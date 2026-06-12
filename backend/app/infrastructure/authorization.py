"""Control de acceso por niño/paciente (REM-001, REM-002, REM-006, REM-008)."""
from __future__ import annotations

import os
from typing import Any, Dict, Optional, Set

from fastapi import HTTPException
from psycopg2.extras import RealDictCursor

from app.infrastructure.database import get_connection

CAMPOS_PERFIL_TERAPEUTA: Set[str] = {
    "nivel_cognitivo",
    "diagnostico",
    "perfil_sensorial",
    "objetivos_intervencion",
    "estado_clinico",
}

CAMPOS_PERFIL_TUTOR: Set[str] = {"perfil_sensorial"}


def autorizar_acceso_nino(nino_id: str, current_user: Dict[str, Any]) -> None:
    """Terapeuta/tutor asignado o admin. 404 si no existe; 403 si sin permiso."""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT terapeuta_id, tutor_id FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            acceso = cur.fetchone()
            if not acceso:
                raise HTTPException(status_code=404, detail="Niño no encontrado")
            role = current_user.get("role")
            if role == "terapeuta":
                cur.execute(
                    "SELECT id FROM terapeutas WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                ter = cur.fetchone()
                if not ter or str(acceso["terapeuta_id"]) != str(ter["id"]):
                    raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            elif role in ("padre_tutor", "tutor", "padre"):
                cur.execute(
                    "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                tutor = cur.fetchone()
                if not tutor or str(acceso["tutor_id"]) != str(tutor["id"]):
                    raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            elif role != "admin":
                raise HTTPException(status_code=403, detail="Acceso denegado")


def autorizar_descarga_documento_clinico(
    nino_id: str, current_user: Dict[str, Any]
) -> None:
    """Descarga de PDFs: tutor del nino, terapeuta asignado o terapeuta en bandeja pendiente."""
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT terapeuta_id, tutor_id FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            acceso = cur.fetchone()
            if not acceso:
                raise HTTPException(status_code=404, detail="Documento no encontrado")
            role = current_user.get("role")
            if role == "admin":
                return
            if role == "terapeuta":
                cur.execute(
                    "SELECT id FROM terapeutas WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                ter = cur.fetchone()
                if not ter:
                    raise HTTPException(status_code=403, detail="Acceso denegado al nino")
                if acceso["terapeuta_id"] is None:
                    return
                if str(acceso["terapeuta_id"]) == str(ter["id"]):
                    return
                raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            if role in ("padre_tutor", "tutor", "padre"):
                cur.execute(
                    "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                tutor = cur.fetchone()
                if tutor and str(acceso["tutor_id"]) == str(tutor["id"]):
                    return
                raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            raise HTTPException(status_code=403, detail="Acceso denegado")


def campos_perfil_editables_por_rol(role: str) -> Set[str]:
    if role in ("padre_tutor", "tutor", "padre"):
        return CAMPOS_PERFIL_TUTOR
    return CAMPOS_PERFIL_TERAPEUTA


def verify_tutor_owns_patient(patient_id: str, tutor_user_id: str) -> bool:
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM ninos n
                JOIN padres_tutores pt ON pt.id = n.tutor_id
                WHERE n.id = %s AND pt.usuario_id = %s AND n.activo = TRUE
                """,
                (str(patient_id), str(tutor_user_id)),
            )
            return cur.fetchone() is not None


def verify_terapeuta_assigned_to_patient(patient_id: str, terapeuta_user_id: str) -> bool:
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT 1 FROM ninos n
                JOIN terapeutas t ON t.id = n.terapeuta_id
                WHERE n.id = %s AND t.usuario_id = %s AND n.activo = TRUE
                """,
                (str(patient_id), str(terapeuta_user_id)),
            )
            return cur.fetchone() is not None


def _url_matches_filename(url: str, safe_name: str) -> bool:
    if not url:
        return False
    return url.endswith(safe_name) or safe_name in url


def resolve_nino_id_for_clinical_file(filename: str) -> Optional[str]:
    """Busca el nino_id asociado a un archivo clínico subido (documentos o evaluaciones)."""
    safe_name = os.path.basename(filename)
    if not safe_name:
        return None

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, perfil_sensorial
                FROM ninos
                WHERE activo = TRUE AND perfil_sensorial IS NOT NULL
                """
            )
            for row in cur.fetchall():
                perfil = row["perfil_sensorial"] or {}
                documentos = perfil.get("documentos_clinicos") or {}
                for doc in documentos.values():
                    if isinstance(doc, dict) and _url_matches_filename(
                        doc.get("url", ""), safe_name
                    ):
                        return str(row["id"])
                for ev in perfil.get("evaluaciones_externas") or []:
                    if isinstance(ev, dict) and _url_matches_filename(
                        ev.get("file_url", ""), safe_name
                    ):
                        return str(row["id"])
    return None
