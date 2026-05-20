from typing import List
from app.domain.entities.reporte_progreso import ReporteAnalitico, MetricaDesempeno
from app.application.ports.seguimiento_repository import ISeguimientoRepository
from datetime import datetime

class GenerarReporteAnaliticoUseCase:
    def __init__(self, seguimiento_repo: ISeguimientoRepository):
        self.seguimiento_repo = seguimiento_repo

    def execute(self, patient_id: int, inicio: datetime, fin: datetime) -> ReporteAnalitico:
        actividades = self.seguimiento_repo.get_by_patient_id(patient_id)
        # Filtrar por fecha
        filtradas = [a for a in actividades if inicio <= a.timestamp_local <= fin]
        
        if not filtradas:
            return ReporteAnalitico(
                patient_id=patient_id,
                periodo_inicio=inicio,
                periodo_fin=fin,
                tasa_adherencia_global=0.0,
                metricas_por_actividad=[],
                observaciones_agrupadas=[],
                detonantes_frecuentes=[]
            )

        total_completadas = sum(1 for a in filtradas if a.completada)
        tasa_adherencia = total_completadas / len(filtradas)

        metricas_dict = {}
        observaciones = []
        detonantes = []

        for a in filtradas:
            if a.actividad_id not in metricas_dict:
                metricas_dict[a.actividad_id] = {"tiempos": [], "apoyos": [], "completadas": 0, "total": 0}
            
            m = metricas_dict[a.actividad_id]
            m["total"] += 1
            if a.completada:
                m["completadas"] += 1
            m["tiempos"].append(a.tiempo_empleado_segundos)
            m["apoyos"].append(a.nivel_apoyo_requerido)
            
            if a.observaciones:
                observaciones.append(a.observaciones)
            detonantes.extend(a.detonantes_presentados)

        metricas_list = []
        for act_id, m in metricas_dict.items():
            prom_tiempo = sum(m["tiempos"]) / m["total"] if m["total"] > 0 else 0
            prom_apoyo = sum(m["apoyos"]) / m["total"] if m["total"] > 0 else 0
            tasa_comp = m["completadas"] / m["total"] if m["total"] > 0 else 0
            
            metricas_list.append(MetricaDesempeno(
                actividad_id=act_id,
                promedio_tiempo=prom_tiempo,
                promedio_apoyo=prom_apoyo,
                tasa_completitud=tasa_comp
            ))

        return ReporteAnalitico(
            patient_id=patient_id,
            periodo_inicio=inicio,
            periodo_fin=fin,
            tasa_adherencia_global=tasa_adherencia,
            metricas_por_actividad=metricas_list,
            observaciones_agrupadas=observaciones,
            detonantes_frecuentes=list(set(detonantes)) # únicos
        )
