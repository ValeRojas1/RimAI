-- ============================================================
-- RimAI — Migración 04: Índices + tutor_id en ninos + columna nivel_cognitivo nullable
-- ============================================================
-- Esta migración complementa la 03 y asegura compatibilidad
-- con el flujo familiar:
--   - tutor_id ya existe en ninos (de 01_init.sql), solo se agregan índices.
--   - nivel_cognitivo puede llegar NULL desde la familia (el terapeuta lo pone
--     en el paso de enriquecimiento), así que se relaja el NOT NULL.
--   - Se agrega índice en decisiones_clinicas para trazabilidad rápida.
-- ============================================================

BEGIN;

-- 1. Relajar nivel_cognitivo para que la familia pueda crear niños sin ese campo
ALTER TABLE ninos
    ALTER COLUMN nivel_cognitivo DROP NOT NULL;

ALTER TABLE ninos
    ALTER COLUMN nivel_cognitivo SET DEFAULT 'Medio';

-- 2. Índices adicionales de rendimiento
CREATE INDEX IF NOT EXISTS idx_decisiones_nino      ON decisiones_clinicas(nino_id);
CREATE INDEX IF NOT EXISTS idx_decisiones_terapeuta ON decisiones_clinicas(terapeuta_id);
CREATE INDEX IF NOT EXISTS idx_ninos_tutor_activo   ON ninos(tutor_id, activo);
CREATE INDEX IF NOT EXISTS idx_ninos_pendientes     ON ninos(estado_clinico, activo)
    WHERE activo = TRUE;

-- 3. Retrocompatibilidad: asegurar que todos los niños con terapeuta tengan nivel_cognitivo
UPDATE ninos SET nivel_cognitivo = 'Medio' WHERE nivel_cognitivo IS NULL;

-- 4. Verificación
DO $$
DECLARE v_total INT;
BEGIN
    SELECT COUNT(*) INTO v_total FROM ninos WHERE nivel_cognitivo IS NULL;
    IF v_total > 0 THEN
        RAISE WARNING '  ⚠ Hay % ninos con nivel_cognitivo NULL', v_total;
    ELSE
        RAISE NOTICE '  ✓ Todos los ninos tienen nivel_cognitivo asignado';
    END IF;

    SELECT COUNT(*) INTO v_total FROM decisiones_clinicas;
    RAISE NOTICE '  Decisiones clínicas en base: %', v_total;
END $$;

COMMIT;
