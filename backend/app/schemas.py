from pydantic import BaseModel, EmailStr
from typing import Optional, List, Any
from datetime import date, datetime
import uuid


# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RegisterRequest(BaseModel):
    nombre: str
    email: EmailStr
    password: str
    rol: str = "terapeuta"


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    nombre: str
    rol: str


# ── Admin ─────────────────────────────────────────────────────────────────────

class UsuarioOut(BaseModel):
    id: str
    nombre: str
    email: EmailStr
    rol: str
    activo: bool
    created_at: datetime

    class Config:
        from_attributes = True

class CrearUsuarioAdminRequest(BaseModel):
    nombre: str
    email: EmailStr
    password: str
    rol: str
    especialidad: Optional[str] = None
    colegiatura: Optional[str] = None

class ActualizarEstadoUsuarioRequest(BaseModel):
    activo: bool

class AdminEstadisticasOut(BaseModel):
    total_terapeutas: int
    total_familias: int
    total_ninos: int
    total_sesiones: int


# ── Pacientes (Dashboard) ─────────────────────────────────────────────────────

class UltimaSesionInfo(BaseModel):
    fecha: Optional[datetime]
    tasa_aciertos: Optional[float]
    estado: Optional[str]


class PacienteDashboard(BaseModel):
    id: str
    nombre: str
    edad: int
    nivel_cognitivo: str
    plan_activo: Optional[str]
    ultima_sesion: Optional[UltimaSesionInfo]
    foto_url: Optional[str] = None

    class Config:
        from_attributes = True


class DashboardResumen(BaseModel):
    total_pacientes: int
    sesiones_esta_semana: int
    alertas_baja_adherencia: int
    pacientes: List[PacienteDashboard]


# ── Perfil del Niño ───────────────────────────────────────────────────────────

class PerfilNino(BaseModel):
    id: str
    nombre: str
    fecha_nacimiento: date
    edad: int
    nivel_cognitivo: str
    perfil_sensorial: Optional[Any]
    objetivos_intervencion: Optional[List[str]]

class HitosDesarrollo(BaseModel):
    comunicacion: str
    contacto_visual: str
    juego_social: str
    motricidad: List[str] = []

class PerfilSensorialIA(BaseModel):
    hipersensibilidad: List[str] = []
    hiposensibilidad: List[str] = []
    comportamientos_repetitivos: List[str] = []
    intereses_obsesivos: List[str] = []

class CrearNinoFamiliarRequest(BaseModel):
    nombre: str
    fecha_nacimiento: date
    hitos: HitosDesarrollo
    sensorial: PerfilSensorialIA

class VincularPacienteRequest(BaseModel):
    nombre: str
    fecha_nacimiento: date
    nivel_cognitivo: str
    objetivos_intervencion: List[str]
    perfil_sensorial: dict

# ── Plan Terapéutico ──────────────────────────────────────────────────────────

class ActividadOut(BaseModel):
    id: str
    nombre: str
    tipo: str
    instrucciones: Optional[str]
    nivel_dificultad: str
    duracion_estimada: Optional[int]

    class Config:
        from_attributes = True


class PlanOut(BaseModel):
    id: str
    fecha_inicio: date
    nivel_dificultad_actual: str
    activo: bool
    actividades: List[ActividadOut] = []

    class Config:
        from_attributes = True


# ── Sesión ────────────────────────────────────────────────────────────────────

class ResultadoActividadIn(BaseModel):
    actividad_id: str
    aciertos: int
    repeticiones: int
    tiempo_respuesta: float
    nivel_ayuda_requerido: int = 0
    emocion_detectada: Optional[str] = None
    confianza_emocion: Optional[float] = None


class CrearSesionRequest(BaseModel):
    nino_id: str
    plan_id: str
    resultados: List[ResultadoActividadIn] = []


class SesionResumen(BaseModel):
    sesion_id: str
    nino_nombre: str
    fecha: datetime
    total_aciertos: int
    total_intentos: int
    tasa_aciertos: float
    nivel_dificultad_recomendado: str
