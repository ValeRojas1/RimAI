from typing import Optional
from app.application.ports.plan_repository import IPlanRepository
from app.domain.entities.plan_terapeutico import PlanTerapeutico

class PostgresPlanRepository(IPlanRepository):
    def __init__(self):
        self.planes = {}
        self.next_id = 1

    def save_plan(self, plan: PlanTerapeutico) -> PlanTerapeutico:
        if not plan.id:
            plan.id = self.next_id
            self.next_id += 1
        self.planes[plan.id] = plan.dict()
        return plan

    def get_plan_by_id(self, plan_id: int) -> Optional[PlanTerapeutico]:
        data = self.planes.get(plan_id)
        if data:
            return PlanTerapeutico(**data)
        return None
