-- ============================================================
-- RimAI - Alertas clinicas y trazabilidad de notificaciones
-- ============================================================

BEGIN;

ALTER TABLE notificaciones
    ADD COLUMN IF NOT EXISTS tipo VARCHAR(60) NOT NULL DEFAULT 'general',
    ADD COLUMN IF NOT EXISTS canal VARCHAR(40) NOT NULL DEFAULT 'in_app',
    ADD COLUMN IF NOT EXISTS estado_envio VARCHAR(30) NOT NULL DEFAULT 'registrada',
    ADD COLUMN IF NOT EXISTS entidad_tipo VARCHAR(80),
    ADD COLUMN IF NOT EXISTS entidad_id UUID,
    ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_notificaciones_entidad
    ON notificaciones(entidad_tipo, entidad_id);

CREATE INDEX IF NOT EXISTS idx_notificaciones_tipo_created
    ON notificaciones(tipo, created_at DESC);

CREATE TABLE IF NOT EXISTS configuracion_notificaciones (
    usuario_id UUID PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
    canal_preferido VARCHAR(40) NOT NULL DEFAULT 'in_app',
    alertas_clinicas BOOLEAN NOT NULL DEFAULT TRUE,
    recordatorios_familia BOOLEAN NOT NULL DEFAULT TRUE,
    umbral_inactividad_dias INT NOT NULL DEFAULT 7,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE configuracion_notificaciones
    ADD COLUMN IF NOT EXISTS umbral_inactividad_dias INT NOT NULL DEFAULT 7;

CREATE TABLE IF NOT EXISTS alertas_clinicas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nino_id UUID NOT NULL REFERENCES ninos(id) ON DELETE CASCADE,
    terapeuta_id UUID NOT NULL REFERENCES terapeutas(id) ON DELETE CASCADE,
    tutor_id UUID REFERENCES padres_tutores(id) ON DELETE SET NULL,
    tipo VARCHAR(80) NOT NULL,
    severidad VARCHAR(20) NOT NULL,
    titulo VARCHAR(255) NOT NULL,
    mensaje TEXT NOT NULL,
    canal VARCHAR(40) NOT NULL DEFAULT 'in_app',
    estado_envio VARCHAR(30) NOT NULL DEFAULT 'registrada',
    origen VARCHAR(80) NOT NULL DEFAULT 'evaluacion_automatica',
    metricas JSONB NOT NULL DEFAULT '{}'::jsonb,
    dedupe_key VARCHAR(255) NOT NULL UNIQUE,
    notificacion_terapeuta_id UUID REFERENCES notificaciones(id) ON DELETE SET NULL,
    notificacion_familia_id UUID REFERENCES notificaciones(id) ON DELETE SET NULL,
    resuelta BOOLEAN NOT NULL DEFAULT FALSE,
    resuelta_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alertas_clinicas_terapeuta
    ON alertas_clinicas(terapeuta_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_alertas_clinicas_nino
    ON alertas_clinicas(nino_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_alertas_clinicas_pendientes
    ON alertas_clinicas(terapeuta_id, resuelta, severidad)
    WHERE resuelta = FALSE;

COMMIT;
