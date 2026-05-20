from pydantic import BaseModel
from typing import List, Optional
from enum import Enum
from datetime import datetime

class EstadoPlan(str, Enum):
    BORRADOR = "Borrador"
    VALIDADO = "Validado"

class SugerenciaActividad(BaseModel):
    id: Optional[int] = None
    actividad_id: str
    nombre: str
    justificacion: str # Por qué el motor sugiere esto (ej: "Apto para evitar hiperreactividad auditiva")

class PlanTerapeutico(BaseModel):
    id: Optional[int] = None
    patient_id: int
    terapeuta_id: int
    estado: EstadoPlan
    sugerencias: List[SugerenciaActividad]
    created_at: Optional[datetime] = None
