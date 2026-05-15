import os
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
import bcrypt
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Usuario, PadreTutor
from app.schemas import LoginRequest, TokenResponse, RegisterRequest

# ── Config ────────────────────────────────────────────────────────────────────
SECRET_KEY = os.getenv("JWT_SECRET", "rimai-super-secret-key-2026-change-in-prod")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 horas

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

router = APIRouter(prefix="/api/auth", tags=["auth"])


# ── Helpers ───────────────────────────────────────────────────────────────────

def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode('utf-8'), hashed.encode('utf-8'))
    except Exception:
        return False


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> Usuario:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Token inválido o expirado",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(Usuario).filter(Usuario.id == user_id).first()
    if not user or not user.activo:
        raise credentials_exception
    return user


def get_current_admin(current_user: Usuario = Depends(get_current_user)) -> Usuario:
    if current_user.rol.value != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Se requieren permisos de administrador",
        )
    return current_user


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/register", response_model=TokenResponse)
def register(request: RegisterRequest, db: Session = Depends(get_db)):
    """Registra un nuevo usuario y retorna un JWT."""
    user_exists = db.query(Usuario).filter(Usuario.email == request.email).first()
    if user_exists:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo ya está registrado",
        )
    
    salt = bcrypt.gensalt()
    hashed_password = bcrypt.hashpw(request.password.encode('utf-8'), salt).decode('utf-8')
    
    nuevo_usuario = Usuario(
        nombre=request.nombre,
        email=request.email,
        password_hash=hashed_password,
        rol="padre_tutor",
        activo=True
    )
    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)
    
    nuevo_tutor = PadreTutor(
        usuario_id=nuevo_usuario.id
    )
    db.add(nuevo_tutor)
    db.commit()

    token = create_access_token({
        "sub": str(nuevo_usuario.id),
        "user_id": str(nuevo_usuario.id),
        "rol": nuevo_usuario.rol.value,
        "nombre": nuevo_usuario.nombre,
    })
    return TokenResponse(
        access_token=token,
        user_id=str(nuevo_usuario.id),
        nombre=nuevo_usuario.nombre,
        rol=nuevo_usuario.rol.value,
    )

@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    """Valida credenciales y retorna un JWT."""
    user = db.query(Usuario).filter(Usuario.email == request.email).first()

    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email o contraseña incorrectos",
        )
    if not user.activo:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cuenta inactiva. Contacta al administrador.",
        )

    token = create_access_token({
        "sub": str(user.id),
        "user_id": str(user.id),
        "rol": user.rol.value,
        "nombre": user.nombre,
    })
    return TokenResponse(
        access_token=token,
        user_id=str(user.id),
        nombre=user.nombre,
        rol=user.rol.value,
    )


@router.get("/me")
def get_me(current_user: Usuario = Depends(get_current_user)):
    return {"id": str(current_user.id), "nombre": current_user.nombre, "rol": current_user.rol.value}
