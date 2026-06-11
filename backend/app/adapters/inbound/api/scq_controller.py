from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from typing import List

from app.application.usecases.evaluar_cuestionario_scq_usecase import EvaluarCuestionarioSCQUseCase
from app.application.ports.scq_repository import ISCQRepository
from .dependencies import get_current_user, get_scq_use_cases, get_scq_repository

router = APIRouter(prefix="/api/v1/admision", tags=["admision"])


class SCQRequest(BaseModel):
    patient_id: str
    respuestas: List[int]
    acepto_disclaimer: bool


def _submit_scq_impl(
    request: SCQRequest,
    current_user: dict,
    uc: EvaluarCuestionarioSCQUseCase,
    scq_repo: ISCQRepository,
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede responder el SCQ")
    if not request.acepto_disclaimer:
        raise HTTPException(
            status_code=400,
            detail="Debe aceptar el aviso legal (RNF-10) antes de enviar el cuestionario.",
        )
    if not scq_repo.verify_tutor_owns_patient(request.patient_id, current_user["id"]):
        raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

    try:
        scq = uc.execute(
            request.patient_id,
            current_user["id"],
            request.respuestas,
            request.acepto_disclaimer,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    nivel_str = scq.nivel_indicio.value if scq.nivel_indicio else "Bajo"
    return {
        "id": scq.id,
        "patient_id": request.patient_id,
        "puntaje_total": scq.puntaje_total,
        "nivel_indicio": nivel_str,
        "enviado_terapeuta": False,
    }


@router.post("/")
def submit_scq(
    request: SCQRequest,
    current_user: dict = Depends(get_current_user),
    uc: EvaluarCuestionarioSCQUseCase = Depends(get_scq_use_cases),
    scq_repo: ISCQRepository = Depends(get_scq_repository),
):
    return _submit_scq_impl(request, current_user, uc, scq_repo)


@router.post("/scq")
def submit_scq_compat(
    request: SCQRequest,
    current_user: dict = Depends(get_current_user),
    uc: EvaluarCuestionarioSCQUseCase = Depends(get_scq_use_cases),
    scq_repo: ISCQRepository = Depends(get_scq_repository),
):
    return _submit_scq_impl(request, current_user, uc, scq_repo)


@router.post("/{patient_id}/enviar-terapeuta")
def enviar_a_terapeuta(
    patient_id: str,
    current_user: dict = Depends(get_current_user),
    scq_repo: ISCQRepository = Depends(get_scq_repository),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede enviar el caso")

    repo = scq_repo
    try:
        repo.authorize_send_to_therapist(patient_id, current_user["id"])
    except ValueError as exc:
        msg = str(exc)
        if "completar el SCQ" in msg:
            raise HTTPException(status_code=400, detail=msg)
        raise HTTPException(status_code=404, detail=msg)

    return {
        "ok": True,
        "patient_id": patient_id,
        "mensaje": "Caso enviado a la bandeja de terapeutas.",
    }
