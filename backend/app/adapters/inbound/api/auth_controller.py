from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from app.application.usecases.auth_usecases import AuthUseCases
from .dependencies import get_auth_use_cases, get_current_user, get_user_repository

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

class LoginRequest(BaseModel):
    email: str
    password: str

class RegisterRequest(BaseModel):
    nombre: str
    email: str
    password: str

@router.post("/login")
def login(request: LoginRequest, auth_uc: AuthUseCases = Depends(get_auth_use_cases)):
    try:
        return auth_uc.login(request.email, request.password)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )

@router.post("/register")
def register(request: RegisterRequest, auth_uc: AuthUseCases = Depends(get_auth_use_cases)):
    try:
        return auth_uc.register_family_user(request.nombre, request.email, request.password)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

@router.get("/me")
def me(
    current_user: dict = Depends(get_current_user),
    user_repo = Depends(get_user_repository),
):
    user = user_repo.get_by_id(current_user["id"])
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario no encontrado",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return {
        "id": user.id,
        "nombre": user.nombre_completo,
        "email": user.email,
        "rol": user.role.value,
    }
