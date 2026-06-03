-- Bloque 8: trazabilidad completa por actor, entidad y nino.

ALTER TABLE logs_auditoria
ADD COLUMN IF NOT EXISTS nino_id UUID REFERENCES ninos(id) ON DELETE SET NULL;

ALTER TABLE logs_auditoria
ADD COLUMN IF NOT EXISTS fecha_evento TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE logs_auditoria
SET fecha_evento = COALESCE(fecha_evento, timestamp_servidor, NOW());

CREATE INDEX IF NOT EXISTS idx_logs_auditoria_nino_fecha
ON logs_auditoria (nino_id, fecha_evento DESC);

CREATE INDEX IF NOT EXISTS idx_logs_auditoria_accion_fecha
ON logs_auditoria (accion, fecha_evento DESC);

CREATE OR REPLACE PROCEDURE sp_registrar_auditoria(
    IN p_usuario_id UUID,
    IN p_rol_usuario TEXT,
    IN p_accion TEXT,
    IN p_entidad_afectada TEXT,
    IN p_entidad_id TEXT,
    IN p_payload_anterior JSONB,
    IN p_payload_nuevo JSONB,
    IN p_ip_origen INET,
    IN p_user_agent TEXT,
    IN p_nino_id UUID,
    OUT p_auditoria JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_log logs_auditoria%ROWTYPE;
BEGIN
    IF p_usuario_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_usuario_id) THEN
        RAISE EXCEPTION 'Usuario % no existe', p_usuario_id USING ERRCODE = 'P0002';
    END IF;

    IF p_nino_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM ninos WHERE id = p_nino_id) THEN
        RAISE EXCEPTION 'Nino % no existe', p_nino_id USING ERRCODE = 'P0002';
    END IF;

    IF NULLIF(TRIM(COALESCE(p_rol_usuario, '')), '') IS NULL THEN
        RAISE EXCEPTION 'rol_usuario es requerido';
    END IF;

    IF NULLIF(TRIM(COALESCE(p_accion, '')), '') IS NULL THEN
        RAISE EXCEPTION 'accion es requerida';
    END IF;

    IF NULLIF(TRIM(COALESCE(p_entidad_afectada, '')), '') IS NULL THEN
        RAISE EXCEPTION 'entidad_afectada es requerida';
    END IF;

    IF NULLIF(TRIM(COALESCE(p_entidad_id, '')), '') IS NULL THEN
        RAISE EXCEPTION 'entidad_id es requerido';
    END IF;

    INSERT INTO logs_auditoria (
        usuario_id,
        rol_usuario,
        accion,
        entidad_afectada,
        entidad_id,
        nino_id,
        payload_anterior,
        payload_nuevo,
        ip_origen,
        user_agent,
        fecha_evento
    )
    VALUES (
        p_usuario_id,
        p_rol_usuario,
        p_accion,
        p_entidad_afectada,
        p_entidad_id,
        p_nino_id,
        p_payload_anterior,
        COALESCE(p_payload_nuevo, '{}'::jsonb),
        p_ip_origen,
        p_user_agent,
        NOW()
    )
    RETURNING * INTO v_log;

    p_auditoria := to_jsonb(v_log);
END;
$$;
