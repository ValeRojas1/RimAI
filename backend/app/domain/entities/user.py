from enum import Enum
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class RoleEnum(str, Enum):
    ADMIN = "admin"
    TERAPEUTA = "terapeuta"
    TUTOR = "padre_tutor"

class User(BaseModel):
    id: Optional[str] = None
    email: EmailStr
    hashed_password: str
    role: RoleEnum
    nombre_completo: str
    created_at: Optional[datetime] = None

class Therapist(User):
    especialidad: str = ""
    numero_colegiatura: str = ""
