from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from app.application.usecases.patient_usecases import PatientUseCases
from app.application.usecases.evaluation_usecases import EvaluationUseCases
from app.domain.entities.patient import Patient, ClinicalProfile, SourceEnum
from .dependencies import get_patient_use_cases, get_evaluation_use_cases, get_current_user

router = APIRouter(prefix="/api/v1/perfiles", tags=["perfiles"])

@router.post("/")
def create_patient(patient: Patient, uc: PatientUseCases = Depends(get_patient_use_cases), current_user: dict = Depends(get_current_user)):
    patient.tutor_id = current_user.get("id")
    return uc.register_patient(patient)

@router.post("/perfil-clinico")
def create_clinical_profile(profile: ClinicalProfile, uc: PatientUseCases = Depends(get_patient_use_cases), current_user: dict = Depends(get_current_user)):
    role = current_user.get("role")
    profile.source = SourceEnum.TERAPEUTA if role == "terapeuta" else SourceEnum.TUTOR
    return uc.register_clinical_profile(profile)

@router.post("/{patient_id}/evaluaciones")
def upload_evaluation(
    patient_id: int, 
    file: UploadFile = File(...),
    uc: EvaluationUseCases = Depends(get_evaluation_use_cases),
    current_user: dict = Depends(get_current_user)
):
    role = current_user.get("role")
    source = SourceEnum.TERAPEUTA if role == "terapeuta" else SourceEnum.TUTOR
    return uc.upload_evaluation(patient_id, source, file.file, file.filename, file.content_type)

@router.get("/{patient_id}/historial")
def get_patient_history(patient_id: int, uc: PatientUseCases = Depends(get_patient_use_cases), current_user: dict = Depends(get_current_user)):
    return uc.get_patient_history(patient_id)
