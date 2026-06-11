import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from typing import List

from app.domain.entities.actividad_ejecutada import ActividadEjecutada
from app.application.usecases.sincronizar_datos_usecase import SincronizarDatosUseCase
from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from app.application.usecases.generar_reporte_analitico_usecase import GenerarReporteAnaliticoUseCase
from app.adapters.inbound.api.reportes_controller import _get_reporte_impl
from .dependencies import (
    get_sincronizar_datos_usecase,
    get_current_user,
    get_evaluar_adherencia_usecase,
    get_generar_reporte_analitico_usecase,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/seguimiento", tags=["seguimiento"])

DEPRECATION_MSG = (
    "Este endpoint está deprecado. Use POST /api/sesiones para sincronizar "
    "ejecuciones de actividades desde la app familiar."
)


class SyncRequest(BaseModel):
    actividades: List[ActividadEjecutada]


@router.post("/sincronizar")
def sincronizar_actividades(
    response: Response,
    request: SyncRequest,
    sync_uc: SincronizarDatosUseCase = Depends(get_sincronizar_datos_usecase),
    current_user: dict = Depends(get_current_user),
):
    response.headers["Deprecation"] = "true"
    response.headers["Link"] = '</api/sesiones>; rel="successor-version"'

    if current_user.get("role") not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede sincronizar actividades")

    tutor_id = current_user.get("id")
    try:
        synced = sync_uc.execute(tutor_id, request.actividades)
        return {
            "status": "success",
            "synced_count": len(synced),
            "deprecation_notice": DEPRECATION_MSG,
            "canonical_endpoint": "POST /api/sesiones",
        }
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception:
        logger.exception("Error al sincronizar actividades vía /api/v1/seguimiento/sincronizar")
        raise HTTPException(
            status_code=500,
            detail="No se pudieron sincronizar las actividades. Intente nuevamente.",
        )


@router.get("/reportes/{patient_id}")
def get_reporte_legacy_alias(
    patient_id: int,
    inicio: datetime,
    fin: datetime,
    reporte_uc: GenerarReporteAnaliticoUseCase = Depends(get_generar_reporte_analitico_usecase),
    adherencia_uc: EvaluarAdherenciaUseCase = Depends(get_evaluar_adherencia_usecase),
    current_user: dict = Depends(get_current_user),
):
    """Alias legacy: /api/v1/seguimiento/reportes/{id} (MEJ-001)."""
    try:
        return _get_reporte_impl(
            patient_id, inicio, fin, reporte_uc, adherencia_uc, current_user
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except HTTPException:
        raise
    except Exception:
        logger.exception("Error en alias legacy de reporte para paciente %s", patient_id)
        raise HTTPException(
            status_code=500,
            detail="No se pudo generar el reporte analítico. Intente nuevamente.",
        )
