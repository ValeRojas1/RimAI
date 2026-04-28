-- ============================================
-- RimAI — Seed Data — PMV1 + PMV2 Demo
-- ============================================
-- BCrypt hash of "test1234" (12 rounds)
-- $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewfGsPU.Q5VCpBe

DO $$
DECLARE
  v_usuario_id    UUID;
  v_terapeuta_id  UUID;
  v_tutor_id      UUID;
  v_tutor_usr_id  UUID;
  v_nino_id       UUID;
  v_act1_id       UUID;
  v_act2_id       UUID;
  v_act3_id       UUID;
  v_plan_id       UUID;
  v_sesion_id     UUID;
BEGIN
  -- ----------------------------------------
  -- 1. Usuario Terapeuta
  -- ----------------------------------------
  INSERT INTO usuarios (nombre, email, password_hash, rol)
  VALUES (
    'Dra. Sofía Ramírez',
    'terapeuta@rimai.com',
    '$2b$12$UWjEtaWqTpjmkWmzdNeW1.QXidbvIj.Qh4z3Tfkv1JI4SV/WGI38C',
    'terapeuta'
  )
  ON CONFLICT (email) DO NOTHING
  RETURNING id INTO v_usuario_id;

  -- Si ya existía, obtenemos el id
  IF v_usuario_id IS NULL THEN
    SELECT id INTO v_usuario_id FROM usuarios WHERE email = 'terapeuta@rimai.com';
  END IF;

  -- Crear perfil de terapeuta
  INSERT INTO terapeutas (usuario_id, especialidad, colegiatura)
  VALUES (v_usuario_id, 'Terapia Ocupacional con enfoque TEA', 'TO-2021-4892')
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_terapeuta_id;

  IF v_terapeuta_id IS NULL THEN
    SELECT id INTO v_terapeuta_id FROM terapeutas WHERE usuario_id = v_usuario_id;
  END IF;

  -- ----------------------------------------
  -- 2. Usuario Tutor (para Lucas)
  -- ----------------------------------------
  INSERT INTO usuarios (nombre, email, password_hash, rol)
  VALUES (
    'Carlos Mendoza',
    'tutor.lucas@rimai.com',
    '$2b$12$UWjEtaWqTpjmkWmzdNeW1.QXidbvIj.Qh4z3Tfkv1JI4SV/WGI38C',
    'padre_tutor'
  )
  ON CONFLICT (email) DO NOTHING
  RETURNING id INTO v_tutor_usr_id;

  IF v_tutor_usr_id IS NULL THEN
    SELECT id INTO v_tutor_usr_id FROM usuarios WHERE email = 'tutor.lucas@rimai.com';
  END IF;

  INSERT INTO padres_tutores (usuario_id, telefono)
  VALUES (v_tutor_usr_id, '+52 55 1234 5678')
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_tutor_id;

  IF v_tutor_id IS NULL THEN
    SELECT id INTO v_tutor_id FROM padres_tutores WHERE usuario_id = v_tutor_usr_id;
  END IF;

  -- ----------------------------------------
  -- 3. Niño — Lucas Mendoza
  -- ----------------------------------------
  INSERT INTO ninos (
    nombre, fecha_nacimiento, nivel_cognitivo,
    perfil_sensorial, objetivos_intervencion,
    terapeuta_id, tutor_id
  )
  VALUES (
    'Lucas Mendoza',
    '2017-03-12',
    'Medio',
    '{
      "intereses": ["Dinosaurios", "Trenes", "Lego", "Manzanas", "Pelotas"],
      "estimulosAversivos": {
        "RUIDO": ["Licuadora", "Gritos fuertes", "Sirenas"],
        "COLORES": ["Rojo chillón", "Naranja intenso"],
        "TEXTURAS": ["Superficies rugosas"],
        "LUGARES": ["Espacios muy llenos de gente"]
      },
      "umbralSensorial": "bajo",
      "preferenciasEntorno": ["Luz tenue", "Música suave", "Espacios ordenados"]
    }'::jsonb,
    ARRAY[
      'Mejorar atención conjunta sostenida >5 min',
      'Desarrollar habilidades de comunicación funcional',
      'Reducir conductas de evitación sensorial',
      'Fortalecer motricidad fina para actividades cotidianas'
    ],
    v_terapeuta_id,
    v_tutor_id
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_nino_id;

  IF v_nino_id IS NULL THEN
    SELECT id INTO v_nino_id FROM ninos WHERE nombre = 'Lucas Mendoza' AND terapeuta_id = v_terapeuta_id;
  END IF;

  -- ----------------------------------------
  -- 4. Actividades
  -- ----------------------------------------
  INSERT INTO actividades (tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada)
  VALUES (
    'Atención Sensorial',
    'Calibración con Luces Verdes',
    'Usar pantalla con ondas suaves en tono verde. Pedir al niño que siga el movimiento con los ojos. Observar nivel de calma basal.',
    'Bajo',
    300
  ) RETURNING id INTO v_act1_id;

  INSERT INTO actividades (tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada)
  VALUES (
    'Atención Conjunta',
    'Seguimiento Visual con Dinosaurios',
    'Desplazar figura de dinosaurio de izquierda a derecha. Solicitar al niño señalar el dinosaurio cuando se detiene. Registrar latencia de respuesta.',
    'Medio',
    900
  ) RETURNING id INTO v_act2_id;

  INSERT INTO actividades (tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada)
  VALUES (
    'Regulación Emocional',
    'Cierre y Transición con Conteo Regresivo',
    'Iniciar conteo regresivo 5-4-3-2-1 con apoyo visual. Actividad de propioception: presión suave en hombros. Canción de cierre familiar.',
    'Bajo',
    600
  ) RETURNING id INTO v_act3_id;

  -- ----------------------------------------
  -- 5. Plan Terapéutico Activo
  -- ----------------------------------------
  INSERT INTO planes_terapeuticos (
    nino_id, terapeuta_id, fecha_inicio,
    nivel_dificultad_actual, criterios_progresion, activo
  )
  VALUES (
    v_nino_id, v_terapeuta_id, NOW()::DATE,
    'Bajo',
    '{
      "umbralAciertos": 0.8,
      "sesionesConsecutivas": 3,
      "latenciaMaxima": 5000
    }'::jsonb,
    TRUE
  ) RETURNING id INTO v_plan_id;

  -- Asignar actividades al plan
  INSERT INTO plan_actividades (plan_id, actividad_id, orden) VALUES
    (v_plan_id, v_act1_id, 1),
    (v_plan_id, v_act2_id, 2),
    (v_plan_id, v_act3_id, 3);

  -- ----------------------------------------
  -- 6. Sesión Previa (para historial IA-01)
  -- ----------------------------------------
  INSERT INTO sesiones (nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at)
  VALUES (
    v_nino_id, v_plan_id,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '3 days' + INTERVAL '45 minutes',
    'completada',
    NOW() - INTERVAL '3 days' + INTERVAL '46 minutes'
  ) RETURNING id INTO v_sesion_id;

  -- Resultados de la sesión previa
  INSERT INTO resultados_actividad (
    sesion_id, actividad_id, tiempo_respuesta, aciertos,
    repeticiones, nivel_ayuda_requerido, emocion_detectada, confianza_emocion
  ) VALUES
    (v_sesion_id, v_act1_id, 2.4, 8, 10, 0, 'neutral', 0.82),
    (v_sesion_id, v_act2_id, 3.8, 6, 10, 1, 'happy', 0.74),
    (v_sesion_id, v_act3_id, 1.9, 9, 10, 0, 'neutral', 0.91);

  RAISE NOTICE 'Seed completado. Terapeuta: %, Niño: %, Plan: %', v_usuario_id, v_nino_id, v_plan_id;
END $$;
