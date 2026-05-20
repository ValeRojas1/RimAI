from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class ActividadEjecutada(BaseModel):
    id: Optional[str] = None # UUID desde el frontend (SQLite)
    patient_id: int
    actividad_id: str
    plan_id: int
    tiempo_empleado_segundos: int
    nivel_apoyo_requerido: int # 0=Independiente, 1=Verbal, 2=Físico parcial, etc.
    observaciones: str
    detonantes_presentados: List[str]
    completada: bool
    timestamp_local: datetime # Timestamp en que el padre la ejecutó offline
    synced_at: Optional[datetime] = None # Timestamp en que llegó al server
