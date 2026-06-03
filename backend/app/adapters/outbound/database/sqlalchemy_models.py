from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Float
from sqlalchemy.orm import declarative_base
from datetime import datetime

Base = declarative_base()

class UserModel(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    role = Column(String, nullable=False)
    nombre_completo = Column(String, nullable=False)
    especialidad = Column(String, nullable=True)
    numero_colegiatura = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class PatientModel(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String, nullable=False)
    edad = Column(Integer, nullable=False)
    diagnostico_declarado = Column(String, nullable=False)
    tutor_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.utcnow)

class ClinicalProfileModel(Base):
    __tablename__ = "clinical_profiles"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"))
    antecedentes_clinicos = Column(String, nullable=False)
    escolaridad = Column(String, nullable=False)
    perfil_sensorial_score = Column(Integer, nullable=False)
    contexto_familiar_score = Column(Integer, nullable=False)
    preferencias = Column(String, nullable=False)
    is_medicated = Column(Boolean, nullable=False)
    medication_description = Column(String, nullable=True)
    calming_rituals_json = Column(String, nullable=False) # Guardado como string JSON para simplificar
    source = Column(String, nullable=False) # Tag inalterable (Tutor vs Terapeuta)
    created_at = Column(DateTime, default=datetime.utcnow)

class ExternalEvaluationModel(Base):
    __tablename__ = "external_evaluations"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"))
    file_url = Column(String, nullable=False)
    uploaded_by = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class CuestionarioSCQModel(Base):
    __tablename__ = "cuestionarios_scq"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"))
    tutor_id = Column(Integer, ForeignKey("users.id"))
    respuestas_json = Column(String, nullable=False)
    puntaje_total = Column(Integer, nullable=False)
    nivel_indicio = Column(String, nullable=False)
    acepto_disclaimer = Column(Boolean, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class PlanTerapeuticoModel(Base):
    __tablename__ = "planes_terapeuticos_v2" # v2 para separar del de init.sql si fuera necesario
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"))
    terapeuta_id = Column(Integer, ForeignKey("users.id"))
    estado = Column(String, nullable=False)
    sugerencias_json = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class ActividadEjecutadaModel(Base):
    __tablename__ = "actividades_ejecutadas"
    id = Column(String, primary_key=True, index=True) # UUID
    patient_id = Column(Integer, ForeignKey("patients.id"))
    actividad_id = Column(String, nullable=False)
    plan_id = Column(Integer, nullable=False)
    tiempo_empleado_segundos = Column(Integer, nullable=False)
    nivel_apoyo_requerido = Column(Integer, nullable=False)
    observaciones = Column(String)
    detonantes_presentados_json = Column(String)
    completada = Column(Boolean, nullable=False)
    timestamp_local = Column(DateTime, nullable=False)
    synced_at = Column(DateTime, default=datetime.utcnow)

class AlertaAdherenciaModel(Base):
    __tablename__ = "alertas_adherencia"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"))
    terapeuta_id = Column(Integer, ForeignKey("users.id"))
    severidad = Column(String, nullable=False)
    mensaje = Column(String, nullable=False)
    tasa_actual = Column(Float, nullable=False)
    umbral_minimo = Column(Float, nullable=False)
    resuelta = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

class LogTrazabilidadModel(Base):
    __tablename__ = "logs_auditoria"
    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("users.id"))
    rol_usuario = Column(String, nullable=False)
    accion = Column(String, nullable=False)
    entidad_afectada = Column(String, nullable=False)
    entidad_id = Column(String, nullable=False)
    payload_anterior = Column(String)
    payload_nuevo = Column(String, nullable=False)
    timestamp_servidor = Column(DateTime, default=datetime.utcnow)
