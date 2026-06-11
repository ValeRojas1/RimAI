import json
import logging
from datetime import datetime
from typing import List, Optional, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.scq_repository import ISCQRepository
from app.domain.entities.cuestionario_scq import CuestionarioSCQ, NivelIndicioSCQ
from app.infrastructure.database import get_connection

logger = logging.getLogger(__name__)


class PostgresSCQRepository(ISCQRepository):
    """Persiste SCQ en ninos.perfil_sensorial (JSONB existente, sin cambio de esquema)."""

    def save_scq(self, scq: CuestionarioSCQ) -> CuestionarioSCQ:
        patient_id = str(scq.patient_id)
        nivel_str = (
            scq.nivel_indicio.value
            if isinstance(scq.nivel_indicio, NivelIndicioSCQ)
            else str(scq.nivel_indicio)
        )

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                    (patient_id,),
                )
                row = cur.fetchone()
                if not row:
                    raise ValueError(f"Niño no encontrado: {patient_id}")

                perfil = row["perfil_sensorial"] or {}
                triaje = perfil.get("triaje") or {}
                triaje.update(
                    {
                        "requiere_scq": True,
                        "scq_completado": True,
                        "autorizado_envio_terapeuta": False,
                        "scq": {
                            "puntaje_total": scq.puntaje_total,
                            "nivel_indicio": nivel_str,
                            "respuestas": scq.respuestas,
                            "acepto_disclaimer": scq.acepto_disclaimer,
                            "fecha": datetime.utcnow().isoformat(),
                            "uso_no_diagnostico": True,
                        },
                    }
                )
                perfil["triaje"] = triaje
                cur.execute(
                    "UPDATE ninos SET perfil_sensorial = %s::jsonb WHERE id = %s",
                    (Json(perfil), patient_id),
                )

        scq.created_at = datetime.utcnow()
        return scq

    def get_by_patient_id(self, patient_id: Union[int, str]) -> Optional[CuestionarioSCQ]:
        pid = str(patient_id)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                    (pid,),
                )
                row = cur.fetchone()
                if not row:
                    return None
                perfil = row["perfil_sensorial"] or {}
                triaje = perfil.get("triaje") or {}
                scq_data = triaje.get("scq")
                if not scq_data:
                    return None
                nivel_raw = scq_data.get("nivel_indicio", "Bajo")
                return CuestionarioSCQ(
                    patient_id=pid,
                    tutor_id="",
                    respuestas=scq_data.get("respuestas", []),
                    puntaje_total=scq_data.get("puntaje_total"),
                    nivel_indicio=NivelIndicioSCQ(nivel_raw),
                    acepto_disclaimer=bool(scq_data.get("acepto_disclaimer", False)),
                )

    def authorize_send_to_therapist(self, patient_id: str, tutor_user_id: str) -> None:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT n.id, n.perfil_sensorial
                    FROM ninos n
                    JOIN padres_tutores pt ON pt.id = n.tutor_id
                    WHERE n.id = %s AND pt.usuario_id = %s AND n.activo = TRUE
                    """,
                    (patient_id, tutor_user_id),
                )
                nino = cur.fetchone()
                if not nino:
                    raise ValueError("Niño no encontrado para este tutor")

                perfil = nino["perfil_sensorial"] or {}
                triaje = perfil.get("triaje") or {}
                if triaje.get("requiere_scq") and not triaje.get("scq_completado"):
                    raise ValueError(
                        "Debe completar el SCQ antes de enviar el caso al terapeuta."
                    )

                triaje["autorizado_envio_terapeuta"] = True
                triaje["fecha_autorizacion_envio"] = datetime.utcnow().isoformat()
                perfil["triaje"] = triaje
                cur.execute(
                    """
                    UPDATE ninos
                    SET perfil_sensorial = %s::jsonb,
                        estado_clinico = 'pendiente_asignacion'
                    WHERE id = %s
                    """,
                    (Json(perfil), patient_id),
                )

    def verify_tutor_owns_patient(self, patient_id: str, tutor_user_id: str) -> bool:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT 1 FROM ninos n
                    JOIN padres_tutores pt ON pt.id = n.tutor_id
                    WHERE n.id = %s AND pt.usuario_id = %s AND n.activo = TRUE
                    """,
                    (patient_id, tutor_user_id),
                )
                return cur.fetchone() is not None
