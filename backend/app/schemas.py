from pydantic import BaseModel, EmailStr
from typing import Optional, List, Any
from datetime import date, datetime
import uuid


# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    nombre: str
    rol: str


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

    class Config:
        from_attributes = True


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
