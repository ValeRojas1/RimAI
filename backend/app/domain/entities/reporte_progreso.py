from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class MetricaDesempeno(BaseModel):
    actividad_id: str
    promedio_tiempo: float
    promedio_apoyo: float
    tasa_completitud: float

class ReporteAnalitico(BaseModel):
    patient_id: int
    periodo_inicio: datetime
    periodo_fin: datetime
    tasa_adherencia_global: float # % de actividades ejecutadas vs planificadas
    metricas_por_actividad: List[MetricaDesempeno]
    observaciones_agrupadas: List[str]
    detonantes_frecuentes: List[str]
