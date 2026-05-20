from pydantic import BaseModel
from typing import Optional
from enum import Enum
from datetime import datetime

class SeveridadAlerta(str, Enum):
    INFO = "INFO"
    ADVERTENCIA = "ADVERTENCIA"
    CRITICA = "CRITICA"

class AlertaAdherencia(BaseModel):
    id: Optional[int] = None
    patient_id: int
    terapeuta_id: int
    severidad: SeveridadAlerta
    mensaje: str
    tasa_actual: float
    umbral_minimo: float
    resuelta: bool = False
    created_at: Optional[datetime] = None
