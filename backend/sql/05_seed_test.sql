-- ============================================================
-- RimAI — Seed 05: Datos de prueba para el flujo clínico completo
-- ============================================================
-- Crea un terapeuta de prueba, una familia de prueba y 4 niños
-- que cubren todos los estados del ciclo de vida clínico.
--
-- Usuarios de prueba:
--   Terapeuta : terapeuta@rimai.dev / Rimai2024!
--   Familia 1 : familia1@rimai.dev  / Rimai2024!
--   Familia 2 : familia2@rimai.dev  / Rimai2024!
--
-- IMPORTANTE: Las contraseñas ya están hasheadas con bcrypt (cost=12).
-- ============================================================

BEGIN;

-- ── 1. Usuarios de prueba ────────────────────────────────────────────────────

-- Terapeuta
INSERT INTO usuarios (id, nombre, email, password_hash, rol)
VALUES (
    '11111111-0000-0000-0000-000000000001',
    'Dr. Alejandro Mora',
    'terapeuta@rimai.dev',
    '$2b$12$0uGeTMk5Y6qiAOmRh0HJ0uIuTsvXhMmCnHWSA3frpHxJx4b6CRZEW',   -- Rimai2024!
    'terapeuta'
)
ON CONFLICT (email) DO NOTHING;

INSERT INTO terapeutas (id, usuario_id, especialidad, colegiatura)
VALUES (
    '22222222-0000-0000-0000-000000000001',
    '11111111-0000-0000-0000-000000000001',
    'Terapia Ocupacional TEA',
    'COL-12345'
)
ON CONFLICT (usuario_id) DO NOTHING;

-- Familia 1
INSERT INTO usuarios (id, nombre, email, password_hash, rol)
VALUES (
    '11111111-0000-0000-0000-000000000002',
    'María López',
    'familia1@rimai.dev',
    '$2b$12$0uGeTMk5Y6qiAOmRh0HJ0uIuTsvXhMmCnHWSA3frpHxJx4b6CRZEW',   -- Rimai2024!
    'padre_tutor'
)
ON CONFLICT (email) DO NOTHING;

INSERT INTO padres_tutores (id, usuario_id, telefono)
VALUES (
    '33333333-0000-0000-0000-000000000001',
    '11111111-0000-0000-0000-000000000002',
    '+52 55 1234 5678'
)
ON CONFLICT (usuario_id) DO NOTHING;

-- Familia 2
INSERT INTO usuarios (id, nombre, email, password_hash, rol)
VALUES (
    '11111111-0000-0000-0000-000000000003',
    'Carlos Vega',
    'familia2@rimai.dev',
    '$2b$12$0uGeTMk5Y6qiAOmRh0HJ0uIuTsvXhMmCnHWSA3frpHxJx4b6CRZEW',   -- Rimai2024!
    'padre_tutor'
)
ON CONFLICT (email) DO NOTHING;

INSERT INTO padres_tutores (id, usuario_id, telefono)
VALUES (
    '33333333-0000-0000-0000-000000000002',
    '11111111-0000-0000-0000-000000000003',
    '+52 55 9876 5432'
)
ON CONFLICT (usuario_id) DO NOTHING;

-- ── 2. Actividades de ejemplo (si no existen) ───────────────────────────────

INSERT INTO actividades (id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada)
VALUES
    ('aaaaaaaa-0000-0000-0000-000000000001', 'Comunicacion', 'Señalar objetos', 'El niño señala el objeto nombrado por el terapeuta.', 'Bajo', 300),
    ('aaaaaaaa-0000-0000-0000-000000000002', 'Atencion',     'Seguir instrucción simple', 'El niño sigue una instrucción de 1 paso.', 'Bajo', 240),
    ('aaaaaaaa-0000-0000-0000-000000000003', 'Social',       'Contacto visual 5 seg', 'Mantener contacto visual durante 5 segundos.', 'Medio', 180),
    ('aaaaaaaa-0000-0000-0000-000000000004', 'Motricidad',   'Insertar piezas', 'Insertar piezas en tablero de formas.', 'Medio', 360),
    ('aaaaaaaa-0000-0000-0000-000000000005', 'Cognitivo',    'Clasificación por color', 'Ordenar bloques por color en 3 categorías.', 'Alto', 420)
ON CONFLICT (id) DO NOTHING;

-- ── 3. Niños en distintos estados del ciclo de vida ─────────────────────────

-- Niño A: pendiente_asignacion (familia 1 lo registró, nadie lo ha tomado)
INSERT INTO ninos (
    id, nombre, fecha_nacimiento, nivel_cognitivo,
    perfil_sensorial, diagnostico, tutor_id, estado_clinico, activo
) VALUES (
    'cccccccc-0000-0000-0000-000000000001',
    'Santiago López',
    '2019-03-15',
    'Medio',
    '{"hitos": {"comunicacion": "Palabras sueltas", "contacto_visual": "Intermitente"},
      "sensorial": {"hipersensibilidad": ["Ruidos fuertes"], "hiposensibilidad": [], "comportamientos_repetitivos": ["Balanceo"]},
      "intereses": ["Dinosaurios", "Trenes"]}',
    'TEA nivel 1',
    '33333333-0000-0000-0000-000000000001',
    'pendiente_asignacion',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- Niño B: perfil_clinico_incompleto (familia 1, ya vinculado al terapeuta, le falta completar perfil)
INSERT INTO ninos (
    id, nombre, fecha_nacimiento, nivel_cognitivo,
    perfil_sensorial, diagnostico, terapeuta_id, tutor_id,
    vinculado_por, vinculado_at, estado_clinico, activo
) VALUES (
    'cccccccc-0000-0000-0000-000000000002',
    'Emilio López',
    '2018-07-22',
    'Bajo',
    '{"hitos": {"comunicacion": "No verbal"}, "intereses": ["Música"]}',
    'TEA nivel 2',
    '22222222-0000-0000-0000-000000000001',
    '33333333-0000-0000-0000-000000000001',
    '22222222-0000-0000-0000-000000000001',
    NOW() - INTERVAL '2 days',
    'perfil_clinico_incompleto',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- Niño C: listo_para_plan (familia 2, perfil completo listo para generación)
INSERT INTO ninos (
    id, nombre, fecha_nacimiento, nivel_cognitivo,
    perfil_sensorial, objetivos_intervencion, diagnostico,
    terapeuta_id, tutor_id, vinculado_por, vinculado_at,
    perfil_completado_at, estado_clinico, activo
) VALUES (
    'cccccccc-0000-0000-0000-000000000003',
    'Valeria Vega',
    '2020-01-10',
    'Medio',
    '{"hitos": {"comunicacion": "Frases cortas", "contacto_visual": "Sostenido"},
      "sensorial": {"hipersensibilidad": ["Luces brillantes"], "hiposensibilidad": ["Movimiento constante"]},
      "intereses": ["Música", "Animales"]}',
    ARRAY['Mejorar contacto visual', 'Ampliar vocabulario funcional', 'Reducir conductas repetitivas'],
    'TEA nivel 1',
    '22222222-0000-0000-0000-000000000001',
    '33333333-0000-0000-0000-000000000002',
    '22222222-0000-0000-0000-000000000001',
    NOW() - INTERVAL '5 days',
    NOW() - INTERVAL '3 days',
    'listo_para_plan',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- Niño D: plan_activo (familia 2, plan ya generado y vigente)
INSERT INTO ninos (
    id, nombre, fecha_nacimiento, nivel_cognitivo,
    perfil_sensorial, objetivos_intervencion, diagnostico,
    terapeuta_id, tutor_id, vinculado_por, vinculado_at,
    perfil_completado_at, estado_clinico, activo
) VALUES (
    'cccccccc-0000-0000-0000-000000000004',
    'Diego Vega',
    '2017-11-05',
    'Medio',
    '{"hitos": {"comunicacion": "Fluido", "contacto_visual": "Sostenido"},
      "sensorial": {"hipersensibilidad": [], "hiposensibilidad": ["Presión profunda"]},
      "intereses": ["Dinosaurios", "Geometría"]}',
    ARRAY['Comunicación funcional avanzada', 'Habilidades de juego compartido'],
    'Síndrome de Asperger',
    '22222222-0000-0000-0000-000000000001',
    '33333333-0000-0000-0000-000000000002',
    '22222222-0000-0000-0000-000000000001',
    NOW() - INTERVAL '30 days',
    NOW() - INTERVAL '28 days',
    'plan_activo',
    TRUE
)
ON CONFLICT (id) DO NOTHING;

-- ── 4. Plan activo para Diego Vega ─────────────────────────────────────────

INSERT INTO planes_terapeuticos (
    id, nombre, nino_id, terapeuta_id,
    fecha_inicio, nivel_dificultad_actual, activo
) VALUES (
    'dddddddd-0000-0000-0000-000000000001',
    'Plan activo de Diego Vega',
    'cccccccc-0000-0000-0000-000000000004',
    '22222222-0000-0000-0000-000000000001',
    CURRENT_DATE - INTERVAL '28 days',
    'Medio',
    TRUE
)
ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    nino_id = EXCLUDED.nino_id,
    terapeuta_id = EXCLUDED.terapeuta_id,
    fecha_inicio = EXCLUDED.fecha_inicio,
    nivel_dificultad_actual = EXCLUDED.nivel_dificultad_actual,
    activo = TRUE;

INSERT INTO plan_actividades (plan_id, actividad_id, orden)
VALUES
    ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000003', 1),
    ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000004', 2),
    ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000005', 3)
ON CONFLICT DO NOTHING;

-- Sesion previa para demostrar HU-08: ajuste automatico de dificultad.
-- Al ejecutar de nuevo "Contacto visual 5 seg" con desempeno >= 80%,
-- el sistema tendra historial y registrara el aumento de Medio a Alto.
INSERT INTO sesiones (
    id, nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at
) VALUES (
    'eeeeeeee-0000-0000-0000-000000000001',
    'cccccccc-0000-0000-0000-000000000004',
    'dddddddd-0000-0000-0000-000000000001',
    NOW() - INTERVAL '1 day',
    NOW() - INTERVAL '1 day' + INTERVAL '12 minutes',
    'completada',
    NOW() - INTERVAL '1 day' + INTERVAL '13 minutes'
)
ON CONFLICT (id) DO UPDATE SET
    fecha_inicio = EXCLUDED.fecha_inicio,
    fecha_fin = EXCLUDED.fecha_fin,
    estado = EXCLUDED.estado,
    sync_at = EXCLUDED.sync_at;

DELETE FROM resultados_actividad
WHERE sesion_id = 'eeeeeeee-0000-0000-0000-000000000001';

INSERT INTO resultados_actividad (
    sesion_id, actividad_id, tiempo_respuesta, aciertos, repeticiones,
    nivel_ayuda_requerido, nivel_dificultad_usado, observaciones
) VALUES (
    'eeeeeeee-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000003',
    2.1,
    8,
    10,
    0,
    'Medio',
    'Sesion previa demo HU-08: desempeno suficiente para evaluar progresion.'
);

-- ── 5. Trazabilidad de ejemplo ──────────────────────────────────────────────

INSERT INTO decisiones_clinicas (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
VALUES
    ('22222222-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002',
     'vincular_paciente', 'ACEPTAR', 'Vinculado desde bandeja de espera. Estado anterior: pendiente_asignacion'),
    ('22222222-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000003',
     'vincular_paciente', 'ACEPTAR', 'Vinculado desde bandeja de espera'),
    ('22222222-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000003',
     'perfil_clinico', 'COMPLETAR', 'Perfil clínico completado. Listo para generar plan.'),
    ('22222222-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000004',
     'plan_ia', 'GENERAR', 'Plan generado por IA. Dificultad: Alto. Confianza: 0.912');

-- ── 6. Resumen de verificación ──────────────────────────────────────────────

DO $$
DECLARE
    v_pendientes    INT;
    v_incompletos   INT;
    v_listos        INT;
    v_activos       INT;
BEGIN
    SELECT COUNT(*) INTO v_pendientes  FROM ninos WHERE estado_clinico = 'pendiente_asignacion' AND activo;
    SELECT COUNT(*) INTO v_incompletos FROM ninos WHERE estado_clinico = 'perfil_clinico_incompleto' AND activo;
    SELECT COUNT(*) INTO v_listos      FROM ninos WHERE estado_clinico = 'listo_para_plan' AND activo;
    SELECT COUNT(*) INTO v_activos     FROM ninos WHERE estado_clinico = 'plan_activo' AND activo;

    RAISE NOTICE '=== RimAI seed 05 — datos de prueba ===';
    RAISE NOTICE '  pendiente_asignacion     : % (Santiago López)', v_pendientes;
    RAISE NOTICE '  perfil_clinico_incompleto: % (Emilio López)', v_incompletos;
    RAISE NOTICE '  listo_para_plan          : % (Valeria Vega)', v_listos;
    RAISE NOTICE '  plan_activo              : % (Diego Vega)', v_activos;
    RAISE NOTICE '  Usuarios de prueba:';
    RAISE NOTICE '    terapeuta@rimai.dev  / Rimai2024!';
    RAISE NOTICE '    familia1@rimai.dev   / Rimai2024!  (Santiago + Emilio)';
    RAISE NOTICE '    familia2@rimai.dev   / Rimai2024!  (Valeria + Diego)';
END $$;

COMMIT;
