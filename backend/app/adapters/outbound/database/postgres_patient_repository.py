from typing import List
from app.application.ports.patient_repository import IPatientRepository
from app.domain.entities.patient import Patient, ClinicalProfile, ExternalEvaluation

class PostgresPatientRepository(IPatientRepository):
    def __init__(self):
        # Mock storage
        self.patients = {}
        self.profiles = {}
        self.evaluations = {}
        self.next_p_id = 1
        self.next_pr_id = 1
        self.next_e_id = 1

    def create_patient(self, patient: Patient) -> Patient:
        patient.id = self.next_p_id
        self.next_p_id += 1
        self.patients[patient.id] = patient.dict()
        return patient

    def create_clinical_profile(self, profile: ClinicalProfile) -> ClinicalProfile:
        profile.id = self.next_pr_id
        self.next_pr_id += 1
        # El source inalterable ya viene en profile.source
        self.profiles[profile.id] = profile.dict()
        return profile

    def save_external_evaluation(self, evaluation: ExternalEvaluation) -> ExternalEvaluation:
        evaluation.id = self.next_e_id
        self.next_e_id += 1
        self.evaluations[evaluation.id] = evaluation.dict()
        return evaluation

    def get_patient_history(self, patient_id: int) -> dict:
        pr = [p for p in self.profiles.values() if p["patient_id"] == patient_id]
        ev = [e for e in self.evaluations.values() if e["patient_id"] == patient_id]
        return {
            "profiles": pr,
            "evaluations": ev
        }

    def get_patients_by_tutor(self, tutor_id: int) -> List[Patient]:
        return [Patient(**p) for p in self.patients.values() if p["tutor_id"] == tutor_id]
