import pytest
from datetime import datetime
from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from app.domain.entities.alerta_adherencia import SeveridadAlerta

class MockReportesRepository:
    def __init__(self):
        self.alertas = []
    def save_alerta(self, alerta):
        self.alertas.append(alerta)
        return alerta
    def get_alertas_by_patient(self, p_id):
        pass
    def get_reporte_by_patient(self, p_id):
        pass
    def save_reporte(self, r):
        pass

def test_evaluar_adherencia_baja_critica():
    repo = MockReportesRepository()
    uc = EvaluarAdherenciaUseCase(repo)
    
    # 40% < 50% = CRITICA
    alerta = uc.execute(patient_id=1, terapeuta_id=1, tasa_actual=0.4, umbral_minimo=0.7)
    
    assert alerta is not None
    assert alerta.severidad == SeveridadAlerta.CRITICA
    assert "40.0%" in alerta.mensaje

def test_evaluar_adherencia_baja_advertencia():
    repo = MockReportesRepository()
    uc = EvaluarAdherenciaUseCase(repo)
    
    # 60% < 70% pero >= 50% = ADVERTENCIA
    alerta = uc.execute(patient_id=1, terapeuta_id=1, tasa_actual=0.6, umbral_minimo=0.7)
    
    assert alerta is not None
    assert alerta.severidad == SeveridadAlerta.ADVERTENCIA
    assert "60.0%" in alerta.mensaje

def test_evaluar_adherencia_optima():
    repo = MockReportesRepository()
    uc = EvaluarAdherenciaUseCase(repo)
    
    # 80% >= 70% = NINGUNA ALERTA
    alerta = uc.execute(patient_id=1, terapeuta_id=1, tasa_actual=0.8, umbral_minimo=0.7)
    
    assert alerta is None
    assert len(repo.alertas) == 0
