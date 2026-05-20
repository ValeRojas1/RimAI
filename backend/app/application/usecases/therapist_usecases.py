from app.application.ports.user_repository import IUserRepository
from app.domain.entities.user import Therapist, RoleEnum
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class TherapistUseCases:
    def __init__(self, user_repo: IUserRepository):
        self.user_repo = user_repo

    def register_therapist(self, email: str, password: str, nombre_completo: str, especialidad: str, numero_colegiatura: str) -> Therapist:
        existing_user = self.user_repo.get_by_email(email)
        if existing_user:
            raise ValueError("El correo ya está registrado")

        hashed_password = pwd_context.hash(password)
        therapist = Therapist(
            email=email,
            hashed_password=hashed_password,
            role=RoleEnum.TERAPEUTA,
            nombre_completo=nombre_completo,
            especialidad=especialidad,
            numero_colegiatura=numero_colegiatura
        )
        return self.user_repo.create_therapist(therapist)
