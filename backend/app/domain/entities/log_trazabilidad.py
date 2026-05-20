from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class LogTrazabilidad(BaseModel):
    id: Optional[int] = None
    usuario_id: int
    rol_usuario: str
    accion: str
    entidad_afectada: str
    entidad_id: str
    payload_anterior: Optional[str] = None
    payload_nuevo: str
    timestamp_servidor: Optional[datetime] = None
