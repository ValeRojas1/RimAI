-- ============================================================
-- 09_migration_notifications.sql
-- Creación del sistema de notificaciones para el tutor/padre.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS notificaciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    titulo VARCHAR(255) NOT NULL,
    mensaje TEXT NOT NULL,
    leido BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para optimizar consultas de la aplicación familiar
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_leido 
    ON notificaciones(usuario_id, leido);

CREATE INDEX IF NOT EXISTS idx_notificaciones_created_at 
    ON notificaciones(created_at DESC);

COMMIT;
