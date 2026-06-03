-- Bloque 9: consentimiento informado y evidencias de cumplimiento LPDP.

CREATE TABLE IF NOT EXISTS consentimientos_informados (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nino_id UUID NOT NULL REFERENCES ninos(id) ON DELETE CASCADE,
    tutor_id UUID REFERENCES padres_tutores(id) ON DELETE SET NULL,
    usuario_id UUID REFERENCES usuarios(id) ON DELETE SET NULL,
    version VARCHAR(80) NOT NULL DEFAULT 'LPDP-29733-v1',
    finalidad TEXT NOT NULL,
    datos_sensibles BOOLEAN NOT NULL DEFAULT TRUE,
    aceptado BOOLEAN NOT NULL DEFAULT TRUE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_consentimientos_nino_fecha
ON consentimientos_informados (nino_id, accepted_at DESC);

CREATE INDEX IF NOT EXISTS idx_consentimientos_tutor_fecha
ON consentimientos_informados (tutor_id, accepted_at DESC);

CREATE INDEX IF NOT EXISTS idx_consentimientos_activos
ON consentimientos_informados (nino_id)
WHERE aceptado = TRUE AND revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS evidencias_cumplimiento (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    control VARCHAR(120) NOT NULL,
    descripcion TEXT NOT NULL,
    estado VARCHAR(40) NOT NULL DEFAULT 'activo',
    referencia TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO evidencias_cumplimiento (control, descripcion, estado, referencia)
VALUES
    ('consentimiento_informado', 'El registro y actualizacion de datos sensibles requiere confirmacion expresa del tutor.', 'activo', 'Ley 29733'),
    ('control_acceso_por_rol', 'Los endpoints filtran por rol y por vinculacion tutor/terapeuta antes de exponer informacion del nino.', 'activo', 'RBAC'),
    ('minima_recoleccion', 'El perfil familiar acepta campos opcionales y registra finalidad de tratamiento para datos sensibles.', 'activo', 'Principio de proporcionalidad'),
    ('advertencia_clinica', 'Los modulos SCQ, riesgo y recomendaciones declaran uso de apoyo clinico y no diagnostico.', 'activo', 'Uso no diagnostico'),
    ('trazabilidad', 'Las acciones relevantes quedan registradas en logs_auditoria con actor, entidad y nino_id.', 'activo', 'Bloque 8')
ON CONFLICT DO NOTHING;
