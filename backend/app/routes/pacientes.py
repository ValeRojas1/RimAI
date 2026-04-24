from datetime import datetime, timedelta, date
from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.database import get_db
from app.models import Terapeuta, Nino, Sesion, PlanTerapeutico, Actividad, ResultadoActividad
from app.schemas import DashboardResumen, PacienteDashboard, UltimaSesionInfo, PerfilNino, PlanOut, ActividadOut
from app.auth import get_current_user
from app.models import Usuario

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


def _calcular_edad(fecha_nac: date) -> int:
    hoy = date.today()
    return hoy.year - fecha_nac.year - ((hoy.month, hoy.day) < (fecha_nac.month, fecha_nac.day))


@router.get("/resumen", response_model=DashboardResumen)
def get_resumen(
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Retorna las métricas del dashboard y lista de pacientes del terapeuta autenticado."""
    terapeuta = db.query(Terapeuta).filter(Terapeuta.usuario_id == current_user.id).first()
    if not terapeuta:
        raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

    # Niños activos del terapeuta
    ninos = db.query(Nino).filter(
        Nino.terapeuta_id == terapeuta.id,
        Nino.activo == True
    ).all()

    # Sesiones esta semana
    inicio_semana = datetime.utcnow() - timedelta(days=7)
    sesiones_semana = db.query(Sesion).join(Nino).filter(
        Nino.terapeuta_id == terapeuta.id,
        Sesion.fecha_inicio >= inicio_semana
    ).count()

    # Construir lista de pacientes
    pacientes_out: List[PacienteDashboard] = []
    alertas = 0

    for nino in ninos:
        # Plan activo
        plan = db.query(PlanTerapeutico).filter(
            PlanTerapeutico.nino_id == nino.id,
            PlanTerapeutico.activo == True
        ).first()

        # Última sesión
        ultima_sesion = db.query(Sesion).filter(
            Sesion.nino_id == nino.id
        ).order_by(Sesion.fecha_inicio.desc()).first()

        ultima_info = None
        if ultima_sesion:
            resultados = db.query(ResultadoActividad).filter(
                ResultadoActividad.sesion_id == ultima_sesion.id
            ).all()
            total_aciertos = sum(r.aciertos or 0 for r in resultados)
            total_reps = sum(r.repeticiones or 1 for r in resultados)
            tasa = round(total_aciertos / total_reps, 2) if total_reps > 0 else 0

            if tasa < 0.5:
                alertas += 1

            ultima_info = UltimaSesionInfo(
                fecha=ultima_sesion.fecha_inicio,
                tasa_aciertos=tasa,
                estado=ultima_sesion.estado.value,
            )

        perfil = nino.perfil_sensorial or {}
        intereses = perfil.get("intereses", [])

        pacientes_out.append(PacienteDashboard(
            id=str(nino.id),
            nombre=nino.nombre,
            edad=_calcular_edad(nino.fecha_nacimiento),
            nivel_cognitivo=nino.nivel_cognitivo.value,
            plan_activo=str(plan.id) if plan else None,
            ultima_sesion=ultima_info,
        ))

    return DashboardResumen(
        total_pacientes=len(ninos),
        sesiones_esta_semana=sesiones_semana,
        alertas_baja_adherencia=alertas,
        pacientes=pacientes_out,
    )


@router.get("/paciente/{nino_id}/perfil", response_model=PerfilNino)
def get_perfil_nino(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")

    return PerfilNino(
        id=str(nino.id),
        nombre=nino.nombre,
        fecha_nacimiento=nino.fecha_nacimiento,
        edad=_calcular_edad(nino.fecha_nacimiento),
        nivel_cognitivo=nino.nivel_cognitivo.value,
        perfil_sensorial=nino.perfil_sensorial,
        objetivos_intervencion=nino.objetivos_intervencion,
    )


@router.get("/paciente/{nino_id}/plan", response_model=PlanOut)
def get_plan_activo(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = db.query(PlanTerapeutico).filter(
        PlanTerapeutico.nino_id == nino_id,
        PlanTerapeutico.activo == True,
    ).first()

    if not plan:
        raise HTTPException(status_code=404, detail="No hay plan activo para este paciente")

    # Actividades del plan (via join manual porque la relación está en plan_actividades)
    from sqlalchemy import text
    result = db.execute(
        text("""
            SELECT a.* FROM actividades a
            JOIN plan_actividades pa ON pa.actividad_id = a.id
            WHERE pa.plan_id = :plan_id
            ORDER BY pa.orden
        """),
        {"plan_id": str(plan.id)}
    ).fetchall()

    actividades = [
        ActividadOut(
            id=str(row.id),
            nombre=row.nombre,
            tipo=row.tipo,
            instrucciones=row.instrucciones,
            nivel_dificultad=row.nivel_dificultad,
            duracion_estimada=row.duracion_estimada,
        )
        for row in result
    ]

    return PlanOut(
        id=str(plan.id),
        fecha_inicio=plan.fecha_inicio,
        nivel_dificultad_actual=plan.nivel_dificultad_actual.value,
        activo=plan.activo,
        actividades=actividades,
    )
