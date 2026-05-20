from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.application.usecases.therapist_usecases import TherapistUseCases
from .dependencies import get_therapist_use_cases, get_current_user

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])

class TherapistCreateRequest(BaseModel):
    nombre_completo: str
    email: str
    password: str
    especialidad: str
    numero_colegiatura: str

@router.post("/terapeutas")
def create_therapist(request: TherapistCreateRequest, current_user: dict = Depends(get_current_user), uc: TherapistUseCases = Depends(get_therapist_use_cases)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
    
    try:
        therapist = uc.register_therapist(
            email=request.email,
            password=request.password,
            nombre_completo=request.nombre_completo,
            especialidad=request.especialidad,
            numero_colegiatura=request.numero_colegiatura
        )
        return {"id": therapist.id, "email": therapist.email, "status": "created"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
