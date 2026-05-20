from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List
from app.application.usecases.evaluar_cuestionario_scq_usecase import EvaluarCuestionarioSCQUseCase
from .dependencies import get_scq_use_cases, get_current_user

router = APIRouter(prefix="/api/v1/admision", tags=["admision"])

class SCQRequest(BaseModel):
    patient_id: int
    respuestas: List[int]
    acepto_disclaimer: bool

@router.post("/")
def submit_scq(request: SCQRequest, uc: EvaluarCuestionarioSCQUseCase = Depends(get_scq_use_cases), current_user: dict = Depends(get_current_user)):
    tutor_id = current_user.get("id")
    try:
        scq = uc.execute(
            patient_id=request.patient_id,
            tutor_id=tutor_id,
            respuestas=request.respuestas,
            acepto_disclaimer=request.acepto_disclaimer
        )
        return {
            "id": scq.id,
            "puntaje_total": scq.puntaje_total,
            "nivel_indicio": scq.nivel_indicio.value
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
