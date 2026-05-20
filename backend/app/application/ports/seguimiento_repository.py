from abc import ABC, abstractmethod
from typing import List
from app.domain.entities.actividad_ejecutada import ActividadEjecutada

class ISeguimientoRepository(ABC):
    @abstractmethod
    def save_actividad_ejecutada(self, actividad: ActividadEjecutada) -> ActividadEjecutada:
        pass

    @abstractmethod
    def get_by_patient_id(self, patient_id: int) -> List[ActividadEjecutada]:
        pass
