"""
dashboard_controller.py
-----------------------
Endpoints que consume el panel Flutter en el lado del terapeuta y la familia.

Rutas expuestas (prefijo /api/dashboard):
  GET  /resumen                            -> DashboardData del terapeuta logueado
  GET  /terapeuta/pendientes               -> Niños sin terapeuta asignado
  POST /terapeuta/vincular-paciente        -> Vincular niño a terapeuta por email/código
  POST /terapeuta/vincular/{nino_id}       -> Vincular niño a terapeuta por id directo
  GET  /familia/resumen                    -> DashboardData del tutor logueado
  POST /familia/paciente                   -> Registrar niño desde la app familiar
  POST /dashboard/paciente/{nino_id}/plan/generar -> Generar plan IA para un niño

Rutas adicionales sin prefijo /dashboard:
  GET  /api/ninos/{nino_id}                -> Perfil completo del niño
  GET  /api/ninos/{nino_id}/plan           -> Plan activo de un niño
  GET  /api/ninos/{nino_id}/progreso       -> Métricas de progreso clínico
  PATCH /api/ninos/{nino_id}/perfil-clinico -> Actualizar perfil clínico
  GET  /api/ia/asistente/{nino_id}         -> Datos del asistente IA para un niño
"""

import json
import os
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import psycopg2
from psycopg2.extras import Json, RealDictCursor
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from app.adapters.inbound.api.dependencies import get_current_user
from app.adapters.outbound.storage.cloud_storage_adapter import CloudStorageAdapter
from app.ai.motor import motor_adaptativo

router = APIRouter(tags=["dashboard"])

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
)


def _conn():
    return psycopg2.connect(DATABASE_URL)


# ── Pydantic models ────────────────────────────────────────────────────────────

class VincularPacienteRequest(BaseModel):
    email: Optional[str] = None
    nino_id: Optional[str] = None
    nombre: Optional[str] = None


class RegistrarNinoRequest(BaseModel):
    nombre: str
    fecha_nacimiento: str          # "YYYY-MM-DD"
    nivel_cognitivo: Optional[str] = "Bajo"
    diagnostico: Optional[str] = None
    intereses: Optional[List[str]] = []
    estimulos_aversivos: Optional[Dict[str, Any]] = {}
    hitos: Optional[Dict[str, Any]] = {}
    sensorial: Optional[Dict[str, Any]] = {}
    rutinas_regulacion: Optional[List[str]] = []
    documentos_clinicos: Optional[Dict[str, Any]] = {}
    medicacion_actual: Optional[str] = None


class ActividadRequest(BaseModel):
    nombre: str
    categoria: str
    nivel_dificultad: str
    duracion_estimada: int
    materiales: Optional[List[str]] = []
    instrucciones: str
    plan_id: Optional[str] = None


class ResultadoActividadRequest(BaseModel):
    actividad_id: str
    aciertos: int
    repeticiones: int
    tiempo_respuesta: Optional[float] = 0
    nivel_ayuda_requerido: Optional[int] = 0
    nivel_dificultad_usado: Optional[str] = "Medio"
    observaciones: Optional[str] = None


class CrearSesionRequest(BaseModel):
    nino_id: str
    plan_id: str
    resultados: List[ResultadoActividadRequest]


# ── Helpers ────────────────────────────────────────────────────────────────────

def _calc_edad(fecha_nac) -> int:
    if fecha_nac is None:
        return 0
    hoy = date.today()
    if isinstance(fecha_nac, str):
        fecha_nac = date.fromisoformat(fecha_nac)
    if isinstance(fecha_nac, datetime):
        fecha_nac = fecha_nac.date()
    return hoy.year - fecha_nac.year - (
        (hoy.month, hoy.day) < (fecha_nac.month, fecha_nac.day)
    )


def _has_clinical_evidence(req: RegistrarNinoRequest) -> bool:
    documentos = req.documentos_clinicos or {}
    has_docs = any(bool(v) for v in documentos.values())
    return bool((req.diagnostico or "").strip() or (req.medicacion_actual or "").strip() or has_docs)


def _triaje_from_perfil(perfil: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not perfil:
        return {}
    triaje = perfil.get("triaje")
    return triaje if isinstance(triaje, dict) else {}


def _documentos_from_req(
    existentes: Optional[Dict[str, Any]],
    nuevos: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    documentos = dict(existentes or {})
    for key, value in (nuevos or {}).items():
        if not value:
            documentos.pop(key, None)
            continue
        if (
            key in documentos
            and isinstance(documentos[key], dict)
            and isinstance(value, str)
            and documentos[key].get("nombre") == value
        ):
            continue
        documentos[key] = value
    return documentos


def _build_perfil_familiar(
    req: RegistrarNinoRequest,
    perfil_actual: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    perfil_actual = perfil_actual or {}
    triaje_actual = _triaje_from_perfil(perfil_actual)
    documentos = _documentos_from_req(
        perfil_actual.get("documentos_clinicos"),
        req.documentos_clinicos,
    )
    evidencia_clinica = bool(
        (req.diagnostico or "").strip()
        or (req.medicacion_actual or "").strip()
        or any(bool(v) for v in documentos.values())
    )
    scq_completado = bool(triaje_actual.get("scq_completado", False))
    envio_previo = bool(triaje_actual.get("autorizado_envio_terapeuta", False))

    triaje = {
        "tiene_evidencia_clinica": evidencia_clinica,
        "requiere_scq": not evidencia_clinica,
        "scq_completado": scq_completado,
        "autorizado_envio_terapeuta": evidencia_clinica or (scq_completado and envio_previo),
        "uso_no_diagnostico": True,
    }
    if isinstance(triaje_actual.get("scq"), dict):
        triaje["scq"] = triaje_actual["scq"]

    return {
        "hitos": req.hitos or {},
        "sensorial": req.sensorial or {},
        "intereses": req.intereses or [],
        "estimulosAversivos": req.estimulos_aversivos or {},
        "rutinas_regulacion": req.rutinas_regulacion or [],
        "documentos_clinicos": documentos,
        "medicacion_actual": req.medicacion_actual,
        "umbralSensorial": perfil_actual.get("umbralSensorial", "medio"),
        "preferenciasEntorno": perfil_actual.get("preferenciasEntorno", []),
        "triaje": triaje,
    }


def _normalize_dificultad(value: Optional[str]) -> str:
    dificultad = (value or "Medio").strip().capitalize()
    return dificultad if dificultad in ("Bajo", "Medio", "Alto") else "Medio"


def _ajustar_nivel(actual: str, direccion: str) -> Optional[str]:
    niveles = ["Bajo", "Medio", "Alto"]
    actual = _normalize_dificultad(actual)
    index = niveles.index(actual)
    if direccion == "aumentar" and index < len(niveles) - 1:
        return niveles[index + 1]
    if direccion == "reducir" and index > 0:
        return niveles[index - 1]
    return None


def _evaluar_ajuste_dificultad(
    cur,
    nino_id: str,
    plan_id: str,
    actividad_id: str,
) -> Optional[Dict[str, Any]]:
    cur.execute(
        """
        SELECT
            ra.aciertos,
            ra.repeticiones,
            ra.nivel_dificultad_usado,
            a.nombre AS actividad_nombre,
            pt.terapeuta_id,
            pt.nivel_dificultad_actual
        FROM resultados_actividad ra
        JOIN sesiones s ON s.id = ra.sesion_id
        JOIN actividades a ON a.id = ra.actividad_id
        JOIN planes_terapeuticos pt ON pt.id = s.plan_id
        WHERE s.nino_id = %s
          AND s.plan_id = %s
          AND ra.actividad_id = %s
          AND s.estado = 'completada'
        ORDER BY ra.timestamp DESC
        LIMIT 3
        """,
        (nino_id, plan_id, actividad_id),
    )
    rows = cur.fetchall()
    if len(rows) < 2:
        return None

    total_intentos = sum(r["repeticiones"] or 0 for r in rows)
    if total_intentos <= 0:
        return None

    total_aciertos = sum(r["aciertos"] or 0 for r in rows)
    tasa = round(total_aciertos / total_intentos, 4)
    direccion = None
    accion = None
    if tasa >= 0.8:
        direccion = "aumentar"
        accion = "AUMENTAR_DIFICULTAD"
    elif tasa < 0.4:
        direccion = "reducir"
        accion = "REDUCIR_DIFICULTAD"

    if not direccion or not accion:
        return None

    actual = _normalize_dificultad(rows[0]["nivel_dificultad_actual"])
    sugerida = _ajustar_nivel(actual, direccion)
    if not sugerida:
        return None

    payload = {
        "actividad_id": actividad_id,
        "actividad_nombre": rows[0]["actividad_nombre"],
        "tasa_aciertos": tasa,
        "muestras": len(rows),
        "umbral_superior": 0.8,
        "umbral_inferior": 0.4,
        "dificultad_actual": actual,
        "dificultad_sugerida": sugerida,
    }
    cur.execute(
        """
        UPDATE planes_terapeuticos
        SET nivel_dificultad_actual = %s,
            criterios_progresion = COALESCE(criterios_progresion, '{}'::jsonb) || %s::jsonb
        WHERE id = %s
        """,
        (
            sugerida,
            Json({"ultimo_ajuste": payload}),
            plan_id,
        ),
    )
    cur.execute(
        """
        INSERT INTO decisiones_clinicas
            (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id, created_at
        """,
        (
            rows[0]["terapeuta_id"],
            nino_id,
            f"ajuste_dificultad:{plan_id}:{actividad_id}",
            accion,
            json.dumps(payload, ensure_ascii=False),
        ),
    )
    decision = cur.fetchone()
    return {
        **payload,
        "accion": direccion,
        "registrado": True,
        "decision_id": str(decision["id"]),
        "created_at": decision["created_at"].isoformat(),
    }


def _extract_words(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return " ".join(_extract_words(v) for v in value.values())
    if isinstance(value, list):
        return " ".join(_extract_words(v) for v in value)
    return str(value)


def _score_actividad(act: Dict[str, Any], nino: Dict[str, Any], dificultad: str) -> int:
    perfil = nino.get("perfil_sensorial") or {}
    objetivos = nino.get("objetivos_intervencion") or []
    texto_perfil = _extract_words(perfil).lower()
    texto_objetivos = _extract_words(objetivos).lower()
    texto_act = " ".join(
        [
            str(act.get("tipo") or ""),
            str(act.get("nombre") or ""),
            str(act.get("instrucciones") or ""),
        ]
    ).lower()

    score = 0
    if act.get("nivel_dificultad") == dificultad:
        score += 8
    elif dificultad == "Medio":
        score += 3
    elif act.get("nivel_dificultad") == "Medio":
        score += 2

    if any(w in texto_objetivos for w in ("comunicacion", "lenguaje", "verbal", "social")):
        if any(w in texto_act for w in ("comunicacion", "turnos", "social", "lenguaje")):
            score += 6
    if any(w in texto_objetivos for w in ("atencion", "conjunta", "seguimiento")):
        if any(w in texto_act for w in ("atencion", "seguimiento", "visual", "clasificacion")):
            score += 6
    if any(w in texto_objetivos for w in ("regulacion", "emocional", "transicion")):
        if any(w in texto_act for w in ("regulacion", "emocional", "calma", "respiracion", "sensorial")):
            score += 6

    if any(w in texto_perfil for w in ("ruidos fuertes", "auditiv", "licuadora", "sirenas")):
        if any(w in texto_act for w in ("musica", "sonido", "ritmica", "auditiv")):
            score -= 8
        if any(w in texto_act for w in ("visual", "calma", "presion", "propiocept")):
            score += 4
    if any(w in texto_perfil for w in ("movimiento constante", "presion profunda", "morder objetos")):
        if any(w in texto_act for w in ("movimiento", "propiocept", "presion", "motor")):
            score += 4
    if any(w in texto_perfil for w in ("luces brillantes", "visual")):
        if any(w in texto_act for w in ("luz", "visual", "colores")):
            score -= 2

    return score


# ── GET /api/dashboard/resumen ─────────────────────────────────────────────────

@router.get("/api/dashboard/resumen")
def resumen_terapeuta(current_user: dict = Depends(get_current_user)):
    """Devuelve el resumen del dashboard para el terapeuta autenticado."""
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # 1. Datos del terapeuta
            cur.execute(
                """
                SELECT u.nombre, t.id AS terapeuta_id
                FROM usuarios u
                JOIN terapeutas t ON t.usuario_id = u.id
                WHERE u.id = %s
                """,
                (user_id,),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Terapeuta no encontrado")

            terapeuta_id = str(ter["terapeuta_id"])

            # 2. Pacientes activos asignados
            cur.execute(
                """
                SELECT
                    n.id,
                    n.nombre,
                    n.fecha_nacimiento,
                    n.nivel_cognitivo,
                    n.estado_clinico,
                    pt.id   AS plan_activo_id,
                    pt.nombre AS plan_activo,
                    s.fecha_inicio AS ultima_sesion_fecha,
                    s.estado        AS ultima_sesion_estado,
                    (
                        SELECT ROUND(
                            CAST(SUM(ra.aciertos) AS NUMERIC) /
                            NULLIF(SUM(ra.repeticiones), 0), 4
                        )
                        FROM resultados_actividad ra
                        WHERE ra.sesion_id = s.id
                    ) AS tasa_aciertos
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                LEFT JOIN sesiones s
                    ON s.id = (
                        SELECT id FROM sesiones
                        WHERE nino_id = n.id
                        ORDER BY fecha_inicio DESC
                        LIMIT 1
                    )
                WHERE n.terapeuta_id = %s AND n.activo = TRUE
                ORDER BY n.nombre
                """,
                (terapeuta_id,),
            )
            ninos = cur.fetchall()

            # 3. Sesiones esta semana
            cur.execute(
                """
                SELECT COUNT(*) AS cnt
                FROM sesiones s
                JOIN ninos n ON n.id = s.nino_id
                WHERE n.terapeuta_id = %s
                  AND s.fecha_inicio >= date_trunc('week', NOW())
                """,
                (terapeuta_id,),
            )
            sesiones_semana = cur.fetchone()["cnt"] or 0

            # 4. Alertas de baja adherencia (simplificado: sesiones con tasa < 0.7)
            cur.execute(
                """
                SELECT COUNT(DISTINCT n.id) AS cnt
                FROM ninos n
                JOIN sesiones s ON s.nino_id = n.id
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE n.terapeuta_id = %s
                  AND n.activo = TRUE
                GROUP BY n.id
                HAVING ROUND(
                    CAST(SUM(ra.aciertos) AS NUMERIC) /
                    NULLIF(SUM(ra.repeticiones), 0), 2
                ) < 0.7
                """,
                (terapeuta_id,),
            )
            alertas_rows = cur.fetchall()
            alertas = len(alertas_rows)

    pacientes_list = []
    for n in ninos:
        pacientes_list.append(
            {
                "id": str(n["id"]),
                "nombre": n["nombre"],
                "edad": _calc_edad(n["fecha_nacimiento"]),
                "nivel_cognitivo": n["nivel_cognitivo"] or "Sin datos",
                "estado_clinico": n["estado_clinico"] or "activo",
                "plan_activo": n["plan_activo"],
                "plan_activo_id": str(n["plan_activo_id"]) if n["plan_activo_id"] else None,
                "ultima_sesion": {
                    "fecha": n["ultima_sesion_fecha"].isoformat()
                    if n["ultima_sesion_fecha"]
                    else None,
                    "tasa_aciertos": float(n["tasa_aciertos"])
                    if n["tasa_aciertos"] is not None
                    else None,
                    "estado": n["ultima_sesion_estado"],
                }
                if n["ultima_sesion_fecha"]
                else None,
            }
        )

    return {
        "terapeuta_id": terapeuta_id,
        "terapeuta_nombre": ter["nombre"],
        "total_pacientes": len(pacientes_list),
        "sesiones_esta_semana": sesiones_semana,
        "alertas_baja_adherencia": alertas,
        "pacientes": pacientes_list,
    }


# ── GET /api/dashboard/terapeuta/pendientes ────────────────────────────────────

@router.get("/api/dashboard/terapeuta/pendientes")
def pacientes_pendientes(current_user: dict = Depends(get_current_user)):
    """Lista de niños sin terapeuta asignado (pendiente_asignacion)."""
    if current_user["role"] not in ("terapeuta", "admin"):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    n.id,
                    n.nombre,
                    n.fecha_nacimiento,
                    n.nivel_cognitivo,
                    n.estado_clinico,
                    n.diagnostico,
                    n.created_at AS fecha_registro,
                    n.perfil_sensorial,
                    u.nombre AS tutor_nombre
                FROM ninos n
                LEFT JOIN padres_tutores pt ON pt.id = n.tutor_id
                LEFT JOIN usuarios u ON u.id = pt.usuario_id
                WHERE n.terapeuta_id IS NULL AND n.activo = TRUE
                  AND (
                    COALESCE(n.perfil_sensorial->'triaje'->>'requiere_scq', 'false') <> 'true'
                    OR COALESCE(n.perfil_sensorial->'triaje'->>'autorizado_envio_terapeuta', 'false') = 'true'
                  )
                ORDER BY n.created_at DESC
                """
            )
            rows = cur.fetchall()

    result = []
    for r in rows:
        sensorial = r["perfil_sensorial"] or {}
        hitos = sensorial.get("hitos", {})
        triaje = _triaje_from_perfil(sensorial)
        scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
        result.append(
            {
                "id": str(r["id"]),
                "nombre": r["nombre"],
                "edad": _calc_edad(r["fecha_nacimiento"]),
                "estado_clinico": r["estado_clinico"] or "pendiente_asignacion",
                "fecha_registro": r["fecha_registro"].isoformat()
                if r["fecha_registro"]
                else None,
                "diagnostico": r["diagnostico"],
                "comunicacion": hitos.get("comunicacion"),
                "intereses": sensorial.get("intereses", []),
                "tutor_nombre": r["tutor_nombre"],
                "requiere_scq": triaje.get("requiere_scq", False),
                "scq_completado": triaje.get("scq_completado", False),
                "scq_puntaje": scq.get("puntaje_total"),
                "scq_nivel": scq.get("nivel_indicio"),
                "documentos_clinicos": sensorial.get("documentos_clinicos", {}),
                "medicacion_actual": sensorial.get("medicacion_actual"),
            }
        )
    return result


# ── POST /api/dashboard/terapeuta/vincular-paciente ───────────────────────────

@router.post("/api/dashboard/terapeuta/vincular-paciente")
def vincular_paciente_por_email(
    req: VincularPacienteRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Obtener terapeuta_id
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            if req.nino_id:
                cur.execute(
                    "SELECT id FROM ninos WHERE id = %s AND activo = TRUE",
                    (req.nino_id,),
                )
            elif req.email:
                cur.execute(
                    """
                    SELECT n.id FROM ninos n
                    JOIN padres_tutores pt ON pt.id = n.tutor_id
                    JOIN usuarios u ON u.id = pt.usuario_id
                    WHERE lower(u.email) = lower(%s) AND n.activo = TRUE
                    LIMIT 1
                    """,
                    (req.email,),
                )
            else:
                raise HTTPException(status_code=400, detail="Debe indicar nino_id o email")

            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET terapeuta_id = %s,
                    estado_clinico = 'perfil_clinico_incompleto',
                    vinculado_por = %s,
                    vinculado_at = NOW()
                WHERE id = %s
                """,
                (ter["id"], ter["id"], nino["id"]),
            )

    return {"ok": True, "nino_id": str(nino["id"])}


# ── POST /api/dashboard/terapeuta/vincular/{nino_id} ──────────────────────────

@router.post("/api/dashboard/terapeuta/vincular/{nino_id}")
def vincular_paciente_por_id(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                "SELECT id FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET terapeuta_id = %s,
                    estado_clinico = 'perfil_clinico_incompleto',
                    vinculado_por = %s,
                    vinculado_at = NOW()
                WHERE id = %s
                """,
                (ter["id"], ter["id"], nino["id"]),
            )

    return {"ok": True, "nino_id": nino_id}


# ── GET /api/dashboard/familia/resumen ────────────────────────────────────────

@router.get("/api/dashboard/familia/resumen")
def resumen_familia(current_user: dict = Depends(get_current_user)):
    """Resumen del panel familiar: lista de niños vinculados al tutor."""
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT
                    n.id, n.nombre, n.fecha_nacimiento,
                    n.nivel_cognitivo, n.estado_clinico, n.diagnostico,
                    n.perfil_sensorial,
                    pt.id AS plan_activo_id,
                    pt.nombre AS plan_activo
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                WHERE n.tutor_id = %s AND n.activo = TRUE
                """,
                (tutor["id"],),
            )
            ninos = cur.fetchall()

    pacientes_list = []
    for n in ninos:
        perfil = n["perfil_sensorial"] or {}
        triaje = _triaje_from_perfil(perfil)
        scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
        pacientes_list.append({
            "id": str(n["id"]),
            "nombre": n["nombre"],
            "fecha_nacimiento": n["fecha_nacimiento"].isoformat()
            if n["fecha_nacimiento"]
            else None,
            "edad": _calc_edad(n["fecha_nacimiento"]),
            "nivel_cognitivo": n["nivel_cognitivo"] or "Sin datos",
            "diagnostico": n["diagnostico"],
            "estado_clinico": n["estado_clinico"] or "pendiente_asignacion",
            "plan_activo": n["plan_activo"],
            "plan_activo_id": str(n["plan_activo_id"]) if n["plan_activo_id"] else None,
            "ultima_sesion": None,
            "hitos": perfil.get("hitos", {}),
            "sensorial": perfil.get("sensorial", {}),
            "intereses": perfil.get("intereses", []),
            "estimulos_aversivos": perfil.get("estimulosAversivos", {}),
            "rutinas_regulacion": perfil.get("rutinas_regulacion", []),
            "documentos_clinicos": perfil.get("documentos_clinicos", {}),
            "medicacion_actual": perfil.get("medicacion_actual"),
            "requiere_scq": triaje.get("requiere_scq", False),
            "scq_completado": triaje.get("scq_completado", False),
            "scq_autorizado_envio": triaje.get("autorizado_envio_terapeuta", False),
            "scq_puntaje": scq.get("puntaje_total"),
            "scq_nivel": scq.get("nivel_indicio"),
        })

    return {
        "terapeuta_id": None,
        "terapeuta_nombre": None,
        "total_pacientes": len(pacientes_list),
        "sesiones_esta_semana": 0,
        "alertas_baja_adherencia": 0,
        "pacientes": pacientes_list,
    }


# ── POST /api/dashboard/familia/paciente ──────────────────────────────────────

@router.post("/api/dashboard/familia/paciente")
def registrar_nino(
    req: RegistrarNinoRequest,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            perfil_sensorial = _build_perfil_familiar(req)
            triaje = _triaje_from_perfil(perfil_sensorial)

            cur.execute(
                """
                INSERT INTO ninos (
                    nombre, fecha_nacimiento, nivel_cognitivo,
                    diagnostico, perfil_sensorial, tutor_id, activo, estado_clinico
                )
                VALUES (%s, %s, %s, %s, %s::jsonb, %s, TRUE, 'pendiente_asignacion')
                RETURNING id
                """,
                (
                    req.nombre,
                    req.fecha_nacimiento,
                    req.nivel_cognitivo,
                    req.diagnostico,
                    Json(perfil_sensorial),
                    tutor["id"],
                ),
            )
            nino = cur.fetchone()

    return {
        "id": str(nino["id"]),
        "nombre": req.nombre,
        "requiere_scq": triaje.get("requiere_scq", False),
        "autorizado_envio_terapeuta": triaje.get("autorizado_envio_terapeuta", False),
    }


@router.patch("/api/dashboard/familia/paciente/{nino_id}")
def actualizar_nino_familia(
    nino_id: str,
    req: RegistrarNinoRequest,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT n.id, n.perfil_sensorial
                FROM ninos n
                WHERE n.id = %s
                  AND n.activo = TRUE
                  AND (
                    n.tutor_id = %s
                    OR n.creado_por = %s
                  )
                """,
                (nino_id, tutor["id"], tutor["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil_sensorial = _build_perfil_familiar(req, nino["perfil_sensorial"] or {})
            triaje = _triaje_from_perfil(perfil_sensorial)

            cur.execute(
                """
                UPDATE ninos
                SET nombre = %s,
                    fecha_nacimiento = %s,
                    nivel_cognitivo = %s,
                    diagnostico = %s,
                    perfil_sensorial = %s::jsonb
                WHERE id = %s
                RETURNING id
                """,
                (
                    req.nombre,
                    req.fecha_nacimiento,
                    req.nivel_cognitivo,
                    req.diagnostico,
                    Json(perfil_sensorial),
                    nino_id,
                ),
            )
            updated = cur.fetchone()

    return {
        "id": str(updated["id"]),
        "nombre": req.nombre,
        "requiere_scq": triaje.get("requiere_scq", False),
        "autorizado_envio_terapeuta": triaje.get("autorizado_envio_terapeuta", False),
    }


@router.delete("/api/dashboard/familia/paciente/{nino_id}")
def eliminar_nino_familia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET activo = FALSE
                WHERE id = %s
                  AND activo = TRUE
                  AND (
                    tutor_id = %s
                    OR creado_por = %s
                  )
                RETURNING id
                """,
                (nino_id, tutor["id"], tutor["id"]),
            )
            deleted = cur.fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

    return {"ok": True, "nino_id": str(deleted["id"])}


@router.post("/api/dashboard/familia/paciente/{nino_id}/documento")
def subir_documento_clinico(
    nino_id: str,
    tipo: str = Form(...),
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede adjuntar documentos")

    storage = CloudStorageAdapter()
    file_url = storage.upload_file(file.file, file.filename or "documento", file.content_type or "application/octet-stream")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT n.id, n.perfil_sensorial
                FROM ninos n
                JOIN padres_tutores pt ON pt.id = n.tutor_id
                WHERE n.id = %s
                  AND pt.usuario_id = %s
                  AND n.activo = TRUE
                """,
                (nino_id, current_user["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil = nino["perfil_sensorial"] or {}
            documentos = perfil.get("documentos_clinicos") or {}
            documentos[tipo] = {
                "nombre": file.filename,
                "url": file_url,
                "content_type": file.content_type,
            }
            perfil["documentos_clinicos"] = documentos

            triaje = _triaje_from_perfil(perfil)
            triaje["tiene_evidencia_clinica"] = True
            triaje["requiere_scq"] = False
            triaje["autorizado_envio_terapeuta"] = True
            perfil["triaje"] = triaje

            cur.execute(
                """
                UPDATE ninos
                SET perfil_sensorial = %s::jsonb
                WHERE id = %s
                """,
                (Json(perfil), nino_id),
            )

    return {"ok": True, "tipo": tipo, "url": file_url}


# ── Actividades ocupacionales del terapeuta ───────────────────────────────────

@router.get("/api/dashboard/terapeuta/actividades")
def listar_actividades_ocupacionales(
    plan_id: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("terapeuta", "admin"):
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden listar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if plan_id:
                cur.execute(
                    """
                    SELECT id FROM planes_terapeuticos
                    WHERE id = %s AND activo = TRUE
                    """,
                    (plan_id,),
                )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Plan activo no encontrado")

            cur.execute(
                """
                SELECT
                    a.id, a.tipo, a.nombre, a.instrucciones,
                    a.nivel_dificultad, a.duracion_estimada,
                    a.recursos_multimedia,
                    CASE WHEN pa.actividad_id IS NULL THEN FALSE ELSE TRUE END AS asociado
                FROM actividades a
                LEFT JOIN plan_actividades pa
                  ON pa.actividad_id = a.id
                 AND (%s::uuid IS NOT NULL AND pa.plan_id = %s::uuid)
                WHERE a.activo = TRUE
                ORDER BY a.nombre
                """,
                (plan_id, plan_id),
            )
            rows = cur.fetchall()

    return [
        {
            "id": str(r["id"]),
            "categoria": r["tipo"],
            "tipo": r["tipo"],
            "nombre": r["nombre"],
            "instrucciones": r["instrucciones"],
            "nivel_dificultad": r["nivel_dificultad"],
            "duracion_estimada": r["duracion_estimada"],
            "materiales": (r["recursos_multimedia"] or {}).get("materiales", []),
            "asociado": r["asociado"],
        }
        for r in rows
    ]


@router.post("/api/dashboard/terapeuta/actividades")
def crear_actividad_ocupacional(
    req: ActividadRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden registrar actividades")

    if not req.nombre.strip() or not req.categoria.strip() or not req.instrucciones.strip():
        raise HTTPException(status_code=400, detail="Nombre, categoría e instrucciones son obligatorios")
    if req.duracion_estimada <= 0:
        raise HTTPException(status_code=400, detail="La duración debe ser mayor a cero")

    dificultad = _normalize_dificultad(req.nivel_dificultad)
    materiales = [m.strip() for m in (req.materiales or []) if m and m.strip()]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            if req.plan_id:
                cur.execute(
                    """
                    SELECT id FROM planes_terapeuticos
                    WHERE id = %s
                      AND terapeuta_id = %s
                      AND activo = TRUE
                    """,
                    (req.plan_id, ter["id"]),
                )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

            cur.execute(
                """
                INSERT INTO actividades (
                    tipo, nombre, instrucciones, nivel_dificultad,
                    duracion_estimada, recursos_multimedia, activo
                )
                VALUES (%s, %s, %s, %s, %s, %s::jsonb, TRUE)
                RETURNING id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada, recursos_multimedia
                """,
                (
                    req.categoria.strip(),
                    req.nombre.strip(),
                    req.instrucciones.strip(),
                    dificultad,
                    req.duracion_estimada,
                    Json({"materiales": materiales}),
                ),
            )
            actividad = cur.fetchone()

            asociado = False
            if req.plan_id:
                cur.execute(
                    "SELECT COALESCE(MAX(orden), 0) + 1 AS orden FROM plan_actividades WHERE plan_id = %s",
                    (req.plan_id,),
                )
                orden = cur.fetchone()["orden"]
                cur.execute(
                    """
                    INSERT INTO plan_actividades (plan_id, actividad_id, orden)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (plan_id, actividad_id) DO UPDATE SET orden = EXCLUDED.orden
                    """,
                    (req.plan_id, actividad["id"], orden),
                )
                asociado = True

    return {
        "id": str(actividad["id"]),
        "categoria": actividad["tipo"],
        "tipo": actividad["tipo"],
        "nombre": actividad["nombre"],
        "instrucciones": actividad["instrucciones"],
        "nivel_dificultad": actividad["nivel_dificultad"],
        "duracion_estimada": actividad["duracion_estimada"],
        "materiales": (actividad["recursos_multimedia"] or {}).get("materiales", []),
        "asociado": asociado,
    }


@router.post("/api/dashboard/terapeuta/planes/{plan_id}/actividades/{actividad_id}")
def asociar_actividad_a_plan(
    plan_id: str,
    actividad_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden asociar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT id FROM planes_terapeuticos
                WHERE id = %s AND terapeuta_id = %s AND activo = TRUE
                """,
                (plan_id, ter["id"]),
            )
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

            cur.execute(
                "SELECT id FROM actividades WHERE id = %s AND activo = TRUE",
                (actividad_id,),
            )
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail="Actividad no encontrada")

            cur.execute(
                "SELECT COALESCE(MAX(orden), 0) + 1 AS orden FROM plan_actividades WHERE plan_id = %s",
                (plan_id,),
            )
            orden = cur.fetchone()["orden"]
            cur.execute(
                """
                INSERT INTO plan_actividades (plan_id, actividad_id, orden)
                VALUES (%s, %s, %s)
                ON CONFLICT (plan_id, actividad_id) DO NOTHING
                """,
                (plan_id, actividad_id, orden),
            )

    return {"ok": True, "plan_id": plan_id, "actividad_id": actividad_id}


# ── GET /api/ninos/{nino_id}/plan ─────────────────────────────────────────────

@router.get("/api/ninos/{nino_id}/plan")
def obtener_plan_activo(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    pt.id, pt.nombre, pt.nino_id, n.nombre AS nino_nombre,
                    pt.nivel_dificultad_actual
                FROM planes_terapeuticos pt
                JOIN ninos n ON n.id = pt.nino_id
                WHERE pt.nino_id = %s AND pt.activo = TRUE
                ORDER BY pt.fecha_inicio DESC
                LIMIT 1
                """,
                (nino_id,),
            )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado")

            cur.execute(
                """
                SELECT a.id, a.nombre, a.tipo, a.instrucciones,
                       a.nivel_dificultad, a.duracion_estimada,
                       a.recursos_multimedia
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                ORDER BY pa.orden
                """,
                (plan["id"],),
            )
            actividades = cur.fetchall()

    return {
        "id": str(plan["id"]),
        "nombre": plan["nombre"],
        "nino_id": str(plan["nino_id"]),
        "nino_nombre": plan["nino_nombre"],
        "nivel_dificultad_actual": plan["nivel_dificultad_actual"],
        "actividades": [
            {
                "id": str(a["id"]),
                "nombre": a["nombre"],
                "tipo": a["tipo"],
                "instrucciones": a["instrucciones"],
                "nivel_dificultad": a["nivel_dificultad"],
                "duracion_estimada": a["duracion_estimada"],
                "materiales": (a["recursos_multimedia"] or {}).get("materiales", []),
            }
            for a in actividades
        ],
    }


# ── POST /api/sesiones ───────────────────────────────────────────────────────
# Guarda resultados de actividades y registra ajustes adaptativos de dificultad.

@router.post("/api/sesiones")
def crear_sesion(
    req: CrearSesionRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden registrar sesiones")
    if not req.resultados:
        raise HTTPException(status_code=400, detail="La sesion debe incluir resultados")

    for resultado in req.resultados:
        if resultado.repeticiones <= 0:
            raise HTTPException(status_code=400, detail="Las repeticiones deben ser mayores a cero")
        if resultado.aciertos < 0 or resultado.aciertos > resultado.repeticiones:
            raise HTTPException(status_code=400, detail="Los aciertos no pueden exceder las repeticiones")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT pt.id, pt.nino_id, pt.nivel_dificultad_actual
                FROM planes_terapeuticos pt
                JOIN terapeutas t ON t.id = pt.terapeuta_id
                WHERE pt.id = %s
                  AND pt.nino_id = %s
                  AND pt.activo = TRUE
                  AND t.usuario_id = %s
                """,
                (req.plan_id, req.nino_id, current_user["id"]),
            )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado para el terapeuta")

            cur.execute(
                """
                INSERT INTO sesiones
                    (nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at)
                VALUES (%s, %s, NOW(), NOW(), 'completada', NOW())
                RETURNING id
                """,
                (req.nino_id, req.plan_id),
            )
            sesion = cur.fetchone()

            ajustes = []
            total_aciertos = 0
            total_intentos = 0
            for resultado in req.resultados:
                dificultad = _normalize_dificultad(resultado.nivel_dificultad_usado)
                total_aciertos += resultado.aciertos
                total_intentos += resultado.repeticiones
                cur.execute(
                    """
                    INSERT INTO resultados_actividad
                        (sesion_id, actividad_id, tiempo_respuesta, aciertos, repeticiones,
                         nivel_ayuda_requerido, nivel_dificultad_usado, observaciones)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        sesion["id"],
                        resultado.actividad_id,
                        resultado.tiempo_respuesta,
                        resultado.aciertos,
                        resultado.repeticiones,
                        resultado.nivel_ayuda_requerido or 0,
                        dificultad,
                        resultado.observaciones,
                    ),
                )

                ajuste = _evaluar_ajuste_dificultad(
                    cur,
                    req.nino_id,
                    req.plan_id,
                    resultado.actividad_id,
                )
                if ajuste:
                    ajustes.append(ajuste)

    tasa = round(total_aciertos / total_intentos, 4) if total_intentos else 0
    nivel_recomendado = ajustes[-1]["dificultad_sugerida"] if ajustes else plan["nivel_dificultad_actual"]
    return {
        "ok": True,
        "sesion_id": str(sesion["id"]),
        "total_aciertos": total_aciertos,
        "total_intentos": total_intentos,
        "tasa_aciertos": tasa,
        "nivel_dificultad_recomendado": nivel_recomendado,
        "ajustes_dificultad": ajustes,
    }


@router.get("/api/ninos/{nino_id}/ajustes-dificultad")
def obtener_ajustes_dificultad(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden ver ajustes")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT dc.id, dc.accion, dc.observacion, dc.created_at
                FROM decisiones_clinicas dc
                JOIN terapeutas t ON t.id = dc.terapeuta_id
                WHERE dc.nino_id = %s
                  AND t.usuario_id = %s
                  AND dc.accion IN ('AUMENTAR_DIFICULTAD', 'REDUCIR_DIFICULTAD')
                ORDER BY dc.created_at DESC
                LIMIT 20
                """,
                (nino_id, current_user["id"]),
            )
            rows = cur.fetchall()

    ajustes = []
    for row in rows:
        try:
            detalle = json.loads(row["observacion"] or "{}")
        except json.JSONDecodeError:
            detalle = {"observacion": row["observacion"]}
        ajustes.append(
            {
                "id": str(row["id"]),
                "accion": "aumentar" if row["accion"] == "AUMENTAR_DIFICULTAD" else "reducir",
                "created_at": row["created_at"].isoformat(),
                **detalle,
            }
        )
    return {"ajustes": ajustes}


# ── PATCH /api/ninos/{nino_id}/perfil-clinico ─────────────────────────────────

@router.patch("/api/ninos/{nino_id}/perfil-clinico")
def actualizar_perfil_clinico(
    nino_id: str,
    datos: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    campos_permitidos = {"nivel_cognitivo", "diagnostico", "perfil_sensorial",
                         "objetivos_intervencion", "estado_clinico"}
    updates = {k: v for k, v in datos.items() if k in campos_permitidos}
    observaciones = datos.get("observaciones_clinicas")

    if observaciones:
        perfil = updates.get("perfil_sensorial") or {}
        if isinstance(perfil, dict):
            perfil["observaciones_clinicas"] = observaciones
            updates["perfil_sensorial"] = perfil

    if updates.get("objetivos_intervencion") and updates.get("perfil_sensorial"):
        updates["estado_clinico"] = "listo_para_plan"

    if not updates:
        raise HTTPException(status_code=400, detail="Sin campos válidos para actualizar")

    set_clauses = []
    values = []
    for key, value in updates.items():
        if key == "perfil_sensorial":
            set_clauses.append(f"{key} = %s::jsonb")
            values.append(Json(value))
        else:
            set_clauses.append(f"{key} = %s")
            values.append(value)

    if updates.get("estado_clinico") == "listo_para_plan":
        set_clauses.append("perfil_completado_at = NOW()")

    values.append(nino_id)

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                f"UPDATE ninos SET {', '.join(set_clauses)} WHERE id = %s RETURNING id, estado_clinico",
                values,
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

    return {
        "ok": True,
        "nino_id": nino_id,
        "estado_clinico": row["estado_clinico"],
        "mensaje": "Perfil clínico guardado correctamente.",
    }


# ── POST /api/dashboard/paciente/{nino_id}/plan/generar ───────────────────────

@router.post("/api/dashboard/paciente/{nino_id}/plan/generar")
def generar_plan_ia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Genera un plan terapéutico para el niño usando la lógica del motor de reglas.
    Versión PMV: asigna las 3 actividades del catálogo respetando el perfil sensorial.
    """
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden generar planes")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT id, nombre, fecha_nacimiento, nivel_cognitivo, perfil_sensorial, objetivos_intervencion, estado_clinico
                FROM ninos
                WHERE id = %s AND activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            # Validar que exista un perfil clínico-funcional completo (GIVEN de la Historia de Usuario)
            perfil_sensorial = nino.get("perfil_sensorial") or {}
            objetivos = nino.get("objetivos_intervencion") or []
            
            # Un perfil se considera completo si tiene fecha de nacimiento, nivel cognitivo/apoyo,
            # y datos de perfil sensorial y objetivos cargados
            if not nino.get("nivel_cognitivo") or not perfil_sensorial or not objetivos:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "mensaje": (
                            "El perfil clínico-funcional del niño está incompleto. "
                            "Por favor, complete el perfil sensorial, el nivel cognitivo y los objetivos "
                            "de intervención antes de generar el plan."
                        )
                    }
                )

            # Verificar si ya tiene plan activo
            cur.execute(
                "SELECT id FROM planes_terapeuticos WHERE nino_id = %s AND activo = TRUE",
                (nino_id,),
            )
            existing = cur.fetchone()

            # Procesar el motor adaptativo Random Forest (WHEN de la Historia de Usuario)
            # El motor procesa edad, nivel_cognitivo (apoyo), perfil_sensorial, y objetivos (habilidades)
            dificultad_ia, confianza = motor_adaptativo.predecir_dificultad(nino)

            # Mapeo de la dificultad del motor (Básico, Intermedio, Avanzado) al ENUM de la base de datos (Bajo, Medio, Alto)
            map_dificultad_db = {
                "Básico": "Bajo",
                "Intermedio": "Medio",
                "Avanzado": "Alto",
            }
            nivel_dificultad_db = map_dificultad_db.get(dificultad_ia, "Medio")

            if existing:
                cur.execute(
                    """
                    UPDATE planes_terapeuticos
                    SET nivel_dificultad_actual = %s,
                        criterios_progresion = %s::jsonb
                    WHERE id = %s
                    RETURNING id
                    """,
                    (
                        nivel_dificultad_db,
                        '{"umbralAciertos": 0.8, "sesionesConsecutivas": 3}',
                        existing["id"],
                    ),
                )
                plan = cur.fetchone()
                cur.execute("DELETE FROM plan_actividades WHERE plan_id = %s", (plan["id"],))
            else:
                cur.execute(
                    """
                    INSERT INTO planes_terapeuticos
                        (nombre, nino_id, terapeuta_id, fecha_inicio, nivel_dificultad_actual,
                         criterios_progresion, activo)
                    VALUES (%s, %s, %s, CURRENT_DATE, %s, %s::jsonb, TRUE)
                    RETURNING id
                    """,
                    (
                        f"Plan IA — {nino['nombre']}",
                        nino_id,
                        ter["id"],
                        nivel_dificultad_db,
                        '{"umbralAciertos": 0.8, "sesionesConsecutivas": 3}',
                    ),
                )
                plan = cur.fetchone()

            # Actualizar el estado clínico del niño a 'plan_activo' para coherencia global
            cur.execute(
                """
                UPDATE ninos
                SET estado_clinico = 'plan_activo'
                WHERE id = %s
                """,
                (nino_id,),
            )

            cur.execute(
                """
                SELECT id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada, recursos_multimedia
                FROM actividades
                WHERE activo = TRUE
                """
            )
            catalogo = cur.fetchall()
            if not catalogo:
                raise HTTPException(
                    status_code=422,
                    detail={"mensaje": "No hay actividades ocupacionales configuradas para generar el plan."},
                )

            acts = sorted(
                catalogo,
                key=lambda a: (
                    -_score_actividad(a, nino, nivel_dificultad_db),
                    a["nombre"],
                ),
            )[: min(3, len(catalogo))]
            for i, act in enumerate(acts, start=1):
                cur.execute(
                    """
                    INSERT INTO plan_actividades (plan_id, actividad_id, orden)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (plan_id, actividad_id) DO NOTHING
                    """,
                    (plan["id"], act["id"], i),
                )

    return {
        "mensaje": "Plan regenerado con éxito" if existing else "Plan generado con éxito",
        "plan_id": str(plan["id"]),
        "nino_id": nino_id,
        "dificultad_inicial": dificultad_ia,
        "confianza_ia": confianza,
    }


# ── GET /api/ninos/{nino_id} ─────────────────────────────────────────────────────
# Perfil completo del niño (usado por TherapeuticProfileScreen)

@router.get("/api/ninos/{nino_id}")
def obtener_perfil_nino(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    n.id, n.nombre, n.fecha_nacimiento, n.nivel_cognitivo,
                    n.diagnostico, n.perfil_sensorial, n.objetivos_intervencion,
                    n.estado_clinico, n.documento_diagnostico,
                    pt.id AS plan_activo_id
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                WHERE n.id = %s AND n.activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

    sensorial = nino["perfil_sensorial"] or {}
    return {
        "id": str(nino["id"]),
        "nombre": nino["nombre"],
        "edad": _calc_edad(nino["fecha_nacimiento"]),
        "diagnostico": nino["diagnostico"],
        "nivel_cognitivo": nino["nivel_cognitivo"] or "Medio",
        "perfil_sensorial": sensorial,
        "objetivos_intervencion": nino["objetivos_intervencion"] or [],
        "intereses": sensorial.get("intereses", []),
        "estimulos_aversivos": sensorial.get("estimulosAversivos", {}),
        "documento_diagnostico": nino["documento_diagnostico"],
        "plan_activo_id": str(nino["plan_activo_id"]) if nino["plan_activo_id"] else None,
        "estado_clinico": nino["estado_clinico"] or "pendiente_asignacion",
    }


# ── GET /api/ninos/{nino_id}/progreso ────────────────────────────────────────────
# Métricas de progreso clínico (usado por ProgressScreen)

@router.get("/api/ninos/{nino_id}/progreso")
def obtener_progreso(
    nino_id: str,
    periodo: str = "Esta semana",
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Filtro de fecha según período
            if periodo == "Esta semana":
                fecha_desde = "date_trunc('week', NOW())"
            elif periodo == "Este mes":
                fecha_desde = "date_trunc('month', NOW())"
            else:
                fecha_desde = "'2000-01-01'::date"

            cur.execute(
                f"""
                SELECT
                    COUNT(DISTINCT s.id) AS sesiones_completadas,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa_aciertos
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s
                  AND s.fecha_inicio >= {fecha_desde}
                  AND s.estado = 'completada'
                """,
                (nino_id,),
            )
            resumen = cur.fetchone()

            # Historia de aciertos por sesión (últimas 8)
            cur.execute(
                """
                SELECT
                    s.id,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s AND s.estado = 'completada'
                GROUP BY s.id, s.fecha_inicio
                ORDER BY s.fecha_inicio DESC
                LIMIT 8
                """,
                (nino_id,),
            )
            historia_rows = cur.fetchall()

    sesiones = resumen["sesiones_completadas"] or 0
    tasa = float(resumen["tasa_aciertos"]) if resumen["tasa_aciertos"] else 0.0
    historia = [float(r["tasa"]) for r in reversed(historia_rows) if r["tasa"] is not None]
    if not historia:
        historia = [0.0]

    # Adherencia simplificada: proporción de sesiones completadas vs esperadas (objetivo 5/semana)
    adherencia = min(1.0, sesiones / 5.0) if periodo == "Esta semana" else min(1.0, tasa)

    return {
        "sesiones_completadas": sesiones,
        "tasa_aciertos": tasa,
        "adherencia": adherencia,
        "historia_aciertos": historia,
    }


# ── GET /api/ia/asistente/{nino_id} ─────────────────────────────────────────────
# Datos para el Asistente IA (usado por IAAssistantScreen)

@router.get("/api/ia/asistente/{nino_id}")
def obtener_asistente_ia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT n.nombre, n.nivel_cognitivo, n.perfil_sensorial
                FROM ninos n
                WHERE n.id = %s AND n.activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            # Obtener actividades del plan activo para generar recomendaciones
            cur.execute(
                """
                SELECT a.id, a.nombre, a.tipo, a.instrucciones, a.nivel_dificultad, a.duracion_estimada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                JOIN planes_terapeuticos pt ON pt.id = pa.plan_id
                WHERE pt.nino_id = %s AND pt.activo = TRUE
                ORDER BY pa.orden
                """,
                (nino_id,),
            )
            actividades = cur.fetchall()

            # Última sesión para calcular carga cognitiva
            cur.execute(
                """
                SELECT
                    ROUND(CAST(SUM(ra.aciertos) AS NUMERIC) / NULLIF(SUM(ra.repeticiones), 0), 4) AS tasa,
                    AVG(ra.tiempo_respuesta) AS tiempo_promedio
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s AND s.estado = 'completada'
                  AND s.fecha_inicio >= NOW() - INTERVAL '7 days'
                """,
                (nino_id,),
            )
            ultima = cur.fetchone()

    tasa = float(ultima["tasa"]) if ultima and ultima["tasa"] else 0.65
    tiempo_prom = float(ultima["tiempo_promedio"]) if ultima and ultima["tiempo_promedio"] else 3.0
    # Carga cognitiva inversa a la tasa de aciertos
    carga = round(max(0.1, min(0.95, 1.0 - tasa)), 2)
    calma = round(min(10.0, 10.0 * tasa), 1)

    # Recomendaciones basadas en las actividades del plan
    recomendaciones = []
    for act in actividades:
        confianza = round(tasa * 0.9 + 0.05, 2) if tasa > 0 else 0.70
        recomendaciones.append({
            "id": str(act["id"]),
            "actividad": act["nombre"],
            "justificacion": act["instrucciones"] or f"Actividad de tipo {act['tipo']} adecuada al perfil del paciente.",
            "confianza": confianza,
            "fecha_respuesta": datetime.utcnow().isoformat(),
            "estado": "PENDIENTE",
            "observacion": None,
        })

    # Plan de sesión sugerido
    plan_sesion = []
    for i, act in enumerate(actividades):
        duracion = act["duracion_estimada"] or 300
        plan_sesion.append({
            "id": str(act["id"]),
            "title": act["nombre"],
            "description": act["instrucciones"] or act["tipo"],
            "duration": f"{duracion // 60} min",
            "has_scanning": False,
        })

    return {
        "nino_id": nino_id,
        "nino_nombre": nino["nombre"],
        "analisis_cognitivo": {
            "carga_cognitiva": carga,
            "foco_estimado": f"{int(15 * tasa)} min",
            "nivel_calma": calma,
        },
        "recomendaciones": recomendaciones,
        "plan_sesion": plan_sesion,
    }
