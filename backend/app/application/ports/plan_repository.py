from abc import ABC, abstractmethod
from typing import Optional, List
from app.domain.entities.plan_terapeutico import PlanTerapeutico

class IPlanRepository(ABC):
    @abstractmethod
    def save_plan(self, plan: PlanTerapeutico) -> PlanTerapeutico:
        pass

    @abstractmethod
    def get_plan_by_id(self, plan_id: int) -> Optional[PlanTerapeutico]:
        pass
