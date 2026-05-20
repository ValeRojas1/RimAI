from abc import ABC, abstractmethod
from typing import Optional
from app.domain.entities.cuestionario_scq import CuestionarioSCQ

class ISCQRepository(ABC):
    @abstractmethod
    def save_scq(self, scq: CuestionarioSCQ) -> CuestionarioSCQ:
        pass

    @abstractmethod
    def get_by_patient_id(self, patient_id: int) -> Optional[CuestionarioSCQ]:
        pass
