from fastapi import APIRouter, Depends, HTTPException
from datetime import datetime
from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from app.application.usecases.generar_reporte_analitico_usecase import GenerarReporteAnaliticoUseCase
from .dependencies import get_evaluar_adherencia_usecase, get_generar_reporte_analitico_usecase, get_current_user

router = APIRouter(prefix="/api/v1/reportes", tags=["reportes"])

@router.get("/{patient_id}")
def get_reporte(
    patient_id: int,
    inicio: datetime,
    fin: datetime,
    reporte_uc: GenerarReporteAnaliticoUseCase = Depends(get_generar_reporte_analitico_usecase),
    adherencia_uc: EvaluarAdherenciaUseCase = Depends(get_evaluar_adherencia_usecase),
    current_user: dict = Depends(get_current_user)
):
    try:
        # Generar reporte 95% fidelidad basado en BD centralizada
        reporte = reporte_uc.execute(patient_id, inicio, fin)
        
        # Evaluar adherencia silenciosamente y grabar alertas si corresponde
        # (El terapeuta verá la alerta si baja del 70%)
        terapeuta_id = current_user.get("id") # Asumiendo acceso de terapeuta
        if current_user.get("role") == "terapeuta":
            adherencia_uc.execute(patient_id, terapeuta_id, reporte.tasa_adherencia_global, 0.7)
            
        return reporte
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
