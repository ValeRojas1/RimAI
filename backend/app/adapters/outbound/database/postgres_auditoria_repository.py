import json
import uuid
from datetime import datetime
from typing import List, Optional, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.auditoria_repository import IAuditoriaRepository
from app.domain.entities.log_trazabilidad import LogTrazabilidad
from app.infrastructure.database import get_connection


class PostgresAuditoriaRepository(IAuditoriaRepository):
    """Registra acciones en logs_auditoria (esquema existente)."""

    def log_action(self, log: LogTrazabilidad) -> LogTrazabilidad:
        payload_nuevo = log.payload_nuevo
        if isinstance(payload_nuevo, dict):
            payload_json = Json(payload_nuevo)
        else:
            try:
                payload_json = Json(json.loads(payload_nuevo))
            except (TypeError, json.JSONDecodeError):
                payload_json = Json({"raw": str(payload_nuevo)})

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO logs_auditoria (
                        usuario_id, rol_usuario, accion, entidad_afectada,
                        entidad_id, payload_nuevo, timestamp_servidor
                    )
                    VALUES (%s, %s, %s, %s, %s, %s::jsonb, COALESCE(%s, NOW()))
                    RETURNING id
                    """,
                    (
                        str(log.usuario_id) if log.usuario_id else None,
                        log.rol_usuario,
                        log.accion,
                        log.entidad_afectada,
                        str(log.entidad_id),
                        payload_json,
                        log.timestamp_servidor,
                    ),
                )
                row = cur.fetchone()
                log.id = str(row["id"]) if row else None

        if not log.timestamp_servidor:
            log.timestamp_servidor = datetime.utcnow()
        return log
