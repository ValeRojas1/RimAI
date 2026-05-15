from pydantic import BaseModel, EmailStr
from typing import Optional, List, Any, Dict
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
    plan_activo_id: Optional[str] = None
    ultima_sesion: Optional[UltimaSesionInfo]
    foto_url: Optional[str] = None
    # Estado clínico-administrativo
    estado_clinico: str = "pendiente_asignacion"

    class Config:
        from_attributes = True


class DashboardResumen(BaseModel):
    terapeuta_id: Optional[str] = None
    terapeuta_nombre: Optional[str] = None
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
    diagnostico: Optional[str] = None
    nivel_cognitivo: str
    perfil_sensorial: Optional[Any]
    objetivos_intervencion: Optional[List[str]]
    intereses: List[str] = []
    estimulos_aversivos: dict = {}
    documento_diagnostico: Optional[str] = None
    plan_activo_id: Optional[str] = None
    # Estado clínico y trazabilidad
    estado_clinico: str = "pendiente_asignacion"
    vinculado_at: Optional[datetime] = None
    perfil_completado_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class VincularPacienteRequest(BaseModel):
    nombre: str
    fecha_nacimiento: date
    nivel_cognitivo: str
    objetivos_intervencion: List[str]
    perfil_sensorial: dict


# ── Admisión Familiar ────────────────────────────────────────────────────

class HitosDesarrolloIn(BaseModel):
    comunicacion: Optional[str] = None
    contacto_visual: Optional[str] = None
    juego_social: Optional[str] = None
    motricidad: List[str] = []


class PerfilSensorialIn(BaseModel):
    hipersensibilidad: List[str] = []
    hiposensibilidad: List[str] = []
    comportamientos_repetitivos: List[str] = []
    intereses_obsesivos: List[str] = []
    estimulos_aversivos: Optional[Dict[str, List[str]]] = None


class CrearPacienteFamiliaRequest(BaseModel):
    """Schema tipado para el wizard de admisión familiar."""
    nombre: str
    fecha_nacimiento: date
    diagnostico: Optional[str] = None
    documento_diagnostico: Optional[str] = None
    hitos: Optional[HitosDesarrolloIn] = None
    sensorial: Optional[PerfilSensorialIn] = None


# ── Bandeja de espera del terapeuta ───────────────────────────────────

class NinoPendienteOut(BaseModel):
    """Resumen de un niño en estado pendiente para la bandeja del terapeuta."""
    id: str
    nombre: str
    edad: int
    estado_clinico: str
    fecha_registro: datetime
    diagnostico: Optional[str] = None
    # Datos extraídos del perfil_sensorial para vista previa rápida
    comunicacion: Optional[str] = None
    intereses: List[str] = []
    tutor_nombre: Optional[str] = None

    class Config:
        from_attributes = True


# ── Enriquecimiento clínico (terapeuta) ───────────────────────────────

class PerfilClinicoRequest(BaseModel):
    """Datos clínicos que el terapeuta completa/valida tras la vinculación."""
    nivel_cognitivo: str  # Bajo | Medio | Alto
    objetivos_intervencion: List[str]
    perfil_sensorial: Optional[Dict[str, Any]] = None
    observaciones_clinicas: Optional[str] = None


class PerfilClinicoResponse(BaseModel):
    estado_clinico: str
    perfil_completado_at: Optional[datetime]
    campos_faltantes: List[str] = []
    mensaje: str


# ── Trazabilidad ──────────────────────────────────────────────────────────

class TrazabilidadItem(BaseModel):
    id: str
    recomendacion_id: str
    accion: str
    observacion: Optional[str]
    created_at: datetime

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
    nombre: str
    nino_id: str
    nino_nombre: str
    fecha_inicio: date
    nivel_dificultad_actual: str
    activo: bool
    actividades: List[ActividadOut] = []

    class Config:
        from_attributes = True


class GenerarPlanResponse(BaseModel):
    plan_id: str
    dificultad_inicial: str
    confianza_ia: float
    mensaje: str


# ── Sesión ────────────────────────────────────────────────────────────────────

class ResultadoActividadIn(BaseModel):
    actividad_id: str
    aciertos: int
    repeticiones: int
    tiempo_respuesta: float
    nivel_ayuda_requerido: int = 0
    nivel_dificultad_usado: Optional[str] = "Medio"
    observaciones: Optional[str] = None
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


class NivelInicialRequest(BaseModel):
    nino_id: str
    actividad_id: Optional[str] = None


class NivelInicialResponse(BaseModel):
    nivel_recomendado: str
    confianza: float
    latencia_ms: float
    fallback: bool = False
    mensaje: Optional[str] = None


class AsistenteIAResponse(BaseModel):
    nino_id: str
    nino_nombre: str
    analisis_cognitivo: dict
    recomendaciones: List[dict]
    plan_sesion: List[dict]


class DecisionClinicaRequest(BaseModel):
    recomendacion_id: str
    accion: str
    observacion: Optional[str] = None
    nino_id: Optional[str] = None


class MetricasProgresoOut(BaseModel):
    sesiones_completadas: int
    tasa_aciertos: float
    adherencia: float
    historia_aciertos: List[float]
