import json
from datetime import date
from typing import Optional, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.plan_repository import IPlanRepository
from app.domain.entities.plan_terapeutico import EstadoPlan, PlanTerapeutico, SugerenciaActividad
from app.infrastructure.database import get_connection


class PostgresPlanRepository(IPlanRepository):
    """Persiste planes en planes_terapeuticos.criterios_progresion (JSONB existente)."""

    def _resolve_terapeuta_pk(self, cur, terapeuta_ref: Union[int, str]) -> str:
        cur.execute(
            """
            SELECT id FROM terapeutas
            WHERE usuario_id = %s OR id::text = %s
            LIMIT 1
            """,
            (str(terapeuta_ref), str(terapeuta_ref)),
        )
        row = cur.fetchone()
        if not row:
            raise ValueError("Terapeuta no encontrado")
        return str(row["id"])

    def save_plan(self, plan: PlanTerapeutico) -> PlanTerapeutico:
        nino_id = str(plan.patient_id)
        sugerencias_payload = [
            s.model_dump() if hasattr(s, "model_dump") else s.dict()
            for s in plan.sugerencias
        ]
        criterios = {
            "estado_hexagonal": plan.estado.value,
            "sugerencias": sugerencias_payload,
        }

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                terapeuta_pk = self._resolve_terapeuta_pk(cur, plan.terapeuta_id)
                if plan.id:
                    cur.execute(
                        """
                        UPDATE planes_terapeuticos
                        SET criterios_progresion = %s::jsonb,
                            activo = TRUE
                        WHERE id = %s
                        RETURNING id, created_at
                        """,
                        (Json(criterios), str(plan.id)),
                    )
                else:
                    cur.execute(
                        """
                        INSERT INTO planes_terapeuticos (
                            nombre, nino_id, terapeuta_id, fecha_inicio,
                            criterios_progresion, activo
                        )
                        VALUES ('Plan sugerido IA', %s, %s, %s, %s::jsonb, TRUE)
                        RETURNING id, created_at
                        """,
                        (nino_id, terapeuta_pk, date.today(), Json(criterios)),
                    )
                row = cur.fetchone()
                plan.id = str(row["id"])
                plan.created_at = row["created_at"]
        return plan

    def get_plan_by_id(self, plan_id: Union[int, str]) -> Optional[PlanTerapeutico]:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, nino_id, terapeuta_id, criterios_progresion, created_at
                    FROM planes_terapeuticos
                    WHERE id = %s
                    """,
                    (str(plan_id),),
                )
                row = cur.fetchone()
                if not row:
                    return None
                criterios = row["criterios_progresion"] or {}
                sugerencias = [
                    SugerenciaActividad(**s)
                    for s in criterios.get("sugerencias") or []
                ]
                estado_raw = criterios.get("estado_hexagonal", "Borrador")
                return PlanTerapeutico(
                    id=str(row["id"]),
                    patient_id=str(row["nino_id"]),
                    terapeuta_id=str(row["terapeuta_id"]),
                    estado=EstadoPlan(estado_raw),
                    sugerencias=sugerencias,
                    created_at=row["created_at"],
                )
