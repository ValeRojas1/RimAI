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


@router.get("/familia/resumen", response_model=DashboardResumen)
def get_resumen_familia(
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Retorna los datos del niño(s) para el dashboard familiar."""
    from app.models import PadreTutor
    padre = db.query(PadreTutor).filter(PadreTutor.usuario_id == current_user.id).first()
    if not padre:
        raise HTTPException(status_code=404, detail="Perfil de familiar no encontrado")

    # Niños vinculados a este tutor
    ninos = db.query(Nino).filter(
        Nino.tutor_id == padre.id,
        Nino.activo == True
    ).all()

    pacientes_out: List[PacienteDashboard] = []
    
    for nino in ninos:
        plan = db.query(PlanTerapeutico).filter(
            PlanTerapeutico.nino_id == nino.id,
            PlanTerapeutico.activo == True
        ).first()

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

            ultima_info = UltimaSesionInfo(
                fecha=ultima_sesion.fecha_inicio,
                tasa_aciertos=tasa,
                estado=ultima_sesion.estado.value,
            )

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
        sesiones_esta_semana=0, # Simplificado para familiares
        alertas_baja_adherencia=0,
        pacientes=pacientes_out,
    )


from app.schemas import CrearNinoFamiliarRequest

@router.post("/familia/paciente", response_model=PerfilNino)
def guardar_perfil_nino_familiar(
    request: CrearNinoFamiliarRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Permite a un familiar registrar o actualizar el perfil de su hijo."""
    from app.models import PadreTutor, NivelCognitivo
    padre = db.query(PadreTutor).filter(PadreTutor.usuario_id == current_user.id).first()
    if not padre:
        raise HTTPException(status_code=404, detail="Perfil de familiar no encontrado")

    # Buscar si ya tiene un niño registrado (MVP: asumimos un niño por familiar de momento)
    nino = db.query(Nino).filter(Nino.tutor_id == padre.id).first()
    
    perfil_sensorial_ml = {
        "hitos": request.hitos.dict(),
        "sensorial": request.sensorial.dict()
    }

    if nino:
        nino.nombre = request.nombre
        nino.fecha_nacimiento = request.fecha_nacimiento
        nino.perfil_sensorial = perfil_sensorial_ml
    else:
        nino = Nino(
            nombre=request.nombre,
            fecha_nacimiento=request.fecha_nacimiento,
            nivel_cognitivo=NivelCognitivo.Medio,
            perfil_sensorial=perfil_sensorial_ml,
            tutor_id=padre.id,
            terapeuta_id=None
        )
        db.add(nino)
    
    db.commit()
    db.refresh(nino)

    return PerfilNino(
        id=str(nino.id),
        nombre=nino.nombre,
        fecha_nacimiento=nino.fecha_nacimiento,
        edad=_calcular_edad(nino.fecha_nacimiento),
        nivel_cognitivo=nino.nivel_cognitivo.value,
        perfil_sensorial=nino.perfil_sensorial,
        objetivos_intervencion=nino.objetivos_intervencion,
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

from app.ai.motor import motor_adaptativo
from pydantic import BaseModel

class GenerarPlanResponse(BaseModel):
    plan_id: str
    dificultad_inicial: str
    confianza_ia: float
    mensaje: str

@router.post("/paciente/{nino_id}/plan/generar", response_model=GenerarPlanResponse)
def generar_plan_terapeutico(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Genera un nuevo plan terapéutico utilizando IA (Random Forest) para estimar la dificultad.
    """
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
        
    if nino.terapeuta_id is None:
        raise HTTPException(status_code=400, detail="El paciente no tiene un terapeuta asignado")
        
    # Desactivar planes anteriores
    planes_viejos = db.query(PlanTerapeutico).filter(
        PlanTerapeutico.nino_id == nino.id, 
        PlanTerapeutico.activo == True
    ).all()
    for p in planes_viejos:
        p.activo = False
        
    # Preparar datos para IA
    nino_data = {
        'fecha_nacimiento': nino.fecha_nacimiento,
        'nivel_cognitivo': nino.nivel_cognitivo.value if nino.nivel_cognitivo else 'Medio',
        'perfil_sensorial': nino.perfil_sensorial or {},
        'objetivos_intervencion': nino.objetivos_intervencion or []
    }
    
    import time
    start_time = time.time()
    
    # Inferencia IA
    dificultad, confianza = motor_adaptativo.predecir_dificultad(nino_data)
    
    # El Criterio 2 exige < 100ms. Imprimimos para debug
    elapsed = (time.time() - start_time) * 1000
    print(f"IA Inference Time: {elapsed:.2f} ms")
    
    from app.models import NivelDificultad
    
    # Mapeo de string a Enum
    map_enum = {
        'Básico': NivelDificultad.Bajo,
        'Intermedio': NivelDificultad.Medio,
        'Avanzado': NivelDificultad.Alto
    }
    
    dificultad_enum = map_enum.get(dificultad, NivelDificultad.Medio)
    
    # Crear nuevo plan
    nuevo_plan = PlanTerapeutico(
        nino_id=nino.id,
        terapeuta_id=nino.terapeuta_id,
        fecha_inicio=date.today(),
        nivel_dificultad_actual=dificultad_enum,
        activo=True
    )
    db.add(nuevo_plan)
    db.flush() # Para obtener el ID
    
    # Seleccionar actividades sugeridas (Trazabilidad)
    # Buscamos actividades que coincidan con la dificultad
    actividades = db.query(Actividad).filter(Actividad.nivel_dificultad == dificultad_enum).limit(3).all()
    
    # Si no hay actividades en DB (por estar vacía), no rompemos
    if actividades:
        # Aquí crearíamos la relación en plan_actividades
        # Por ahora, usamos SQL crudo ya que SQLAlchemy no mapeó plan_actividades directamente como entidad
        from sqlalchemy import text
        for i, act in enumerate(actividades):
            db.execute(
                text("INSERT INTO plan_actividades (plan_id, actividad_id, orden) VALUES (:pid, :aid, :ord)"),
                {"pid": str(nuevo_plan.id), "aid": str(act.id), "ord": i+1}
            )
            
    db.commit()
    
    return GenerarPlanResponse(
        plan_id=str(nuevo_plan.id),
        dificultad_inicial=dificultad,
        confianza_ia=confianza,
        mensaje="Plan generado exitosamente con IA"
    )

from app.schemas import VincularPacienteRequest

@router.post("/terapeuta/vincular-paciente")
def vincular_paciente(
    data: VincularPacienteRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if current_user.rol.value != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular pacientes")
        
    terapeuta = db.query(Terapeuta).filter(Terapeuta.usuario_id == current_user.id).first()
    if not terapeuta:
        raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
        
    # Buscar primero solo por nombre para dar mejor feedback
    nino_por_nombre = db.query(Nino).filter(
        func.lower(func.trim(Nino.nombre)) == data.nombre.strip().lower()
    ).first()

    if not nino_por_nombre:
        raise HTTPException(
            status_code=404, 
            detail=f"No existe ningún paciente llamado '{data.nombre}' registrado por un familiar."
        )

    # Ahora verificar si la fecha coincide
    nino = db.query(Nino).filter(
        func.lower(func.trim(Nino.nombre)) == data.nombre.strip().lower(),
        Nino.fecha_nacimiento == data.fecha_nacimiento
    ).first()
    
    if not nino:
        raise HTTPException(
            status_code=404, 
            detail=f"El paciente '{data.nombre}' existe, pero la fecha de nacimiento no coincide (Registrada: {nino_por_nombre.fecha_nacimiento})."
        )
        
    if nino.terapeuta_id is not None and nino.terapeuta_id != terapeuta.id:
        raise HTTPException(
            status_code=409,
            detail="El paciente ya está asignado a otro terapeuta."
        )
        
    # Enriquecer perfil y vincular
    from app.models import NivelCognitivo
    nino.terapeuta_id = terapeuta.id
    nino.nivel_cognitivo = NivelCognitivo(data.nivel_cognitivo)
    nino.objetivos_intervencion = data.objetivos_intervencion
    
    # Combinar o sobreescribir el perfil sensorial (el terapeuta tiene la última palabra clínica)
    # Por ahora simplemente guardamos el que manda el terapeuta
    nino.perfil_sensorial = data.perfil_sensorial
    
    db.commit()
    
    return {"status": "ok", "message": "Paciente vinculado y actualizado exitosamente"}
