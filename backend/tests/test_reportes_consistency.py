import pytest
from datetime import datetime, timedelta
from app.application.usecases.generar_reporte_analitico_usecase import GenerarReporteAnaliticoUseCase
from app.domain.entities.actividad_ejecutada import ActividadEjecutada

class MockSeguimientoRepository:
    def __init__(self):
        self.data = []
    def save_actividad_ejecutada(self, a):
        pass
    def get_by_patient_id(self, patient_id):
        return [a for a in self.data if a.patient_id == patient_id]

def test_generar_reporte_consistency():
    repo = MockSeguimientoRepository()
    
    now = datetime.utcnow()
    repo.data = [
        ActividadEjecutada(
            id="1", patient_id=1, actividad_id="A1", plan_id=1,
            tiempo_empleado_segundos=120, nivel_apoyo_requerido=1, observaciones="ok",
            detonantes_presentados=["ruido"], completada=True, timestamp_local=now
        ),
        ActividadEjecutada(
            id="2", patient_id=1, actividad_id="A1", plan_id=1,
            tiempo_empleado_segundos=60, nivel_apoyo_requerido=2, observaciones="difícil",
            detonantes_presentados=["luz"], completada=False, timestamp_local=now
        ),
        ActividadEjecutada(
            id="3", patient_id=1, actividad_id="A2", plan_id=1,
            tiempo_empleado_segundos=300, nivel_apoyo_requerido=0, observaciones="muy bien",
            detonantes_presentados=[], completada=True, timestamp_local=now
        )
    ]
    
    uc = GenerarReporteAnaliticoUseCase(repo)
    reporte = uc.execute(1, now - timedelta(days=1), now + timedelta(days=1))
    
    # 2 completadas de 3 totales = 66.6%
    assert abs(reporte.tasa_adherencia_global - (2/3)) < 0.01
    
    # 2 actividades distintas: A1, A2
    assert len(reporte.metricas_por_actividad) == 2
    
    # Metricas A1: 2 items. Tiempos: 120, 60 (avg 90). Apoyos: 1, 2 (avg 1.5). Completadas 1 de 2 (50%)
    m_A1 = next(m for m in reporte.metricas_por_actividad if m.actividad_id == "A1")
    assert m_A1.promedio_tiempo == 90
    assert m_A1.promedio_apoyo == 1.5
    assert m_A1.tasa_completitud == 0.5
    
    # Detonantes: ruido, luz
    assert "ruido" in reporte.detonantes_frecuentes
    assert "luz" in reporte.detonantes_frecuentes
    assert len(reporte.detonantes_frecuentes) == 2
