import json
from datetime import datetime
from typing import List, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.seguimiento_repository import ISeguimientoRepository
from app.domain.entities.actividad_ejecutada import ActividadEjecutada
from app.infrastructure.database import get_connection


class PostgresSeguimientoRepository(ISeguimientoRepository):
    """Lee/escribe actividades ejecutadas en sesiones y resultados_actividad."""

    def save_actividad_ejecutada(self, actividad: ActividadEjecutada) -> ActividadEjecutada:
        nino_id = str(actividad.patient_id)
        plan_id = str(actividad.plan_id)
        actividad_id = str(actividad.actividad_id)
        ts = actividad.timestamp_local or datetime.utcnow()
        estado = "completada" if actividad.completada else "interrumpida"

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO sesiones (nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at)
                    VALUES (%s, %s, %s, %s, %s::estado_sesion, NOW())
                    RETURNING id
                    """,
                    (nino_id, plan_id, ts, ts, estado),
                )
                sesion_id = cur.fetchone()["id"]
                cur.execute(
                    """
                    INSERT INTO resultados_actividad (
                        sesion_id, actividad_id, tiempo_respuesta,
                        aciertos, repeticiones, nivel_ayuda_requerido,
                        observaciones, timestamp
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING id
                    """,
                    (
                        sesion_id,
                        actividad_id,
                        float(actividad.tiempo_empleado_segundos),
                        1 if actividad.completada else 0,
                        1,
                        actividad.nivel_apoyo_requerido,
                        actividad.observaciones or "",
                        ts,
                    ),
                )
                resultado_id = cur.fetchone()["id"]

        actividad.id = actividad.id or str(resultado_id)
        actividad.synced_at = datetime.utcnow()
        return actividad

    def get_by_patient_id(self, patient_id: Union[int, str]) -> List[ActividadEjecutada]:
        nino_id = str(patient_id)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT
                        ra.id,
                        s.nino_id,
                        ra.actividad_id,
                        s.plan_id,
                        COALESCE(ra.tiempo_respuesta, 0) AS tiempo_respuesta,
                        ra.nivel_ayuda_requerido,
                        ra.observaciones,
                        ra.aciertos,
                        ra.repeticiones,
                        COALESCE(ra.timestamp, s.fecha_inicio) AS ts,
                        s.estado
                    FROM sesiones s
                    JOIN resultados_actividad ra ON ra.sesion_id = s.id
                    WHERE s.nino_id = %s
                    ORDER BY ts ASC
                    """,
                    (nino_id,),
                )
                rows = cur.fetchall()

        actividades: List[ActividadEjecutada] = []
        for row in rows:
            repeticiones = int(row["repeticiones"] or 1)
            aciertos = int(row["aciertos"] or 0)
            actividades.append(
                ActividadEjecutada(
                    id=str(row["id"]),
                    patient_id=nino_id,
                    actividad_id=str(row["actividad_id"]),
                    plan_id=str(row["plan_id"]),
                    tiempo_empleado_segundos=int(float(row["tiempo_respuesta"] or 0)),
                    nivel_apoyo_requerido=int(row["nivel_ayuda_requerido"] or 0),
                    observaciones=row["observaciones"] or "",
                    detonantes_presentados=[],
                    completada=(row["estado"] == "completada" or aciertos >= repeticiones),
                    timestamp_local=row["ts"],
                )
            )
        return actividades
