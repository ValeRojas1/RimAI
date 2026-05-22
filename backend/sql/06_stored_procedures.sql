-- ============================================================
-- RimAI - Stored procedures
-- ============================================================
-- Adds clinical reporting and audit procedures over the current
-- PostgreSQL schema. This file is idempotent and can be applied
-- after the base schema and seed files.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS logs_auditoria (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID REFERENCES usuarios(id) ON DELETE SET NULL,
    rol_usuario VARCHAR(50) NOT NULL,
    accion VARCHAR(120) NOT NULL,
    entidad_afectada VARCHAR(120) NOT NULL,
    entidad_id TEXT NOT NULL,
    payload_anterior JSONB,
    payload_nuevo JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_origen INET,
    user_agent TEXT,
    timestamp_servidor TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_logs_auditoria_usuario
    ON logs_auditoria(usuario_id);

CREATE INDEX IF NOT EXISTS idx_logs_auditoria_entidad
    ON logs_auditoria(entidad_afectada, entidad_id);

CREATE INDEX IF NOT EXISTS idx_logs_auditoria_timestamp
    ON logs_auditoria(timestamp_servidor DESC);

-- ------------------------------------------------------------
-- sp_calcular_indicadores_progreso
-- ------------------------------------------------------------
-- Returns a JSONB summary for one child and a period label.
-- Supported periods: 'Esta semana', 'Este mes', any other value
-- is treated as historical.
-- ------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_calcular_indicadores_progreso(
    IN p_nino_id UUID,
    IN p_periodo TEXT,
    OUT p_indicadores JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha_desde TIMESTAMPTZ;
    v_sesiones INT := 0;
    v_actividades INT := 0;
    v_total_aciertos INT := 0;
    v_total_repeticiones INT := 0;
    v_tasa_aciertos NUMERIC := 0;
    v_promedio_ayuda NUMERIC := 0;
    v_promedio_tiempo NUMERIC := 0;
    v_adherencia NUMERIC := 0;
    v_historia JSONB := '[]'::jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ninos WHERE id = p_nino_id) THEN
        RAISE EXCEPTION 'Nino % no existe', p_nino_id USING ERRCODE = 'P0002';
    END IF;

    v_fecha_desde := CASE
        WHEN COALESCE(p_periodo, '') = 'Esta semana' THEN date_trunc('week', NOW())
        WHEN COALESCE(p_periodo, '') = 'Este mes' THEN date_trunc('month', NOW())
        ELSE '2000-01-01'::timestamptz
    END;

    SELECT
        COUNT(DISTINCT s.id),
        COUNT(ra.id),
        COALESCE(SUM(ra.aciertos), 0),
        COALESCE(SUM(ra.repeticiones), 0),
        COALESCE(ROUND(AVG(ra.nivel_ayuda_requerido)::numeric, 2), 0),
        COALESCE(ROUND(AVG(ra.tiempo_respuesta)::numeric, 2), 0)
    INTO
        v_sesiones,
        v_actividades,
        v_total_aciertos,
        v_total_repeticiones,
        v_promedio_ayuda,
        v_promedio_tiempo
    FROM sesiones s
    LEFT JOIN resultados_actividad ra ON ra.sesion_id = s.id
    WHERE s.nino_id = p_nino_id
      AND s.fecha_inicio >= v_fecha_desde
      AND s.estado = 'completada';

    v_tasa_aciertos := COALESCE(
        ROUND(v_total_aciertos::numeric / NULLIF(v_total_repeticiones, 0), 4),
        0
    );

    v_adherencia := CASE
        WHEN COALESCE(p_periodo, '') = 'Esta semana'
            THEN LEAST(1, ROUND(v_sesiones::numeric / 5, 4))
        WHEN COALESCE(p_periodo, '') = 'Este mes'
            THEN LEAST(1, ROUND(v_sesiones::numeric / 20, 4))
        ELSE LEAST(1, v_tasa_aciertos)
    END;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'sesion_id', sesion_id,
                'fecha_inicio', fecha_inicio,
                'tasa_aciertos', tasa_aciertos
            )
            ORDER BY fecha_inicio
        ),
        '[]'::jsonb
    )
    INTO v_historia
    FROM (
        SELECT
            s.id AS sesion_id,
            s.fecha_inicio,
            COALESCE(
                ROUND(
                    SUM(ra.aciertos)::numeric / NULLIF(SUM(ra.repeticiones), 0),
                    4
                ),
                0
            ) AS tasa_aciertos
        FROM sesiones s
        JOIN resultados_actividad ra ON ra.sesion_id = s.id
        WHERE s.nino_id = p_nino_id
          AND s.estado = 'completada'
        GROUP BY s.id, s.fecha_inicio
        ORDER BY s.fecha_inicio DESC
        LIMIT 8
    ) historia;

    p_indicadores := jsonb_build_object(
        'nino_id', p_nino_id,
        'periodo', COALESCE(p_periodo, 'Historico'),
        'fecha_desde', v_fecha_desde,
        'sesiones_completadas', v_sesiones,
        'actividades_registradas', v_actividades,
        'total_aciertos', v_total_aciertos,
        'total_repeticiones', v_total_repeticiones,
        'tasa_aciertos', v_tasa_aciertos,
        'adherencia', v_adherencia,
        'promedio_ayuda', v_promedio_ayuda,
        'promedio_tiempo_respuesta', v_promedio_tiempo,
        'historia_aciertos', v_historia
    );
END;
$$;

-- ------------------------------------------------------------
-- sp_generar_reporte_sesion
-- ------------------------------------------------------------
-- Returns a JSONB report for a session, including child, plan,
-- aggregate performance and activity-level details.
-- ------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_generar_reporte_sesion(
    IN p_sesion_id UUID,
    OUT p_reporte JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sesion RECORD;
    v_resumen RECORD;
    v_actividades JSONB := '[]'::jsonb;
BEGIN
    SELECT
        s.id,
        s.nino_id,
        n.nombre AS nino_nombre,
        s.plan_id,
        pt.nombre AS plan_nombre,
        s.fecha_inicio,
        s.fecha_fin,
        s.estado,
        s.sync_at
    INTO v_sesion
    FROM sesiones s
    JOIN ninos n ON n.id = s.nino_id
    JOIN planes_terapeuticos pt ON pt.id = s.plan_id
    WHERE s.id = p_sesion_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sesion % no existe', p_sesion_id USING ERRCODE = 'P0002';
    END IF;

    SELECT
        COUNT(*) AS actividades_registradas,
        COALESCE(SUM(ra.aciertos), 0) AS total_aciertos,
        COALESCE(SUM(ra.repeticiones), 0) AS total_repeticiones,
        COALESCE(
            ROUND(SUM(ra.aciertos)::numeric / NULLIF(SUM(ra.repeticiones), 0), 4),
            0
        ) AS tasa_aciertos,
        COALESCE(ROUND(AVG(ra.nivel_ayuda_requerido)::numeric, 2), 0) AS promedio_ayuda,
        COALESCE(ROUND(AVG(ra.tiempo_respuesta)::numeric, 2), 0) AS promedio_tiempo
    INTO v_resumen
    FROM resultados_actividad ra
    WHERE ra.sesion_id = p_sesion_id;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'actividad_id', ra.actividad_id,
                'actividad_nombre', a.nombre,
                'tipo', a.tipo,
                'tiempo_respuesta', ra.tiempo_respuesta,
                'aciertos', ra.aciertos,
                'repeticiones', ra.repeticiones,
                'tasa_aciertos', COALESCE(
                    ROUND(ra.aciertos::numeric / NULLIF(ra.repeticiones, 0), 4),
                    0
                ),
                'nivel_ayuda_requerido', ra.nivel_ayuda_requerido,
                'nivel_dificultad_usado', ra.nivel_dificultad_usado,
                'observaciones', ra.observaciones,
                'timestamp', ra.timestamp
            )
            ORDER BY ra.timestamp
        ),
        '[]'::jsonb
    )
    INTO v_actividades
    FROM resultados_actividad ra
    JOIN actividades a ON a.id = ra.actividad_id
    WHERE ra.sesion_id = p_sesion_id;

    p_reporte := jsonb_build_object(
        'sesion_id', v_sesion.id,
        'nino_id', v_sesion.nino_id,
        'nino_nombre', v_sesion.nino_nombre,
        'plan_id', v_sesion.plan_id,
        'plan_nombre', v_sesion.plan_nombre,
        'fecha_inicio', v_sesion.fecha_inicio,
        'fecha_fin', v_sesion.fecha_fin,
        'estado', v_sesion.estado,
        'sync_at', v_sesion.sync_at,
        'resumen', jsonb_build_object(
            'actividades_registradas', v_resumen.actividades_registradas,
            'total_aciertos', v_resumen.total_aciertos,
            'total_repeticiones', v_resumen.total_repeticiones,
            'tasa_aciertos', v_resumen.tasa_aciertos,
            'promedio_ayuda', v_resumen.promedio_ayuda,
            'promedio_tiempo_respuesta', v_resumen.promedio_tiempo
        ),
        'actividades', v_actividades
    );
END;
$$;

-- ------------------------------------------------------------
-- sp_registrar_auditoria
-- ------------------------------------------------------------
-- Inserts an audit trail entry and returns the stored row as JSONB.
-- ------------------------------------------------------------

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
        payload_anterior,
        payload_nuevo,
        ip_origen,
        user_agent
    )
    VALUES (
        p_usuario_id,
        p_rol_usuario,
        p_accion,
        p_entidad_afectada,
        p_entidad_id,
        p_payload_anterior,
        COALESCE(p_payload_nuevo, '{}'::jsonb),
        p_ip_origen,
        p_user_agent
    )
    RETURNING * INTO v_log;

    p_auditoria := to_jsonb(v_log);
END;
$$;

COMMIT;
