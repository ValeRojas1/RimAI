from typing import List
from app.application.ports.seguimiento_repository import ISeguimientoRepository
from app.domain.entities.actividad_ejecutada import ActividadEjecutada

class PostgresSeguimientoRepository(ISeguimientoRepository):
    def __init__(self):
        # Mock en memoria PMV3
        self.actividades = []

    def save_actividad_ejecutada(self, actividad: ActividadEjecutada) -> ActividadEjecutada:
        if not actividad.id:
            actividad.id = f"remote-{len(self.actividades)+1}"
        self.actividades.append(actividad)
        return actividad

    def get_by_patient_id(self, patient_id: int) -> List[ActividadEjecutada]:
        return [a for a in self.actividades if a.patient_id == patient_id]
