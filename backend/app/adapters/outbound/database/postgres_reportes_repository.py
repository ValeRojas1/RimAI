from typing import List
from app.application.ports.reportes_repository import IReportesRepository
from app.domain.entities.alerta_adherencia import AlertaAdherencia
from app.domain.entities.reporte_progreso import ReporteAnalitico

class PostgresReportesRepository(IReportesRepository):
    def __init__(self):
        self.alertas = []
        self.reportes = []
        self.next_alerta_id = 1

    def save_alerta(self, alerta: AlertaAdherencia) -> AlertaAdherencia:
        alerta.id = self.next_alerta_id
        self.next_alerta_id += 1
        self.alertas.append(alerta)
        return alerta

    def get_alertas_by_patient(self, patient_id: int) -> List[AlertaAdherencia]:
        return [a for a in self.alertas if a.patient_id == patient_id]
    
    def save_reporte(self, reporte: ReporteAnalitico) -> ReporteAnalitico:
        self.reportes.append(reporte)
        return reporte

    def get_reporte_by_patient(self, patient_id: int) -> ReporteAnalitico:
        reportes_pt = [r for r in self.reportes if r.patient_id == patient_id]
        if reportes_pt:
            return reportes_pt[-1]
        return None
