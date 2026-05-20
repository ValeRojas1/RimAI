-- ============================================
-- RimAI init SQL
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Roles y usuarios
CREATE TYPE rol_usuario AS ENUM ('terapeuta', 'padre_tutor', 'admin');

CREATE TABLE usuarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre VARCHAR(150) NOT NULL,
    email VARCHAR(200) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    rol rol_usuario NOT NULL,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE terapeutas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID NOT NULL UNIQUE REFERENCES usuarios(id) ON DELETE CASCADE,
    especialidad VARCHAR(150),
    colegiatura VARCHAR(50)
);

CREATE TABLE padres_tutores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id UUID NOT NULL UNIQUE REFERENCES usuarios(id) ON DELETE CASCADE,
    telefono VARCHAR(20)
);

-- Ninos con TEA
CREATE TYPE nivel_cognitivo AS ENUM ('Bajo', 'Medio', 'Alto');

CREATE TABLE ninos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre VARCHAR(150) NOT NULL,
    fecha_nacimiento DATE NOT NULL,
    nivel_cognitivo nivel_cognitivo NOT NULL,
    perfil_sensorial JSONB,
    objetivos_intervencion TEXT[],
    diagnostico VARCHAR(200),
    documento_diagnostico VARCHAR(255),
    terapeuta_id UUID REFERENCES terapeutas(id),
    tutor_id UUID REFERENCES padres_tutores(id),
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Actividades
CREATE TYPE nivel_dificultad AS ENUM ('Bajo', 'Medio', 'Alto');

CREATE TABLE actividades (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tipo VARCHAR(100) NOT NULL,
    nombre VARCHAR(200) NOT NULL,
    instrucciones TEXT,
    nivel_dificultad nivel_dificultad NOT NULL,
    duracion_estimada INT,
    recursos_multimedia JSONB,
    activo BOOLEAN DEFAULT TRUE
);

-- Planes terapeuticos
CREATE TABLE planes_terapeuticos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre VARCHAR(200) NOT NULL DEFAULT 'Plan terapeutico activo',
    nino_id UUID NOT NULL REFERENCES ninos(id),
    terapeuta_id UUID NOT NULL REFERENCES terapeutas(id),
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE,
    nivel_dificultad_actual nivel_dificultad DEFAULT 'Bajo',
    criterios_progresion JSONB,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE plan_actividades (
    plan_id UUID REFERENCES planes_terapeuticos(id) ON DELETE CASCADE,
    actividad_id UUID REFERENCES actividades(id),
    orden INT,
    PRIMARY KEY (plan_id, actividad_id)
);

-- Sesiones terapeuticas
CREATE TYPE estado_sesion AS ENUM ('completada', 'interrumpida', 'pendiente_sync');

CREATE TABLE sesiones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nino_id UUID NOT NULL REFERENCES ninos(id),
    plan_id UUID NOT NULL REFERENCES planes_terapeuticos(id),
    fecha_inicio TIMESTAMPTZ NOT NULL,
    fecha_fin TIMESTAMPTZ,
    estado estado_sesion DEFAULT 'pendiente_sync',
    sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE resultados_actividad (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sesion_id UUID NOT NULL REFERENCES sesiones(id),
    actividad_id UUID NOT NULL REFERENCES actividades(id),
    tiempo_respuesta FLOAT,
    aciertos INT,
    repeticiones INT,
    nivel_ayuda_requerido INT DEFAULT 0,
    nivel_dificultad_usado nivel_dificultad DEFAULT 'Medio',
    observaciones TEXT,
    confianza_emocion FLOAT,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE decisiones_clinicas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    terapeuta_id UUID NOT NULL REFERENCES terapeutas(id),
    nino_id UUID REFERENCES ninos(id),
    recomendacion_id VARCHAR(120) NOT NULL,
    accion VARCHAR(40) NOT NULL,
    observacion TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indices
CREATE INDEX idx_ninos_terapeuta ON ninos(terapeuta_id);
CREATE INDEX idx_sesiones_nino ON sesiones(nino_id);
CREATE INDEX idx_sesiones_plan ON sesiones(plan_id);
CREATE INDEX idx_resultados_sesion ON resultados_actividad(sesion_id);
CREATE INDEX idx_planes_nino ON planes_terapeuticos(nino_id);
