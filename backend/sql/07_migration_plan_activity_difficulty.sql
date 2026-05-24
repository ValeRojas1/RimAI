-- ============================================================
-- RimAI - Migracion 07: dificultad por actividad en plan
-- ============================================================
-- Permite que cada actividad asociada a un plan terapeutico tenga
-- una dificultad vigente propia, editable por el terapeuta y
-- actualizable tras una sugerencia adaptativa.
-- ============================================================

BEGIN;

ALTER TABLE plan_actividades
    ADD COLUMN IF NOT EXISTS nivel_dificultad_actual nivel_dificultad;

UPDATE plan_actividades pa
SET nivel_dificultad_actual = a.nivel_dificultad
FROM actividades a
WHERE a.id = pa.actividad_id
  AND pa.nivel_dificultad_actual IS NULL;

ALTER TABLE plan_actividades
    ALTER COLUMN nivel_dificultad_actual SET DEFAULT 'Medio';

CREATE INDEX IF NOT EXISTS idx_plan_actividades_dificultad
    ON plan_actividades(plan_id, nivel_dificultad_actual);

COMMIT;
