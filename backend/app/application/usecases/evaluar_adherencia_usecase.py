from app.domain.entities.alerta_adherencia import AlertaAdherencia, SeveridadAlerta
from app.application.ports.reportes_repository import IReportesRepository
from datetime import datetime

class EvaluarAdherenciaUseCase:
    def __init__(self, reportes_repo: IReportesRepository):
        self.reportes_repo = reportes_repo

    def execute(self, patient_id: int, terapeuta_id: int, tasa_actual: float, umbral_minimo: float = 0.7) -> AlertaAdherencia:
        if tasa_actual < umbral_minimo:
            # Generar alerta
            severidad = SeveridadAlerta.CRITICA if tasa_actual < 0.5 else SeveridadAlerta.ADVERTENCIA
            mensaje = f"Baja adherencia detectada: {(tasa_actual * 100):.1f}%. El umbral mínimo esperado es {(umbral_minimo * 100):.1f}%."
            alerta = AlertaAdherencia(
                patient_id=patient_id,
                terapeuta_id=terapeuta_id,
                severidad=severidad,
                mensaje=mensaje,
                tasa_actual=tasa_actual,
                umbral_minimo=umbral_minimo,
                created_at=datetime.utcnow()
            )
            return self.reportes_repo.save_alerta(alerta)
        return None
