import os
from datetime import datetime

import psycopg2
from psycopg2.extras import Json, RealDictCursor
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import List
from .dependencies import get_current_user

router = APIRouter(prefix="/api/v1/admision", tags=["admision"])

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
)


def _conn():
    return psycopg2.connect(DATABASE_URL)


class SCQRequest(BaseModel):
    patient_id: str
    respuestas: List[int]
    acepto_disclaimer: bool


def _score_scq(respuestas: List[int]) -> tuple[int, str]:
    if len(respuestas) != 40:
        raise ValueError("Debe responder exactamente las 40 preguntas del cuestionario SCQ.")
    if not all(r in (0, 1) for r in respuestas):
        raise ValueError("Las respuestas del SCQ deben ser 0 o 1.")

    # Pregunta 1 (índice 0) es la pregunta filtro (gateway) y no se suma al puntaje
    habla_frases = respuestas[0] == 1

    # Preguntas que suman 1 punto si la respuesta es 'No' (valor 0)
    # 1-based: Q2, Q9, Q19, Q20 a Q40
    # 0-based indices: 1, 8, 18, y 19 a 39
    indices_no_scores_1 = {1, 8} | set(range(18, 40))

    # Preguntas que suman 1 punto si la respuesta es 'Sí' (valor 1)
    # 1-based: Q3 a Q8, Q10 a Q18
    # 0-based indices: 2 a 7, 9 a 17
    indices_yes_scores_1 = set(range(2, 8)) | set(range(9, 18))

    puntaje_total = 0
    for i in range(1, 40):
        # Si el niño no habla con frases cortas (Q1 = No), se omiten las preguntas 2 a 7 (índices 1 a 6)
        if not habla_frases and 1 <= i <= 6:
            continue

        val = respuestas[i]
        if i in indices_no_scores_1:
            if val == 0:
                puntaje_total += 1
        elif i in indices_yes_scores_1:
            if val == 1:
                puntaje_total += 1

    if puntaje_total >= 15:
        return puntaje_total, "Alto"
    if puntaje_total >= 11:
        return puntaje_total, "Moderado"
    return puntaje_total, "Bajo"


def _submit_scq_impl(request: SCQRequest, current_user: dict):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede responder el SCQ")
    if not request.acepto_disclaimer:
        raise HTTPException(
            status_code=400,
            detail="Debe aceptar el aviso legal (RNF-10) antes de enviar el cuestionario.",
        )

    try:
        puntaje_total, nivel_indicio = _score_scq(request.respuestas)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT n.id, n.perfil_sensorial
                FROM ninos n
                JOIN padres_tutores pt ON pt.id = n.tutor_id
                WHERE n.id = %s
                  AND pt.usuario_id = %s
                  AND n.activo = TRUE
                """,
                (request.patient_id, current_user["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil = nino["perfil_sensorial"] or {}
            triaje = perfil.get("triaje") or {}
            triaje.update(
                {
                    "requiere_scq": True,
                    "scq_completado": True,
                    "autorizado_envio_terapeuta": False,
                    "scq": {
                        "puntaje_total": puntaje_total,
                        "nivel_indicio": nivel_indicio,
                        "respuestas": request.respuestas,
                        "acepto_disclaimer": request.acepto_disclaimer,
                        "fecha": datetime.utcnow().isoformat(),
                        "uso_no_diagnostico": True,
                    },
                }
            )
            perfil["triaje"] = triaje

            cur.execute(
                """
                UPDATE ninos
                SET perfil_sensorial = %s::jsonb
                WHERE id = %s
                """,
                (Json(perfil), request.patient_id),
            )

    return {
        "id": None,
        "patient_id": request.patient_id,
        "puntaje_total": puntaje_total,
        "nivel_indicio": nivel_indicio,
        "enviado_terapeuta": False,
    }


@router.post("/")
def submit_scq(
    request: SCQRequest,
    current_user: dict = Depends(get_current_user),
):
    return _submit_scq_impl(request, current_user)


@router.post("/scq")
def submit_scq_compat(
    request: SCQRequest,
    current_user: dict = Depends(get_current_user),
):
    return _submit_scq_impl(request, current_user)


@router.post("/{patient_id}/enviar-terapeuta")
def enviar_a_terapeuta(
    patient_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede enviar el caso")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT n.id, n.perfil_sensorial
                FROM ninos n
                JOIN padres_tutores pt ON pt.id = n.tutor_id
                WHERE n.id = %s
                  AND pt.usuario_id = %s
                  AND n.activo = TRUE
                """,
                (patient_id, current_user["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil = nino["perfil_sensorial"] or {}
            triaje = perfil.get("triaje") or {}
            if triaje.get("requiere_scq") and not triaje.get("scq_completado"):
                raise HTTPException(
                    status_code=400,
                    detail="Debe completar el SCQ antes de enviar el caso al terapeuta.",
                )

            triaje["autorizado_envio_terapeuta"] = True
            triaje["fecha_autorizacion_envio"] = datetime.utcnow().isoformat()
            perfil["triaje"] = triaje

            cur.execute(
                """
                UPDATE ninos
                SET perfil_sensorial = %s::jsonb,
                    estado_clinico = 'pendiente_asignacion'
                WHERE id = %s
                """,
                (Json(perfil), patient_id),
            )

        return {
            "ok": True,
            "patient_id": patient_id,
            "mensaje": "Caso enviado a la bandeja de terapeutas.",
        }
