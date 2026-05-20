from abc import ABC, abstractmethod
from typing import List
from app.domain.entities.reporte_progreso import ReporteAnalitico
from app.domain.entities.alerta_adherencia import AlertaAdherencia

class IReportesRepository(ABC):
    @abstractmethod
    def save_alerta(self, alerta: AlertaAdherencia) -> AlertaAdherencia:
        pass

    @abstractmethod
    def get_alertas_by_patient(self, patient_id: int) -> List[AlertaAdherencia]:
        pass
    
    @abstractmethod
    def get_reporte_by_patient(self, patient_id: int) -> ReporteAnalitico:
        pass
    
    @abstractmethod
    def save_reporte(self, reporte: ReporteAnalitico) -> ReporteAnalitico:
        pass
