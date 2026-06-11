import json
from datetime import date, datetime
from typing import List, Union

from psycopg2.extras import Json, RealDictCursor

from app.application.ports.patient_repository import IPatientRepository
from app.domain.entities.patient import ClinicalProfile, ExternalEvaluation, Patient
from app.infrastructure.database import get_connection


class PostgresPatientRepository(IPatientRepository):
    """Persiste pacientes y perfiles en tablas ninos existentes."""

    def _resolve_tutor_pk(self, cur, tutor_ref: Union[int, str]) -> str:
        cur.execute(
            """
            SELECT id FROM padres_tutores
            WHERE usuario_id = %s OR id::text = %s
            LIMIT 1
            """,
            (str(tutor_ref), str(tutor_ref)),
        )
        row = cur.fetchone()
        if not row:
            raise ValueError("Tutor no encontrado")
        return str(row["id"])

    def create_patient(self, patient: Patient) -> Patient:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                tutor_pk = self._resolve_tutor_pk(cur, patient.tutor_id)
                cur.execute(
                    """
                    INSERT INTO ninos (
                        nombre, fecha_nacimiento, nivel_cognitivo,
                        diagnostico, tutor_id, activo
                    )
                    VALUES (%s, %s, 'Medio', %s, %s, TRUE)
                    RETURNING id, created_at
                    """,
                    (
                        patient.nombre,
                        date.today().replace(year=date.today().year - max(patient.edad, 1)),
                        patient.diagnostico_declarado,
                        tutor_pk,
                    ),
                )
                row = cur.fetchone()
                patient.id = str(row["id"])
                patient.created_at = row["created_at"]
        return patient

    def create_clinical_profile(self, profile: ClinicalProfile) -> ClinicalProfile:
        patient_id = str(profile.patient_id)
        perfil_clinico = {
            "antecedentes_clinicos": profile.antecedentes_clinicos,
            "escolaridad": profile.escolaridad,
            "perfil_sensorial_score": profile.perfil_sensorial_score,
            "contexto_familiar_score": profile.contexto_familiar_score,
            "preferencias": profile.preferencias,
            "medication": profile.medication.model_dump()
            if hasattr(profile.medication, "model_dump")
            else profile.medication.dict(),
            "calming_rituals": [
                r.model_dump() if hasattr(r, "model_dump") else r.dict()
                for r in profile.calming_rituals
            ],
            "source": profile.source.value,
            "created_at": datetime.utcnow().isoformat(),
        }

        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT perfil_sensorial FROM ninos WHERE id = %s",
                    (patient_id,),
                )
                row = cur.fetchone()
                if not row:
                    raise ValueError("Paciente no encontrado")
                perfil = row["perfil_sensorial"] or {}
                perfiles = perfil.get("perfiles_clinicos") or []
                perfiles.append(perfil_clinico)
                perfil["perfiles_clinicos"] = perfiles
                cur.execute(
                    "UPDATE ninos SET perfil_sensorial = %s::jsonb WHERE id = %s",
                    (Json(perfil), patient_id),
                )
                profile.id = len(perfiles)
                profile.created_at = datetime.utcnow()
        return profile

    def save_external_evaluation(self, evaluation: ExternalEvaluation) -> ExternalEvaluation:
        patient_id = str(evaluation.patient_id)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT perfil_sensorial FROM ninos WHERE id = %s",
                    (patient_id,),
                )
                row = cur.fetchone()
                if not row:
                    raise ValueError("Paciente no encontrado")
                perfil = row["perfil_sensorial"] or {}
                evals = perfil.get("evaluaciones_externas") or []
                entry = {
                    "file_url": evaluation.file_url,
                    "uploaded_by": evaluation.uploaded_by.value,
                    "created_at": datetime.utcnow().isoformat(),
                }
                evals.append(entry)
                perfil["evaluaciones_externas"] = evals
                cur.execute(
                    "UPDATE ninos SET perfil_sensorial = %s::jsonb WHERE id = %s",
                    (Json(perfil), patient_id),
                )
                evaluation.id = len(evals)
                evaluation.created_at = datetime.utcnow()
        return evaluation

    def get_patient_history(self, patient_id: Union[int, str]) -> dict:
        pid = str(patient_id)
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT perfil_sensorial FROM ninos WHERE id = %s",
                    (pid,),
                )
                row = cur.fetchone()
                if not row:
                    return {"profiles": [], "evaluations": []}
                perfil = row["perfil_sensorial"] or {}
                return {
                    "profiles": perfil.get("perfiles_clinicos") or [],
                    "evaluations": perfil.get("evaluaciones_externas") or [],
                }

    def get_patients_by_tutor(self, tutor_id: Union[int, str]) -> List[Patient]:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                tutor_pk = self._resolve_tutor_pk(cur, tutor_id)
                cur.execute(
                    """
                    SELECT id, nombre, fecha_nacimiento, diagnostico, created_at
                    FROM ninos
                    WHERE tutor_id = %s AND activo = TRUE
                    ORDER BY nombre
                    """,
                    (tutor_pk,),
                )
                rows = cur.fetchall()

        patients = []
        today = date.today()
        for row in rows:
            fn = row["fecha_nacimiento"]
            edad = today.year - fn.year - ((today.month, today.day) < (fn.month, fn.day))
            patients.append(
                Patient(
                    id=str(row["id"]),
                    nombre=row["nombre"],
                    edad=edad,
                    diagnostico_declarado=row["diagnostico"] or "",
                    tutor_id=str(tutor_id),
                    created_at=row["created_at"],
                )
            )
        return patients
