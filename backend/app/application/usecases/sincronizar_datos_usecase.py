from typing import List
from datetime import datetime
from app.domain.entities.actividad_ejecutada import ActividadEjecutada
from app.domain.entities.log_trazabilidad import LogTrazabilidad
from app.application.ports.seguimiento_repository import ISeguimientoRepository
from app.application.ports.auditoria_repository import IAuditoriaRepository

class SincronizarDatosUseCase:
    def __init__(self, seguimiento_repo: ISeguimientoRepository, auditoria_repo: IAuditoriaRepository):
        self.seguimiento_repo = seguimiento_repo
        self.auditoria_repo = auditoria_repo

    def execute(self, tutor_id: int, actividades_pendientes: List[ActividadEjecutada]) -> List[ActividadEjecutada]:
        synced_activities = []
        for actividad in actividades_pendientes:
            actividad.synced_at = datetime.utcnow()
            saved = self.seguimiento_repo.save_actividad_ejecutada(actividad)
            synced_activities.append(saved)
            
            # Log de trazabilidad (auditoria)
            log = LogTrazabilidad(
                usuario_id=tutor_id,
                rol_usuario="padre_tutor",
                accion="SYNC_ACTIVIDAD_OFFLINE",
                entidad_afectada="ActividadEjecutada",
                entidad_id=saved.id or actividad.id or "N/A",
                payload_nuevo=saved.json(),
                timestamp_servidor=datetime.utcnow()
            )
            self.auditoria_repo.log_action(log)

        return synced_activities
