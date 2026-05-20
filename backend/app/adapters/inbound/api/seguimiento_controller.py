from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List
from datetime import datetime
from app.domain.entities.actividad_ejecutada import ActividadEjecutada
from app.application.usecases.sincronizar_datos_usecase import SincronizarDatosUseCase
from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from .dependencies import get_sincronizar_datos_usecase, get_current_user

router = APIRouter(prefix="/api/v1/seguimiento", tags=["seguimiento"])

class SyncRequest(BaseModel):
    actividades: List[ActividadEjecutada]

@router.post("/sincronizar")
def sincronizar_actividades(
    request: SyncRequest,
    sync_uc: SincronizarDatosUseCase = Depends(get_sincronizar_datos_usecase),
    current_user: dict = Depends(get_current_user)
):
    # En FastAPI, la auth valida el token
    tutor_id = current_user.get("id")
    try:
        synced = sync_uc.execute(tutor_id, request.actividades)
        return {"status": "success", "synced_count": len(synced)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


