from abc import ABC, abstractmethod
from typing import Optional
from app.domain.entities.cuestionario_scq import CuestionarioSCQ

class ISCQRepository(ABC):
    @abstractmethod
    def save_scq(self, scq: CuestionarioSCQ) -> CuestionarioSCQ:
        pass

    @abstractmethod
    def get_by_patient_id(self, patient_id) -> Optional[CuestionarioSCQ]:
        pass

    @abstractmethod
    def verify_tutor_owns_patient(self, patient_id: str, tutor_user_id: str) -> bool:
        pass

    @abstractmethod
    def authorize_send_to_therapist(self, patient_id: str, tutor_user_id: str) -> None:
        pass
