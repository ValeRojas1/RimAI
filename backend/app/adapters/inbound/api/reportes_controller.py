import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException

from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from app.application.usecases.generar_reporte_analitico_usecase import GenerarReporteAnaliticoUseCase
from app.infrastructure.authorization import autorizar_acceso_nino
from .dependencies import (
    get_evaluar_adherencia_usecase,
    get_generar_reporte_analitico_usecase,
    get_current_user,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/reportes", tags=["reportes"])


def _get_reporte_impl(
    patient_id: int,
    inicio: datetime,
    fin: datetime,
    reporte_uc: GenerarReporteAnaliticoUseCase,
    adherencia_uc: EvaluarAdherenciaUseCase,
    current_user: dict,
):
    autorizar_acceso_nino(str(patient_id), current_user)
    reporte = reporte_uc.execute(patient_id, inicio, fin)

    if current_user.get("role") == "terapeuta":
        adherencia_uc.execute(
            patient_id, current_user.get("id"), reporte.tasa_adherencia_global, 0.7
        )

    return reporte


@router.get("/{patient_id}")
def get_reporte(
    patient_id: int,
    inicio: datetime,
    fin: datetime,
    reporte_uc: GenerarReporteAnaliticoUseCase = Depends(get_generar_reporte_analitico_usecase),
    adherencia_uc: EvaluarAdherenciaUseCase = Depends(get_evaluar_adherencia_usecase),
    current_user: dict = Depends(get_current_user),
):
    try:
        return _get_reporte_impl(
            patient_id, inicio, fin, reporte_uc, adherencia_uc, current_user
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except HTTPException:
        raise
    except Exception:
        logger.exception("Error al generar reporte analítico para paciente %s", patient_id)
        raise HTTPException(
            status_code=500,
            detail="No se pudo generar el reporte analítico. Intente nuevamente.",
        )
