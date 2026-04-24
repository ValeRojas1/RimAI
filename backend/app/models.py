from sqlalchemy import create_engine, Column, String, Boolean, DateTime, Text, Float, Integer, Date, ARRAY, Enum as SAEnum, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import DeclarativeBase, relationship
from sqlalchemy.sql import func
import uuid
import enum


class Base(DeclarativeBase):
    pass


class RolUsuario(str, enum.Enum):
    terapeuta = "terapeuta"
    padre_tutor = "padre_tutor"
    admin = "admin"


class NivelCognitivo(str, enum.Enum):
    Bajo = "Bajo"
    Medio = "Medio"
    Alto = "Alto"


class NivelDificultad(str, enum.Enum):
    Bajo = "Bajo"
    Medio = "Medio"
    Alto = "Alto"


class EstadoSesion(str, enum.Enum):
    completada = "completada"
    interrumpida = "interrumpida"
    pendiente_sync = "pendiente_sync"


class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nombre = Column(String(150), nullable=False)
    email = Column(String(200), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    rol = Column(SAEnum(RolUsuario, name="rol_usuario"), nullable=False)
    activo = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    terapeuta = relationship("Terapeuta", back_populates="usuario", uselist=False)


class Terapeuta(Base):
    __tablename__ = "terapeutas"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    usuario_id = Column(UUID(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False)
    especialidad = Column(String(150))
    colegiatura = Column(String(50))

    usuario = relationship("Usuario", back_populates="terapeuta")
    ninos = relationship("Nino", back_populates="terapeuta")


class PadreTutor(Base):
    __tablename__ = "padres_tutores"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    usuario_id = Column(UUID(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False)
    telefono = Column(String(20))


class Nino(Base):
    __tablename__ = "ninos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nombre = Column(String(150), nullable=False)
    fecha_nacimiento = Column(Date, nullable=False)
    nivel_cognitivo = Column(SAEnum(NivelCognitivo, name="nivel_cognitivo"), nullable=False)
    perfil_sensorial = Column(JSONB)
    objetivos_intervencion = Column(ARRAY(Text))
    terapeuta_id = Column(UUID(as_uuid=True), ForeignKey("terapeutas.id"), nullable=False)
    tutor_id = Column(UUID(as_uuid=True), ForeignKey("padres_tutores.id"))
    activo = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    terapeuta = relationship("Terapeuta", back_populates="ninos")
    sesiones = relationship("Sesion", back_populates="nino")
    planes = relationship("PlanTerapeutico", back_populates="nino")


class Actividad(Base):
    __tablename__ = "actividades"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tipo = Column(String(100), nullable=False)
    nombre = Column(String(200), nullable=False)
    instrucciones = Column(Text)
    nivel_dificultad = Column(SAEnum(NivelDificultad, name="nivel_dificultad"), nullable=False)
    duracion_estimada = Column(Integer)
    recursos_multimedia = Column(JSONB)
    activo = Column(Boolean, default=True)


class PlanTerapeutico(Base):
    __tablename__ = "planes_terapeuticos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nino_id = Column(UUID(as_uuid=True), ForeignKey("ninos.id"), nullable=False)
    terapeuta_id = Column(UUID(as_uuid=True), ForeignKey("terapeutas.id"), nullable=False)
    fecha_inicio = Column(Date, nullable=False)
    fecha_fin = Column(Date)
    nivel_dificultad_actual = Column(SAEnum(NivelDificultad, name="nivel_dificultad"), default="Bajo")
    criterios_progresion = Column(JSONB)
    activo = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    nino = relationship("Nino", back_populates="planes")
    sesiones = relationship("Sesion", back_populates="plan")


class Sesion(Base):
    __tablename__ = "sesiones"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    nino_id = Column(UUID(as_uuid=True), ForeignKey("ninos.id"), nullable=False)
    plan_id = Column(UUID(as_uuid=True), ForeignKey("planes_terapeuticos.id"), nullable=False)
    fecha_inicio = Column(DateTime(timezone=True), nullable=False)
    fecha_fin = Column(DateTime(timezone=True))
    estado = Column(SAEnum(EstadoSesion, name="estado_sesion"), default="pendiente_sync")
    sync_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    nino = relationship("Nino", back_populates="sesiones")
    plan = relationship("PlanTerapeutico", back_populates="sesiones")
    resultados = relationship("ResultadoActividad", back_populates="sesion")


class ResultadoActividad(Base):
    __tablename__ = "resultados_actividad"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sesion_id = Column(UUID(as_uuid=True), ForeignKey("sesiones.id"), nullable=False)
    actividad_id = Column(UUID(as_uuid=True), ForeignKey("actividades.id"), nullable=False)
    tiempo_respuesta = Column(Float)
    aciertos = Column(Integer)
    repeticiones = Column(Integer)
    nivel_ayuda_requerido = Column(Integer, default=0)
    emocion_detectada = Column(String(50))
    confianza_emocion = Column(Float)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    sesion = relationship("Sesion", back_populates="resultados")
