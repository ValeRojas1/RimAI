from app.application.ports.patient_repository import IPatientRepository
from app.domain.entities.patient import Patient, ClinicalProfile

class PatientUseCases:
    def __init__(self, patient_repo: IPatientRepository):
        self.patient_repo = patient_repo

    def register_patient(self, patient: Patient) -> Patient:
        return self.patient_repo.create_patient(patient)

    def register_clinical_profile(self, profile: ClinicalProfile) -> ClinicalProfile:
        return self.patient_repo.create_clinical_profile(profile)

    def get_patient_history(self, patient_id: int) -> dict:
        return self.patient_repo.get_patient_history(patient_id)
