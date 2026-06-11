from pydantic import BaseModel
from typing import Optional, Union
from enum import Enum
from datetime import datetime

class SeveridadAlerta(str, Enum):
    INFO = "INFO"
    ADVERTENCIA = "ADVERTENCIA"
    CRITICA = "CRITICA"

class AlertaAdherencia(BaseModel):
    id: Optional[int] = None
    patient_id: Union[int, str]
    terapeuta_id: Union[int, str]
    severidad: SeveridadAlerta
    mensaje: str
    tasa_actual: float
    umbral_minimo: float
    resuelta: bool = False
    created_at: Optional[datetime] = None
