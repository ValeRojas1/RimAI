-- Bloque 7: soporte de sincronizacion offline idempotente.

ALTER TABLE sesiones
ADD COLUMN IF NOT EXISTS client_event_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sesiones_client_event_id
ON sesiones (client_event_id)
WHERE client_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sesiones_sync_pending_lookup
ON sesiones (nino_id, plan_id, client_event_id)
WHERE client_event_id IS NOT NULL;
