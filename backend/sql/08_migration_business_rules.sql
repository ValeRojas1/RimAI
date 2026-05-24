-- ============================================================
-- 08_migration_business_rules.sql
-- Reglas base de negocio:
--   - El terapeuta valida el nivel TEA y publica el plan.
--   - El tutor ejecuta planes publicados.
--   - Un plan publicable tiene maximo 3 actividades y maximo 60 minutos.
-- ============================================================

BEGIN;

ALTER TABLE ninos
    ADD COLUMN IF NOT EXISTS nivel_tea_validado SMALLINT,
    ADD COLUMN IF NOT EXISTS perfil_validado_por UUID REFERENCES terapeutas(id),
    ADD COLUMN IF NOT EXISTS perfil_validado_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_ninos_nivel_tea_validado'
    ) THEN
        ALTER TABLE ninos
            ADD CONSTRAINT chk_ninos_nivel_tea_validado
            CHECK (nivel_tea_validado IS NULL OR nivel_tea_validado BETWEEN 1 AND 3);
    END IF;
END $$;

UPDATE ninos
SET nivel_tea_validado = CASE
        WHEN diagnostico ILIKE '%nivel 1%' THEN 1
        WHEN diagnostico ILIKE '%nivel 2%' THEN 2
        WHEN diagnostico ILIKE '%nivel 3%' THEN 3
        ELSE nivel_tea_validado
    END
WHERE nivel_tea_validado IS NULL;

UPDATE ninos
SET perfil_validado_at = COALESCE(perfil_validado_at, perfil_completado_at, vinculado_at, created_at),
    perfil_validado_por = COALESCE(perfil_validado_por, terapeuta_id)
WHERE terapeuta_id IS NOT NULL
  AND nivel_tea_validado IS NOT NULL
  AND perfil_validado_at IS NULL;

ALTER TABLE planes_terapeuticos
    ADD COLUMN IF NOT EXISTS estado_plan VARCHAR(20) NOT NULL DEFAULT 'borrador',
    ADD COLUMN IF NOT EXISTS aprobado_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS publicado_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS publicado_para_tutor BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS limite_actividades INT NOT NULL DEFAULT 3,
    ADD COLUMN IF NOT EXISTS limite_duracion_segundos INT NOT NULL DEFAULT 3600;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_planes_estado_plan'
    ) THEN
        ALTER TABLE planes_terapeuticos
            ADD CONSTRAINT chk_planes_estado_plan
            CHECK (estado_plan IN ('borrador', 'aprobado', 'publicado'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_planes_limites'
    ) THEN
        ALTER TABLE planes_terapeuticos
            ADD CONSTRAINT chk_planes_limites
            CHECK (limite_actividades = 3 AND limite_duracion_segundos = 3600);
    END IF;
END $$;

UPDATE planes_terapeuticos pt
SET estado_plan = 'publicado',
    aprobado_at = COALESCE(aprobado_at, pt.created_at),
    publicado_at = COALESCE(publicado_at, pt.created_at),
    publicado_para_tutor = TRUE
FROM ninos n
WHERE n.id = pt.nino_id
  AND n.estado_clinico = 'plan_activo'
  AND pt.estado_plan = 'borrador';

ALTER TABLE plan_actividades
    ADD COLUMN IF NOT EXISTS modo_ejecucion VARCHAR(20) NOT NULL DEFAULT 'acompanada',
    ADD COLUMN IF NOT EXISTS requiere_acompanamiento BOOLEAN NOT NULL DEFAULT TRUE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_plan_actividades_modo_ejecucion'
    ) THEN
        ALTER TABLE plan_actividades
            ADD CONSTRAINT chk_plan_actividades_modo_ejecucion
            CHECK (modo_ejecucion IN ('autonoma', 'acompanada'));
    END IF;
END $$;

UPDATE plan_actividades pa
SET modo_ejecucion = CASE WHEN n.nivel_tea_validado = 1 THEN 'autonoma' ELSE 'acompanada' END,
    requiere_acompanamiento = CASE WHEN n.nivel_tea_validado = 1 THEN FALSE ELSE TRUE END
FROM planes_terapeuticos pt
JOIN ninos n ON n.id = pt.nino_id
WHERE pt.id = pa.plan_id;

ALTER TABLE sesiones
    ADD COLUMN IF NOT EXISTS ejecutado_por_rol VARCHAR(20),
    ADD COLUMN IF NOT EXISTS ejecutado_por_usuario_id UUID REFERENCES usuarios(id),
    ADD COLUMN IF NOT EXISTS origen_registro VARCHAR(30) NOT NULL DEFAULT 'legacy';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_sesiones_ejecutado_por_rol'
    ) THEN
        ALTER TABLE sesiones
            ADD CONSTRAINT chk_sesiones_ejecutado_por_rol
            CHECK (ejecutado_por_rol IS NULL OR ejecutado_por_rol IN ('padre_tutor', 'tutor'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_planes_estado_plan
    ON planes_terapeuticos(nino_id, estado_plan, activo);

CREATE INDEX IF NOT EXISTS idx_ninos_nivel_tea_validado
    ON ninos(nivel_tea_validado);

COMMIT;
