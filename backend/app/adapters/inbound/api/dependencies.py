from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
import os
from typing import Optional

# Implementaciones a inyectar (que crearemos en outbound)
from app.adapters.outbound.database.postgres_user_repository import PostgresUserRepository
from app.adapters.outbound.database.postgres_patient_repository import PostgresPatientRepository
from app.adapters.outbound.storage.cloud_storage_adapter import CloudStorageAdapter

from app.application.usecases.auth_usecases import AuthUseCases
from app.application.usecases.therapist_usecases import TherapistUseCases
from app.application.usecases.patient_usecases import PatientUseCases
from app.application.usecases.ai_support_usecases import AISupportUseCases
from app.application.usecases.evaluation_usecases import EvaluationUseCases
from app.application.usecases.evaluar_cuestionario_scq_usecase import EvaluarCuestionarioSCQUseCase
from app.application.usecases.generar_plan_sugerido_usecase import GenerarPlanSugeridoUseCase
from app.application.usecases.sincronizar_datos_usecase import SincronizarDatosUseCase
from app.application.usecases.evaluar_adherencia_usecase import EvaluarAdherenciaUseCase
from app.application.usecases.generar_reporte_analitico_usecase import GenerarReporteAnaliticoUseCase

from app.adapters.outbound.database.postgres_scq_repository import PostgresSCQRepository
from app.adapters.outbound.database.postgres_plan_repository import PostgresPlanRepository
from app.adapters.outbound.database.postgres_seguimiento_repository import PostgresSeguimientoRepository
from app.adapters.outbound.database.postgres_auditoria_repository import PostgresAuditoriaRepository
from app.adapters.outbound.database.postgres_reportes_repository import PostgresReportesRepository

SECRET_KEY = os.getenv("JWT_SECRET", "super-secret-key-rimai-2024")
ALGORITHM = "HS256"

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

def get_current_user(token: str = Depends(oauth2_scheme)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("id")
        role = payload.get("role")
        if user_id is None or role is None:
            raise HTTPException(status_code=401, detail="Token inválido")
        return {"id": user_id, "role": role}
    except JWTError:
        raise HTTPException(status_code=401, detail="Token inválido")

# Dependency injection
def get_user_repository():
    return PostgresUserRepository()

def get_patient_repository():
    return PostgresPatientRepository()

def get_file_storage():
    return CloudStorageAdapter()

def get_auth_use_cases(repo = Depends(get_user_repository)):
    return AuthUseCases(repo)

def get_therapist_use_cases(repo = Depends(get_user_repository)):
    return TherapistUseCases(repo)

def get_patient_use_cases(repo = Depends(get_patient_repository)):
    return PatientUseCases(repo)

def get_ai_support_use_cases():
    return AISupportUseCases()

def get_evaluation_use_cases(repo = Depends(get_patient_repository), storage = Depends(get_file_storage)):
    return EvaluationUseCases(repo, storage)

def get_scq_repository():
    return PostgresSCQRepository()

def get_plan_repository():
    return PostgresPlanRepository()

def get_scq_use_cases(repo = Depends(get_scq_repository)):
    return EvaluarCuestionarioSCQUseCase(repo)

def get_plan_use_cases(repo = Depends(get_plan_repository)):
    return GenerarPlanSugeridoUseCase(repo)

def get_seguimiento_repository():
    return PostgresSeguimientoRepository()

def get_auditoria_repository():
    return PostgresAuditoriaRepository()

def get_reportes_repository():
    return PostgresReportesRepository()

def get_sincronizar_datos_usecase(
    seg_repo = Depends(get_seguimiento_repository),
    aud_repo = Depends(get_auditoria_repository)
):
    return SincronizarDatosUseCase(seg_repo, aud_repo)

def get_evaluar_adherencia_usecase(repo = Depends(get_reportes_repository)):
    return EvaluarAdherenciaUseCase(repo)

def get_generar_reporte_analitico_usecase(repo = Depends(get_seguimiento_repository)):
    return GenerarReporteAnaliticoUseCase(repo)
