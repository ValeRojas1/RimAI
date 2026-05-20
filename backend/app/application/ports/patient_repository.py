from abc import ABC, abstractmethod
from typing import List, Optional
from app.domain.entities.patient import Patient, ClinicalProfile, ExternalEvaluation

class IPatientRepository(ABC):
    @abstractmethod
    def create_patient(self, patient: Patient) -> Patient:
        pass

    @abstractmethod
    def create_clinical_profile(self, profile: ClinicalProfile) -> ClinicalProfile:
        pass

    @abstractmethod
    def save_external_evaluation(self, evaluation: ExternalEvaluation) -> ExternalEvaluation:
        pass

    @abstractmethod
    def get_patient_history(self, patient_id: int) -> dict:
        """ Returns clinical profiles and external evaluations """
        pass

    @abstractmethod
    def get_patients_by_tutor(self, tutor_id: int) -> List[Patient]:
        pass
