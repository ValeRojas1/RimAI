from pydantic import BaseModel
from typing import Optional, List, Union
from datetime import datetime
from enum import Enum

class CalmingRitualType(str, Enum):
    CAMBIOS_RUTINA = "CAMBIOS_RUTINA"
    AMBIENTES_RUIDOSOS = "AMBIENTES_RUIDOSOS"
    INTERACCION_SOCIAL = "INTERACCION_SOCIAL"

class SourceEnum(str, Enum):
    TUTOR = "Tutor"
    TERAPEUTA = "Terapeuta"

class Medication(BaseModel):
    is_medicated: bool
    description: Optional[str] = None

class CalmingRitual(BaseModel):
    ritual_type: CalmingRitualType
    description: str

class ClinicalProfile(BaseModel):
    id: Optional[int] = None
    patient_id: Union[int, str]
    antecedentes_clinicos: str
    escolaridad: str
    perfil_sensorial_score: int
    contexto_familiar_score: int
    preferencias: str
    medication: Medication
    calming_rituals: List[CalmingRitual]
    source: SourceEnum
    created_at: Optional[datetime] = None

class Patient(BaseModel):
    id: Optional[Union[int, str]] = None
    nombre: str
    edad: int
    diagnostico_declarado: str
    tutor_id: Union[int, str]
    created_at: Optional[datetime] = None

class ExternalEvaluation(BaseModel):
    id: Optional[int] = None
    patient_id: Union[int, str]
    file_url: str
    uploaded_by: SourceEnum
    created_at: Optional[datetime] = None
