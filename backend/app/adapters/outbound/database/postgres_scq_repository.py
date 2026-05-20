from typing import Optional
from app.application.ports.scq_repository import ISCQRepository
from app.domain.entities.cuestionario_scq import CuestionarioSCQ

class PostgresSCQRepository(ISCQRepository):
    def __init__(self):
        # Mock in-memory PMV2
        self.scqs = {}
        self.next_id = 1

    def save_scq(self, scq: CuestionarioSCQ) -> CuestionarioSCQ:
        scq.id = self.next_id
        self.next_id += 1
        self.scqs[scq.patient_id] = scq.dict()
        return scq

    def get_by_patient_id(self, patient_id: int) -> Optional[CuestionarioSCQ]:
        data = self.scqs.get(patient_id)
        if data:
            return CuestionarioSCQ(**data)
        return None
