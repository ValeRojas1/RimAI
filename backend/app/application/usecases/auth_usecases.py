from typing import Optional
from passlib.context import CryptContext
from jose import jwt
from datetime import datetime, timedelta
from app.application.ports.user_repository import IUserRepository
from app.domain.entities.user import User
import os

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
SECRET_KEY = os.getenv("JWT_SECRET", "super-secret-key-rimai-2024")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7

class AuthUseCases:
    def __init__(self, user_repo: IUserRepository):
        self.user_repo = user_repo

    def authenticate_user(self, email: str, password: str) -> Optional[User]:
        user = self.user_repo.get_by_email(email)
        if not user:
            return None
        if not pwd_context.verify(password, user.hashed_password):
            return None
        return user

    def create_access_token(self, data: dict, expires_delta: Optional[timedelta] = None):
        to_encode = data.copy()
        if expires_delta:
            expire = datetime.utcnow() + expires_delta
        else:
            expire = datetime.utcnow() + timedelta(minutes=15)
        to_encode.update({"exp": expire})
        encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
        return encoded_jwt

    def login(self, email: str, password: str) -> dict:
        user = self.authenticate_user(email, password)
        if not user:
            raise ValueError("Credenciales incorrectas")
        
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = self.create_access_token(
            data={"sub": user.email, "role": user.role.value, "id": user.id},
            expires_delta=access_token_expires
        )
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user_id": user.id,
            "nombre": user.nombre_completo,
            "rol": user.role.value,
        }

    def register_family_user(self, nombre: str, email: str, password: str) -> dict:
        existing_user = self.user_repo.get_by_email(email)
        if existing_user:
            raise ValueError("El correo ya está registrado")

        hashed_password = pwd_context.hash(password)
        user = User(
            email=email,
            hashed_password=hashed_password,
            role="padre_tutor",
            nombre_completo=nombre,
        )
        created = self.user_repo.create_family_user(user)
        return self.login(created.email, password)
