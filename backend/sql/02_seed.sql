-- RimAI seed PMV1 + PMV2 demo.
-- Idempotent: every row uses a fixed UUID or unique email.

DO $$
DECLARE
  v_usuario_id UUID := '11111111-1111-1111-1111-111111111111';
  v_terapeuta_id UUID := '22222222-2222-2222-2222-222222222222';
  v_tutor_usr_id UUID := '33333333-3333-3333-3333-333333333333';
  v_tutor_id UUID := '44444444-4444-4444-4444-444444444444';
  v_nino_id UUID := '55555555-5555-5555-5555-555555555555';
  v_act1_id UUID := '66666666-6666-6666-6666-666666666661';
  v_act2_id UUID := '66666666-6666-6666-6666-666666666662';
  v_act3_id UUID := '66666666-6666-6666-6666-666666666663';
  v_plan_id UUID := '77777777-7777-7777-7777-777777777777';
  v_sesion_id UUID := '88888888-8888-8888-8888-888888888888';
BEGIN
  INSERT INTO usuarios (id, nombre, email, password_hash, rol, activo)
  VALUES (
    v_usuario_id,
    'Dra. Sofia Ramirez',
    'terapeuta@rimai.com',
    '$2b$12$RdIbNiYBwUHzaCF2fKSDFuiAGcRcMyVY2I7J2NhJEyltCZj7GquYG',
    'terapeuta',
    TRUE
  )
  ON CONFLICT (email) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    password_hash = EXCLUDED.password_hash,
    rol = EXCLUDED.rol,
    activo = TRUE
  RETURNING id INTO v_usuario_id;

  INSERT INTO terapeutas (id, usuario_id, especialidad, colegiatura)
  VALUES (v_terapeuta_id, v_usuario_id, 'Terapia Ocupacional con enfoque TEA', 'TO-2021-4892')
  ON CONFLICT (usuario_id) DO UPDATE SET
    especialidad = EXCLUDED.especialidad,
    colegiatura = EXCLUDED.colegiatura
  RETURNING id INTO v_terapeuta_id;

  INSERT INTO usuarios (id, nombre, email, password_hash, rol, activo)
  VALUES (
    v_tutor_usr_id,
    'Carlos Mendoza',
    'tutor.lucas@rimai.com',
    '$2b$12$RdIbNiYBwUHzaCF2fKSDFuiAGcRcMyVY2I7J2NhJEyltCZj7GquYG',
    'padre_tutor',
    TRUE
  )
  ON CONFLICT (email) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    password_hash = EXCLUDED.password_hash,
    rol = EXCLUDED.rol,
    activo = TRUE
  RETURNING id INTO v_tutor_usr_id;

  INSERT INTO padres_tutores (id, usuario_id, telefono)
  VALUES (v_tutor_id, v_tutor_usr_id, '+51 999 123 456')
  ON CONFLICT (usuario_id) DO UPDATE SET telefono = EXCLUDED.telefono
  RETURNING id INTO v_tutor_id;

  INSERT INTO ninos (
    id, nombre, fecha_nacimiento, nivel_cognitivo, perfil_sensorial,
    objetivos_intervencion, diagnostico, documento_diagnostico,
    terapeuta_id, tutor_id, activo
  )
  VALUES (
    v_nino_id,
    'Lucas Mendoza',
    '2017-03-12',
    'Medio',
    '{
      "intereses": ["musica", "colores", "animales"],
      "estimulosAversivos": {
        "RUIDO": ["ruidos fuertes", "sirenas", "licuadora"],
        "LUGARES": ["espacios cerrados", "multitudes"],
        "TEXTURAS": ["superficies rugosas"]
      },
      "umbralSensorial": "bajo",
      "preferenciasEntorno": ["luz tenue", "musica suave", "espacios ordenados"]
    }'::jsonb,
    ARRAY[
      'Mejorar atencion conjunta sostenida mayor a 5 minutos',
      'Desarrollar comunicacion funcional con apoyo verbal',
      'Reducir evitacion ante estimulos auditivos'
    ],
    'TEA nivel 1 - perfil demo',
    NULL,
    v_terapeuta_id,
    v_tutor_id,
    TRUE
  )
  ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    fecha_nacimiento = EXCLUDED.fecha_nacimiento,
    nivel_cognitivo = EXCLUDED.nivel_cognitivo,
    perfil_sensorial = EXCLUDED.perfil_sensorial,
    objetivos_intervencion = EXCLUDED.objetivos_intervencion,
    diagnostico = EXCLUDED.diagnostico,
    terapeuta_id = EXCLUDED.terapeuta_id,
    tutor_id = EXCLUDED.tutor_id,
    activo = TRUE;

  INSERT INTO actividades (id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada, activo)
  VALUES
    (
      v_act1_id,
      'Atencion sensorial',
      'Calibracion con musica suave',
      'Presentar musica de baja intensidad y pedir seguimiento visual con apoyo minimo.',
      'Bajo',
      300,
      TRUE
    ),
    (
      v_act2_id,
      'Atencion conjunta',
      'Seguimiento visual con animales',
      'Mover tarjetas de animales de izquierda a derecha y registrar senalamiento espontaneo.',
      'Medio',
      900,
      TRUE
    ),
    (
      v_act3_id,
      'Regulacion emocional',
      'Cierre con colores tranquilos',
      'Usar laminas de color verde y conteo regresivo para transicion de cierre.',
      'Bajo',
      600,
      TRUE
    )
  ON CONFLICT (id) DO UPDATE SET
    tipo = EXCLUDED.tipo,
    nombre = EXCLUDED.nombre,
    instrucciones = EXCLUDED.instrucciones,
    nivel_dificultad = EXCLUDED.nivel_dificultad,
    duracion_estimada = EXCLUDED.duracion_estimada,
    activo = TRUE;

  INSERT INTO planes_terapeuticos (
    id, nombre, nino_id, terapeuta_id, fecha_inicio,
    nivel_dificultad_actual, criterios_progresion, activo
  )
  VALUES (
    v_plan_id,
    'Plan de intervencion inicial',
    v_nino_id,
    v_terapeuta_id,
    CURRENT_DATE,
    'Medio',
    '{"umbralAciertos": 0.8, "sesionesConsecutivas": 3, "latenciaMaximaMs": 5000}'::jsonb,
    TRUE
  )
  ON CONFLICT (id) DO UPDATE SET
    nombre = EXCLUDED.nombre,
    nino_id = EXCLUDED.nino_id,
    terapeuta_id = EXCLUDED.terapeuta_id,
    fecha_inicio = EXCLUDED.fecha_inicio,
    nivel_dificultad_actual = EXCLUDED.nivel_dificultad_actual,
    criterios_progresion = EXCLUDED.criterios_progresion,
    activo = TRUE;

  INSERT INTO plan_actividades (plan_id, actividad_id, orden)
  VALUES
    (v_plan_id, v_act1_id, 1),
    (v_plan_id, v_act2_id, 2),
    (v_plan_id, v_act3_id, 3)
  ON CONFLICT (plan_id, actividad_id) DO UPDATE SET orden = EXCLUDED.orden;

  INSERT INTO sesiones (id, nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at)
  VALUES (
    v_sesion_id,
    v_nino_id,
    v_plan_id,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '3 days' + INTERVAL '35 minutes',
    'completada',
    NOW() - INTERVAL '3 days' + INTERVAL '36 minutes'
  )
  ON CONFLICT (id) DO UPDATE SET
    fecha_inicio = EXCLUDED.fecha_inicio,
    fecha_fin = EXCLUDED.fecha_fin,
    estado = EXCLUDED.estado,
    sync_at = EXCLUDED.sync_at;

  DELETE FROM resultados_actividad WHERE sesion_id = v_sesion_id;
  INSERT INTO resultados_actividad (
    sesion_id, actividad_id, tiempo_respuesta, aciertos, repeticiones,
    nivel_ayuda_requerido, nivel_dificultad_usado, observaciones,
    emocion_detectada, confianza_emocion
  )
  VALUES
    (v_sesion_id, v_act1_id, 2.4, 8, 10, 0, 'Bajo', 'Buena tolerancia a la musica.', 'neutral', 0.82),
    (v_sesion_id, v_act2_id, 3.8, 6, 10, 1, 'Medio', 'Requirio apoyo verbal para sostener atencion.', 'happy', 0.74),
    (v_sesion_id, v_act3_id, 1.9, 9, 10, 0, 'Bajo', 'Transicion de cierre estable.', 'neutral', 0.91);

  RAISE NOTICE 'RimAI seed listo: terapeuta@rimai.com / test1234';
END $$;
