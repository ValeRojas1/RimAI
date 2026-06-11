from pydantic import BaseModel
from typing import List, Optional, Union
from enum import Enum
from datetime import datetime

class NivelIndicioSCQ(str, Enum):
    BAJO = "Bajo"
    MODERADO = "Moderado"
    ALTO = "Alto"

class CuestionarioSCQ(BaseModel):
    id: Optional[int] = None
    patient_id: Union[int, str]
    tutor_id: Union[int, str]
    respuestas: List[int] # Arreglo de 0s y 1s
    puntaje_total: Optional[int] = None
    nivel_indicio: Optional[NivelIndicioSCQ] = None
    acepto_disclaimer: bool
    created_at: Optional[datetime] = None

class ResultadoScoring(BaseModel):
    puntaje_total: int
    nivel_indicio: NivelIndicioSCQ
