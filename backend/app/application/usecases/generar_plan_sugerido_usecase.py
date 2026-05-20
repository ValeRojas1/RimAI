from typing import List
from app.domain.entities.plan_terapeutico import PlanTerapeutico, SugerenciaActividad, EstadoPlan
from app.application.ports.plan_repository import IPlanRepository

class GenerarPlanSugeridoUseCase:
    def __init__(self, plan_repo: IPlanRepository):
        self.plan_repo = plan_repo

    def execute(self, patient_id: int, terapeuta_id: int, perfil_sensorial: dict) -> PlanTerapeutico:
        sugerencias = []
        
        # Lógica heurística: Si hay hiperreactividad auditiva, se omiten actividades ruidosas
        # (Esto es un mock para PMV2 como solicitó el usuario)
        umbral = perfil_sensorial.get("umbralSensorial", "medio").lower()
        aversiones = perfil_sensorial.get("estimulosAversivos", {})
        
        if "ruidos fuertes" in aversiones.get("RUIDO", []):
            sugerencias.append(
                SugerenciaActividad(
                    actividad_id="ACT-001",
                    nombre="Calibración con luces tenues (Silenciosa)",
                    justificacion="Adaptado por aversión detectada a ruidos fuertes."
                )
            )
        else:
            sugerencias.append(
                SugerenciaActividad(
                    actividad_id="ACT-002",
                    nombre="Interacción musical rítmica",
                    justificacion="No se detectó hiperreactividad auditiva."
                )
            )
            
        sugerencias.append(
            SugerenciaActividad(
                actividad_id="ACT-003",
                nombre="Juego de turnos estructurado",
                justificacion="Actividad estándar para desarrollo de comunicación social."
            )
        )

        plan = PlanTerapeutico(
            patient_id=patient_id,
            terapeuta_id=terapeuta_id,
            estado=EstadoPlan.BORRADOR,
            sugerencias=sugerencias
        )

        return self.plan_repo.save_plan(plan)

    def validar_plan(self, plan_id: int, modificaciones: List[SugerenciaActividad]) -> PlanTerapeutico:
        plan = self.plan_repo.get_plan_by_id(plan_id)
        if not plan:
            raise ValueError("Plan no encontrado")
        
        # El terapeuta reemplaza las sugerencias por su lista validada
        plan.sugerencias = modificaciones
        plan.estado = EstadoPlan.VALIDADO
        return self.plan_repo.save_plan(plan)
