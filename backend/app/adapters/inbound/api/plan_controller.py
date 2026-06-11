from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any
from app.application.usecases.generar_plan_sugerido_usecase import GenerarPlanSugeridoUseCase
from app.domain.entities.plan_terapeutico import SugerenciaActividad
from app.infrastructure.authorization import verify_terapeuta_assigned_to_patient
from .dependencies import get_plan_use_cases, get_current_user

router = APIRouter(prefix="/api/v1/planes", tags=["planes"])

class GenerarPlanRequest(BaseModel):
    patient_id: int
    perfil_sensorial: Dict[str, Any]

class SugerenciaRequest(BaseModel):
    actividad_id: str
    nombre: str
    justificacion: str

class ValidarPlanRequest(BaseModel):
    modificaciones: List[SugerenciaRequest]

@router.post("/personalizar")
def personalizar_plan(request: GenerarPlanRequest, uc: GenerarPlanSugeridoUseCase = Depends(get_plan_use_cases), current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden personalizar planes.")
    if not verify_terapeuta_assigned_to_patient(str(request.patient_id), str(current_user.get("id"))):
        raise HTTPException(status_code=403, detail="Acceso denegado al paciente")
    terapeuta_id = current_user.get("id")
    plan = uc.execute(request.patient_id, terapeuta_id, request.perfil_sensorial)
    return plan

@router.put("/{plan_id}/validar")
def validar_plan(plan_id: int, request: ValidarPlanRequest, uc: GenerarPlanSugeridoUseCase = Depends(get_plan_use_cases), current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden validar planes.")
    
    modificaciones = [
        SugerenciaActividad(
            actividad_id=s.actividad_id,
            nombre=s.nombre,
            justificacion=s.justificacion
        ) for s in request.modificaciones
    ]
    
    try:
        plan_validado = uc.validar_plan(plan_id, modificaciones)
        return plan_validado
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
