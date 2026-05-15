-- ============================================================
-- RimAI — Migración 03: Estado Clínico del Niño
-- ============================================================
-- Agrega el ciclo de vida clínico-administrativo a la tabla ninos.
-- Estados: pendiente_asignacion → vinculado_terapeuta →
--          perfil_clinico_incompleto → listo_para_plan → plan_activo
-- ============================================================

BEGIN;

-- 1. Crear el ENUM de estados clínicos
DO $$ BEGIN
    CREATE TYPE estado_clinico AS ENUM (
        'pendiente_asignacion',
        'vinculado_terapeuta',
        'perfil_clinico_incompleto',
        'listo_para_plan',
        'plan_activo'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- 2. Agregar columnas de estado y trazabilidad a ninos
ALTER TABLE ninos
    ADD COLUMN IF NOT EXISTS estado_clinico estado_clinico NOT NULL DEFAULT 'pendiente_asignacion',
    ADD COLUMN IF NOT EXISTS vinculado_por  UUID REFERENCES terapeutas(id),
    ADD COLUMN IF NOT EXISTS vinculado_at   TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS perfil_completado_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS creado_por     UUID REFERENCES padres_tutores(id);

-- 3. Retrocompatibilidad: actualizar los niños ya existentes
--    Orden: del estado más avanzado al menos avanzado para no pisar.

-- 3a. Niños con plan activo → plan_activo
UPDATE ninos n
SET estado_clinico = 'plan_activo'
WHERE EXISTS (
    SELECT 1 FROM planes_terapeuticos pt
    WHERE pt.nino_id = n.id AND pt.activo = TRUE
)
AND n.terapeuta_id IS NOT NULL;

-- 3b. Niños con terapeuta pero sin plan activo y con perfil sensorial +
--     objetivos cargados → listo_para_plan
UPDATE ninos n
SET estado_clinico = 'listo_para_plan'
WHERE n.terapeuta_id IS NOT NULL
  AND n.estado_clinico = 'pendiente_asignacion'  -- no fue marcado como plan_activo
  AND n.perfil_sensorial IS NOT NULL
  AND n.objetivos_intervencion IS NOT NULL
  AND array_length(n.objetivos_intervencion, 1) > 0;

-- 3c. Niños con terapeuta pero perfil incompleto → perfil_clinico_incompleto
UPDATE ninos n
SET estado_clinico = 'perfil_clinico_incompleto'
WHERE n.terapeuta_id IS NOT NULL
  AND n.estado_clinico = 'pendiente_asignacion';  -- no cayó en los casos anteriores

-- 3d. Niños con terapeuta asignado (sin plan ni perfil listo) →
--     ya quedaron en perfil_clinico_incompleto arriba.
--     Los que tienen terapeuta_id y llegaron hasta acá → vinculado_terapeuta
--     (en realidad quedaron en perfil_clinico_incompleto, que es correcto).

-- 3e. Rellenar vinculado_por con el terapeuta asignado (si existe)
UPDATE ninos n
SET    vinculado_por = n.terapeuta_id
WHERE  n.terapeuta_id IS NOT NULL
  AND  n.vinculado_por IS NULL;

-- 3f. Sincronizar creado_por con tutor_id si existe
UPDATE ninos n
SET    creado_por = n.tutor_id
WHERE  n.tutor_id IS NOT NULL
  AND  n.creado_por IS NULL;

-- 4. Índice para consultas de bandeja de espera
CREATE INDEX IF NOT EXISTS idx_ninos_estado_clinico ON ninos(estado_clinico);
CREATE INDEX IF NOT EXISTS idx_ninos_tutor ON ninos(tutor_id);

-- 5. Verificación rápida
DO $$
DECLARE
    v_pendientes    INT;
    v_vinculados    INT;
    v_listos        INT;
    v_plan_activo   INT;
BEGIN
    SELECT COUNT(*) INTO v_pendientes    FROM ninos WHERE estado_clinico = 'pendiente_asignacion';
    SELECT COUNT(*) INTO v_vinculados    FROM ninos WHERE estado_clinico IN ('vinculado_terapeuta','perfil_clinico_incompleto');
    SELECT COUNT(*) INTO v_listos        FROM ninos WHERE estado_clinico = 'listo_para_plan';
    SELECT COUNT(*) INTO v_plan_activo   FROM ninos WHERE estado_clinico = 'plan_activo';

    RAISE NOTICE '=== RimAI migración 03 — estados clínicos ===';
    RAISE NOTICE '  pendiente_asignacion          : %', v_pendientes;
    RAISE NOTICE '  vinculado / perfil_incompleto : %', v_vinculados;
    RAISE NOTICE '  listo_para_plan               : %', v_listos;
    RAISE NOTICE '  plan_activo                   : %', v_plan_activo;
    RAISE NOTICE '  Total ninos                   : %', v_pendientes + v_vinculados + v_listos + v_plan_activo;
END $$;

COMMIT;
