from fastapi import APIRouter, Depends
from pydantic import BaseModel
from app.application.usecases.ai_support_usecases import AISupportUseCases
from .dependencies import get_ai_support_use_cases, get_current_user

router = APIRouter(prefix="/api/v1/ai", tags=["ai"])

class AIRequest(BaseModel):
    edad: int
    diagnostico_declarado: str
    perfil_sensorial_score: int
    contexto_familiar_score: int

@router.post("/estimar-apoyo")
def estimate_support(request: AIRequest, uc: AISupportUseCases = Depends(get_ai_support_use_cases), current_user: dict = Depends(get_current_user)):
    # Ejecución rápida en < 100ms
    level = uc.estimate_support_level(
        request.edad,
        request.diagnostico_declarado,
        request.perfil_sensorial_score,
        request.contexto_familiar_score
    )
    return {"support_level": level.value}
