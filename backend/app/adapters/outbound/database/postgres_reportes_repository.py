import uuid
from datetime import datetime
from typing import List, Optional, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.reportes_repository import IReportesRepository
from app.domain.entities.alerta_adherencia import AlertaAdherencia, SeveridadAlerta
from app.domain.entities.reporte_progreso import ReporteAnalitico
from app.infrastructure.database import get_connection


class PostgresReportesRepository(IReportesRepository):
    """Persiste alertas de adherencia en alertas_clinicas; reportes se calculan on-the-fly."""

    def save_alerta(self, alerta: AlertaAdherencia) -> AlertaAdherencia:
        nino_id = str(alerta.patient_id)
        terapeuta_usuario_id = str(alerta.terapeuta_id)
        severidad = alerta.severidad.value if isinstance(alerta.severidad, SeveridadAlerta) else str(alerta.severidad)
        dedupe_key = f"adherencia:{nino_id}:{severidad}:{datetime.utcnow().strftime('%Y-%m-%d')}"

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id FROM terapeutas WHERE usuario_id = %s",
                    (terapeuta_usuario_id,),
                )
                ter_row = cur.fetchone()
                if not ter_row:
                    cur.execute(
                        "SELECT id FROM terapeutas WHERE id = %s",
                        (terapeuta_usuario_id,),
                    )
                    ter_row = cur.fetchone()
                if not ter_row:
                    raise ValueError("Terapeuta no encontrado para registrar alerta de adherencia")

                terapeuta_id = ter_row["id"]
                cur.execute("SELECT tutor_id FROM ninos WHERE id = %s", (nino_id,))
                nino_row = cur.fetchone()

                cur.execute(
                    """
                    INSERT INTO alertas_clinicas (
                        nino_id, terapeuta_id, tutor_id, tipo, severidad,
                        titulo, mensaje, origen, metricas, dedupe_key
                    )
                    VALUES (%s, %s, %s, 'adherencia', %s, %s, %s, 'evaluacion_adherencia',
                            %s::jsonb, %s)
                    ON CONFLICT (dedupe_key) DO UPDATE SET
                        mensaje = EXCLUDED.mensaje,
                        metricas = EXCLUDED.metricas,
                        updated_at = NOW()
                    RETURNING id, created_at
                    """,
                    (
                        nino_id,
                        terapeuta_id,
                        nino_row["tutor_id"] if nino_row else None,
                        severidad,
                        "Alerta de adherencia terapéutica",
                        alerta.mensaje,
                        Json(
                            {
                                "tasa_actual": alerta.tasa_actual,
                                "umbral_minimo": alerta.umbral_minimo,
                            }
                        ),
                        dedupe_key,
                    ),
                )
                row = cur.fetchone()
                alerta.id = str(row["id"])
                alerta.created_at = row["created_at"]

        return alerta

    def get_alertas_by_patient(self, patient_id: Union[int, str]) -> List[AlertaAdherencia]:
        nino_id = str(patient_id)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, nino_id, terapeuta_id, severidad, mensaje,
                           metricas, resuelta, created_at
                    FROM alertas_clinicas
                    WHERE nino_id = %s AND tipo = 'adherencia'
                    ORDER BY created_at DESC
                    """,
                    (nino_id,),
                )
                rows = cur.fetchall()

        alertas = []
        for row in rows:
            metricas = row["metricas"] or {}
            alertas.append(
                AlertaAdherencia(
                    id=str(row["id"]),
                    patient_id=nino_id,
                    terapeuta_id=str(row["terapeuta_id"]),
                    severidad=SeveridadAlerta(row["severidad"]),
                    mensaje=row["mensaje"],
                    tasa_actual=float(metricas.get("tasa_actual", 0)),
                    umbral_minimo=float(metricas.get("umbral_minimo", 0.7)),
                    resuelta=bool(row["resuelta"]),
                    created_at=row["created_at"],
                )
            )
        return alertas

    def save_reporte(self, reporte: ReporteAnalitico) -> ReporteAnalitico:
        return reporte

    def get_reporte_by_patient(self, patient_id: Union[int, str]) -> Optional[ReporteAnalitico]:
        return None
