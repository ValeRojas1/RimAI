from datetime import datetime, timedelta, date
from typing import List, Dict, Any
import time

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.ai.motor import motor_adaptativo
from app.auth import get_current_user
from app.database import get_db
from app.models import (
    Actividad,
    DecisionClinica,
    EstadoClinico,
    EstadoSesion,
    NivelCognitivo,
    NivelDificultad,
    Nino,
    PadreTutor,
    PlanActividad,
    PlanTerapeutico,
    ResultadoActividad,
    Sesion,
    Terapeuta,
    Usuario,
)
from app.schemas import (
    ActividadOut,
    AsistenteIAResponse,
    CrearPacienteFamiliaRequest,
    CrearSesionRequest,
    DashboardResumen,
    DecisionClinicaRequest,
    GenerarPlanResponse,
    MetricasProgresoOut,
    NivelInicialRequest,
    NivelInicialResponse,
    NinoPendienteOut,
    PacienteDashboard,
    PerfilClinicoRequest,
    PerfilClinicoResponse,
    PerfilNino,
    PlanOut,
    SesionResumen,
    TrazabilidadItem,
    UltimaSesionInfo,
    VincularPacienteRequest,
)

router = APIRouter(prefix="/api", tags=["clinical"])


def _calcular_edad(fecha_nac: date) -> int:
    hoy = date.today()
    return hoy.year - fecha_nac.year - ((hoy.month, hoy.day) < (fecha_nac.month, fecha_nac.day))


def _get_terapeuta(current_user: Usuario, db: Session) -> Terapeuta:
    terapeuta = db.query(Terapeuta).filter(Terapeuta.usuario_id == current_user.id).first()
    if not terapeuta:
        raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
    return terapeuta


def _assert_terapeuta_nino(nino: Nino, terapeuta: Terapeuta):
    if nino.terapeuta_id != terapeuta.id:
        raise HTTPException(status_code=403, detail="Paciente fuera del contexto del terapeuta")


def _ultimos_resultados(db: Session, nino_id) -> List[ResultadoActividad]:
    return (
        db.query(ResultadoActividad)
        .join(Sesion)
        .filter(Sesion.nino_id == nino_id)
        .order_by(ResultadoActividad.timestamp.desc())
        .limit(8)
        .all()
    )


def _tasa_resultados(resultados: List[ResultadoActividad]) -> float:
    total_aciertos = sum(r.aciertos or 0 for r in resultados)
    total_intentos = sum(r.repeticiones or 0 for r in resultados)
    return round(total_aciertos / total_intentos, 2) if total_intentos > 0 else 0.0


def _perfil_data(nino: Nino) -> Dict[str, Any]:
    perfil = nino.perfil_sensorial or {}
    return {
        "intereses": perfil.get("intereses", []),
        "estimulos_aversivos": perfil.get("estimulosAversivos") or perfil.get("estimulos_aversivos") or {},
    }


def _map_dificultad_ia(label: str) -> str:
    return {
        "Basico": "Bajo",
        "Básico": "Bajo",
        "Intermedio": "Medio",
        "Avanzado": "Alto",
        "Bajo": "Bajo",
        "Medio": "Medio",
        "Alto": "Alto",
    }.get(label, "Medio")


def _nivel_ayuda_num(label: str | None) -> int:
    return {"Ninguna": 0, "Verbal": 1, "Fisica": 2, "Física": 2}.get(label or "Ninguna", 0)


def _build_dashboard(current_user: Usuario, db: Session) -> DashboardResumen:
    terapeuta = _get_terapeuta(current_user, db)
    ninos = (
        db.query(Nino)
        .filter(Nino.terapeuta_id == terapeuta.id, Nino.activo == True)
        .order_by(Nino.created_at.asc())
        .all()
    )

    inicio_semana = datetime.utcnow() - timedelta(days=7)
    sesiones_semana = (
        db.query(Sesion)
        .join(Nino)
        .filter(Nino.terapeuta_id == terapeuta.id, Sesion.fecha_inicio >= inicio_semana)
        .count()
    )

    pacientes_out: List[PacienteDashboard] = []
    alertas = 0
    for nino in ninos:
        plan = (
            db.query(PlanTerapeutico)
            .filter(PlanTerapeutico.nino_id == nino.id, PlanTerapeutico.activo == True)
            .order_by(PlanTerapeutico.fecha_inicio.desc())
            .first()
        )
        ultima_sesion = (
            db.query(Sesion)
            .filter(Sesion.nino_id == nino.id)
            .order_by(Sesion.fecha_inicio.desc())
            .first()
        )
        ultima_info = None
        if ultima_sesion:
            resultados = db.query(ResultadoActividad).filter(ResultadoActividad.sesion_id == ultima_sesion.id).all()
            tasa = _tasa_resultados(resultados)
            if tasa < 0.5:
                alertas += 1
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
            plan_activo=plan.nombre if plan else None,
            plan_activo_id=str(plan.id) if plan else None,
            ultima_sesion=ultima_info,
            estado_clinico=nino.estado_clinico.value,
        ))

    return DashboardResumen(
        terapeuta_id=str(terapeuta.id),
        terapeuta_nombre=current_user.nombre,
        total_pacientes=len(ninos),
        sesiones_esta_semana=sesiones_semana,
        alertas_baja_adherencia=alertas,
        pacientes=pacientes_out,
    )


@router.get("/dashboard/resumen", response_model=DashboardResumen)
def get_resumen(current_user: Usuario = Depends(get_current_user), db: Session = Depends(get_db)):
    return _build_dashboard(current_user, db)


@router.get("/terapeutas/{terapeuta_id}/dashboard", response_model=DashboardResumen)
def get_dashboard_terapeuta(
    terapeuta_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    if str(terapeuta.id) != terapeuta_id:
        raise HTTPException(status_code=403, detail="No puedes acceder a otro dashboard")
    return _build_dashboard(current_user, db)


@router.get("/ninos/{nino_id}", response_model=PerfilNino)
@router.get("/dashboard/paciente/{nino_id}/perfil", response_model=PerfilNino)
def get_perfil_nino(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)

    plan = (
        db.query(PlanTerapeutico)
        .filter(PlanTerapeutico.nino_id == nino.id, PlanTerapeutico.activo == True)
        .order_by(PlanTerapeutico.fecha_inicio.desc())
        .first()
    )
    perfil = _perfil_data(nino)
    return PerfilNino(
        id=str(nino.id),
        nombre=nino.nombre,
        fecha_nacimiento=nino.fecha_nacimiento,
        edad=_calcular_edad(nino.fecha_nacimiento),
        diagnostico=nino.diagnostico,
        nivel_cognitivo=nino.nivel_cognitivo.value,
        perfil_sensorial=nino.perfil_sensorial,
        objetivos_intervencion=nino.objetivos_intervencion,
        intereses=perfil["intereses"],
        estimulos_aversivos=perfil["estimulos_aversivos"],
        documento_diagnostico=nino.documento_diagnostico,
        plan_activo_id=str(plan.id) if plan else None,
        estado_clinico=nino.estado_clinico.value,
        vinculado_at=nino.vinculado_at,
        perfil_completado_at=nino.perfil_completado_at,
    )


@router.get("/ninos/{nino_id}/plan", response_model=PlanOut)
@router.get("/dashboard/paciente/{nino_id}/plan", response_model=PlanOut)
def get_plan_activo(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)

    plan = (
        db.query(PlanTerapeutico)
        .options(joinedload(PlanTerapeutico.actividades).joinedload(PlanActividad.actividad))
        .filter(PlanTerapeutico.nino_id == nino_id, PlanTerapeutico.activo == True)
        .order_by(PlanTerapeutico.fecha_inicio.desc())
        .first()
    )
    if not plan:
        raise HTTPException(status_code=404, detail="No hay plan activo para este paciente")

    plan_acts = sorted(plan.actividades, key=lambda item: item.orden or 0)
    return PlanOut(
        id=str(plan.id),
        nombre=plan.nombre,
        nino_id=str(nino.id),
        nino_nombre=nino.nombre,
        fecha_inicio=plan.fecha_inicio,
        nivel_dificultad_actual=plan.nivel_dificultad_actual.value,
        activo=plan.activo,
        actividades=[
            ActividadOut(
                id=str(pa.actividad.id),
                nombre=pa.actividad.nombre,
                tipo=pa.actividad.tipo,
                instrucciones=pa.actividad.instrucciones,
                nivel_dificultad=pa.actividad.nivel_dificultad.value,
                duracion_estimada=pa.actividad.duracion_estimada,
            )
            for pa in plan_acts
            if pa.actividad and pa.actividad.activo
        ],
    )


@router.get("/actividades/{actividad_id}", response_model=ActividadOut)
def get_actividad(
    actividad_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    actividad = db.query(Actividad).filter(Actividad.id == actividad_id, Actividad.activo == True).first()
    if not actividad:
        raise HTTPException(status_code=404, detail="Actividad no encontrada")
    return ActividadOut(
        id=str(actividad.id),
        nombre=actividad.nombre,
        tipo=actividad.tipo,
        instrucciones=actividad.instrucciones,
        nivel_dificultad=actividad.nivel_dificultad.value,
        duracion_estimada=actividad.duracion_estimada,
    )


@router.post("/sesiones", response_model=SesionResumen)
def crear_sesion(
    data: CrearSesionRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == data.nino_id).first()
    plan = db.query(PlanTerapeutico).filter(PlanTerapeutico.id == data.plan_id).first()
    if not nino or not plan:
        raise HTTPException(status_code=404, detail="Niño o plan no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)

    sesion = Sesion(
        nino_id=nino.id,
        plan_id=plan.id,
        fecha_inicio=datetime.utcnow(),
        fecha_fin=datetime.utcnow(),
        estado=EstadoSesion.completada,
        sync_at=datetime.utcnow(),
    )
    db.add(sesion)
    db.flush()

    for item in data.resultados:
        db.add(ResultadoActividad(
            sesion_id=sesion.id,
            actividad_id=item.actividad_id,
            tiempo_respuesta=item.tiempo_respuesta,
            aciertos=item.aciertos,
            repeticiones=item.repeticiones,
            nivel_ayuda_requerido=item.nivel_ayuda_requerido,
            nivel_dificultad_usado=NivelDificultad(item.nivel_dificultad_usado or "Medio"),
            observaciones=item.observaciones,
            emocion_detectada=item.emocion_detectada,
            confianza_emocion=item.confianza_emocion,
        ))

    db.commit()
    resultados = db.query(ResultadoActividad).filter(ResultadoActividad.sesion_id == sesion.id).all()
    total_aciertos = sum(r.aciertos or 0 for r in resultados)
    total_intentos = sum(r.repeticiones or 0 for r in resultados)
    tasa = round(total_aciertos / total_intentos, 2) if total_intentos else 0
    return SesionResumen(
        sesion_id=str(sesion.id),
        nino_nombre=nino.nombre,
        fecha=sesion.fecha_inicio,
        total_aciertos=total_aciertos,
        total_intentos=total_intentos,
        tasa_aciertos=tasa,
        nivel_dificultad_recomendado="Alto" if tasa >= 0.85 else "Medio" if tasa >= 0.65 else "Bajo",
    )


@router.post("/ia/nivel-inicial", response_model=NivelInicialResponse)
def estimar_nivel_inicial(
    data: NivelInicialRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    start = time.perf_counter()
    fallback = False
    mensaje = None
    try:
        terapeuta = _get_terapeuta(current_user, db)
        nino = db.query(Nino).filter(Nino.id == data.nino_id).first()
        if not nino:
            raise HTTPException(status_code=404, detail="Niño no encontrado")
        _assert_terapeuta_nino(nino, terapeuta)

        historial = _ultimos_resultados(db, nino.id)
        nino_data = {
            "fecha_nacimiento": nino.fecha_nacimiento,
            "nivel_cognitivo": nino.nivel_cognitivo.value,
            "perfil_sensorial": nino.perfil_sensorial or {},
            "objetivos_intervencion": nino.objetivos_intervencion or [],
            "tasa_previa": _tasa_resultados(historial),
        }
        dificultad, confianza = motor_adaptativo.predecir_dificultad(nino_data)
        nivel = _map_dificultad_ia(dificultad)
    except HTTPException:
        raise
    except Exception:
        fallback = True
        mensaje = "IA-01 no disponible. Se usa nivel por defecto Medio."
        nivel = "Medio"
        confianza = 0.0

    return NivelInicialResponse(
        nivel_recomendado=nivel,
        confianza=round(float(confianza), 3),
        latencia_ms=round((time.perf_counter() - start) * 1000, 2),
        fallback=fallback,
        mensaje=mensaje,
    )


@router.get("/ia/asistente/{nino_id}", response_model=AsistenteIAResponse)
def get_asistente_ia(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    perfil = get_perfil_nino(nino_id, current_user, db)
    plan = get_plan_activo(nino_id, current_user, db)
    historial = _ultimos_resultados(db, nino_id)
    tasa = _tasa_resultados(historial)

    recomendaciones = [
        {
            "id": f"ia02-{nino_id}",
            "actividad": "Ajustar duración de actividades de atención conjunta",
            "justificacion": f"El historial reciente muestra una tasa de aciertos de {int(tasa * 100)}%.",
            "confianza": 0.88,
            "estado": "PENDIENTE",
        },
        {
            "id": f"ia03-{nino_id}",
            "actividad": "Priorizar estímulos alineados a intereses del niño",
            "justificacion": "El perfil sensorial contiene intereses útiles para aumentar adherencia.",
            "confianza": 0.84,
            "estado": "PENDIENTE",
        },
    ] if plan.actividades else []

    return AsistenteIAResponse(
        nino_id=perfil.id,
        nino_nombre=perfil.nombre,
        analisis_cognitivo={
            "nivel_cognitivo": perfil.nivel_cognitivo,
            "edad": perfil.edad,
            "carga_cognitiva": min(0.95, max(0.2, 1 - tasa if tasa else 0.55)),
            "nivel_calma": 8.0 if tasa >= 0.7 else 6.5,
            "foco_estimado": "22 min" if tasa >= 0.7 else "15 min",
        },
        recomendaciones=recomendaciones,
        plan_sesion=[
            {
                "id": actividad.id,
                "title": actividad.nombre,
                "description": actividad.instrucciones or actividad.tipo,
                "duration": f"{max(1, (actividad.duracion_estimada or 300) // 60)} MIN",
                "has_scanning": index == 0,
            }
            for index, actividad in enumerate(plan.actividades)
        ],
    )


@router.post("/ia/decision-clinica")
def registrar_decision_clinica(
    data: DecisionClinicaRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    db.add(DecisionClinica(
        terapeuta_id=terapeuta.id,
        nino_id=data.nino_id,
        recomendacion_id=data.recomendacion_id,
        accion=data.accion,
        observacion=data.observacion,
    ))
    db.commit()
    return {"status": "ok", "message": "Decisión clínica registrada"}


@router.get("/ninos/{nino_id}/progreso", response_model=MetricasProgresoOut)
def get_progreso(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)
    sesiones = db.query(Sesion).filter(Sesion.nino_id == nino.id, Sesion.estado == EstadoSesion.completada).all()
    historia = []
    for sesion in sesiones:
        historia.append(_tasa_resultados(db.query(ResultadoActividad).filter(ResultadoActividad.sesion_id == sesion.id).all()))
    tasa = round(sum(historia) / len(historia), 2) if historia else 0.0
    return MetricasProgresoOut(
        sesiones_completadas=len(sesiones),
        tasa_aciertos=tasa,
        adherencia=1.0 if sesiones else 0.0,
        historia_aciertos=historia[-6:] or [0.0],
    )


@router.post("/dashboard/paciente/{nino_id}/plan/generar", response_model=GenerarPlanResponse)
def generar_plan_terapeutico(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Paciente no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)

    # ✔ Guardia de estado: solo generar si el perfil está listo
    if nino.estado_clinico not in (
        EstadoClinico.listo_para_plan,
        EstadoClinico.plan_activo,   # permite regenerar
    ):
        campos_faltantes = []
        if not nino.objetivos_intervencion:
            campos_faltantes.append("objetivos de intervención")
        if not nino.perfil_sensorial:
            campos_faltantes.append("perfil sensorial")
        raise HTTPException(
            status_code=422,
            detail={
                "mensaje": f"El perfil no está listo. Estado actual: {nino.estado_clinico.value}",
                "campos_faltantes": campos_faltantes,
                "estado_actual": nino.estado_clinico.value,
            },
        )

    for viejo in db.query(PlanTerapeutico).filter(PlanTerapeutico.nino_id == nino.id, PlanTerapeutico.activo == True).all():
        viejo.activo = False

    dificultad, confianza = motor_adaptativo.predecir_dificultad({
        "fecha_nacimiento": nino.fecha_nacimiento,
        "nivel_cognitivo": nino.nivel_cognitivo.value,
        "perfil_sensorial": nino.perfil_sensorial or {},
        "objetivos_intervencion": nino.objetivos_intervencion or [],
    })
    dificultad_enum = NivelDificultad(_map_dificultad_ia(dificultad))
    plan = PlanTerapeutico(
        nombre=f"Plan activo de {nino.nombre}",
        nino_id=nino.id,
        terapeuta_id=terapeuta.id,
        fecha_inicio=date.today(),
        nivel_dificultad_actual=dificultad_enum,
        activo=True,
    )
    db.add(plan)
    db.flush()

    actividades = db.query(Actividad).filter(Actividad.nivel_dificultad == dificultad_enum, Actividad.activo == True).limit(3).all()
    for index, actividad in enumerate(actividades, start=1):
        db.add(PlanActividad(plan_id=plan.id, actividad_id=actividad.id, orden=index))

    # Avanzar estado y registrar trazabilidad
    nino.estado_clinico = EstadoClinico.plan_activo
    db.add(DecisionClinica(
        terapeuta_id=terapeuta.id,
        nino_id=nino.id,
        recomendacion_id="plan_ia",
        accion="GENERAR",
        observacion=f"Plan generado por IA. Dificultad: {dificultad_enum.value}. Confianza: {round(float(confianza), 3)}",
    ))

    db.commit()
    return GenerarPlanResponse(
        plan_id=str(plan.id),
        dificultad_inicial=dificultad_enum.value,
        confianza_ia=float(confianza),
        mensaje="Plan generado exitosamente con IA",
    )


@router.post("/dashboard/terapeuta/vincular-paciente")
def vincular_paciente(
    data: VincularPacienteRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.rol.value != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular pacientes")

    terapeuta = _get_terapeuta(current_user, db)
    nino_por_nombre = db.query(Nino).filter(func.lower(func.trim(Nino.nombre)) == data.nombre.strip().lower()).first()
    if not nino_por_nombre:
        raise HTTPException(status_code=404, detail=f"No existe ningún paciente llamado '{data.nombre}' registrado por un familiar.")

    nino = (
        db.query(Nino)
        .filter(func.lower(func.trim(Nino.nombre)) == data.nombre.strip().lower(), Nino.fecha_nacimiento == data.fecha_nacimiento)
        .first()
    )
    if not nino:
        raise HTTPException(status_code=404, detail=f"El paciente '{data.nombre}' existe, pero la fecha de nacimiento no coincide.")
    if nino.terapeuta_id is not None and nino.terapeuta_id != terapeuta.id:
        raise HTTPException(status_code=409, detail="El paciente ya está asignado a otro terapeuta.")

    nino.terapeuta_id = terapeuta.id
    nino.nivel_cognitivo = NivelCognitivo(data.nivel_cognitivo)
    nino.objetivos_intervencion = data.objetivos_intervencion
    nino.perfil_sensorial = data.perfil_sensorial
    db.commit()
    return {"status": "ok", "message": "Paciente vinculado y actualizado exitosamente"}


@router.get("/dashboard/familia/resumen", response_model=DashboardResumen)
def get_resumen_familia(
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    tutor = db.query(PadreTutor).filter(PadreTutor.usuario_id == current_user.id).first()
    if not tutor:
        raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")
    ninos = db.query(Nino).filter(Nino.tutor_id == tutor.id, Nino.activo == True).all()
    pacientes = []
    for nino in ninos:
        plan = db.query(PlanTerapeutico).filter(PlanTerapeutico.nino_id == nino.id, PlanTerapeutico.activo == True).first()
        pacientes.append(PacienteDashboard(
            id=str(nino.id),
            nombre=nino.nombre,
            edad=_calcular_edad(nino.fecha_nacimiento),
            nivel_cognitivo=nino.nivel_cognitivo.value,
            plan_activo=plan.nombre if plan else None,
            plan_activo_id=str(plan.id) if plan else None,
            ultima_sesion=None,
            estado_clinico=nino.estado_clinico.value,
        ))
    return DashboardResumen(total_pacientes=len(ninos), sesiones_esta_semana=0, alertas_baja_adherencia=0, pacientes=pacientes)


@router.get("/dashboard/terapeuta/pendientes", response_model=list[NinoPendienteOut])
def get_pendientes(
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retorna niños en estado pendiente_asignacion.
    Cualquier terapeuta autenticado puede verlos para decidir vincularlos.
    """
    if current_user.rol.value != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden ver la bandeja de pendientes")

    ninos = (
        db.query(Nino)
        .filter(Nino.estado_clinico == EstadoClinico.pendiente_asignacion, Nino.activo == True)
        .order_by(Nino.created_at.asc())
        .all()
    )

    result = []
    for nino in ninos:
        tutor_nombre = None
        if nino.tutor_id:
            tutor = db.query(PadreTutor).filter(PadreTutor.id == nino.tutor_id).first()
            if tutor:
                usr = db.query(Usuario).filter(Usuario.id == tutor.usuario_id).first()
                if usr:
                    tutor_nombre = usr.nombre

        perfil = nino.perfil_sensorial or {}
        hitos = perfil.get("hitos", {})
        intereses = perfil.get("intereses", [])

        result.append(NinoPendienteOut(
            id=str(nino.id),
            nombre=nino.nombre,
            edad=_calcular_edad(nino.fecha_nacimiento),
            estado_clinico=nino.estado_clinico.value,
            fecha_registro=nino.created_at,
            diagnostico=nino.diagnostico,
            comunicacion=hitos.get("comunicacion"),
            intereses=intereses,
            tutor_nombre=tutor_nombre,
        ))

    return result


@router.post("/dashboard/terapeuta/vincular/{nino_id}")
def vincular_por_id(
    nino_id: str,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Vincula un niño por ID directo (desde la bandeja de espera).
    Cambia estado: pendiente_asignacion → perfil_clinico_incompleto.
    Registra trazabilidad en decisiones_clinicas.
    """
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id, Nino.activo == True).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")

    # Si ya está vinculado a este mismo terapeuta, OK (idempotente)
    if nino.terapeuta_id == terapeuta.id:
        return {"status": "ok", "estado_clinico": nino.estado_clinico.value, "nino_id": str(nino.id), "message": "Ya vinculado"}

    # Si está vinculado a otro terapeuta, rechazar
    if nino.terapeuta_id is not None:
        raise HTTPException(status_code=409, detail="El paciente ya está asignado a otro terapeuta.")

    if nino.estado_clinico != EstadoClinico.pendiente_asignacion:
        raise HTTPException(status_code=409, detail="El paciente no está disponible para vincular.")

    nino.terapeuta_id = terapeuta.id
    nino.estado_clinico = EstadoClinico.perfil_clinico_incompleto
    nino.vinculado_por = terapeuta.id
    nino.vinculado_at = datetime.utcnow()

    db.add(DecisionClinica(
        terapeuta_id=terapeuta.id,
        nino_id=nino.id,
        recomendacion_id="vincular_paciente",
        accion="ACEPTAR",
        observacion="Vinculado desde bandeja de espera. Estado anterior: pendiente_asignacion",
    ))
    db.commit()
    return {"status": "ok", "estado_clinico": nino.estado_clinico.value, "nino_id": str(nino.id)}


@router.patch("/ninos/{nino_id}/perfil-clinico", response_model=PerfilClinicoResponse)
def completar_perfil_clinico(
    nino_id: str,
    data: PerfilClinicoRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Terapeuta completa/corrige los campos clínicos del niño.
    Si se cumplen los mínimos, avanza automáticamente a listo_para_plan.
    """
    terapeuta = _get_terapeuta(current_user, db)
    nino = db.query(Nino).filter(Nino.id == nino_id).first()
    if not nino:
        raise HTTPException(status_code=404, detail="Niño no encontrado")
    _assert_terapeuta_nino(nino, terapeuta)

    # Actualizar campos clínicos
    nino.nivel_cognitivo = NivelCognitivo(data.nivel_cognitivo)
    nino.objetivos_intervencion = data.objetivos_intervencion

    if data.perfil_sensorial:
        existing = nino.perfil_sensorial or {}
        nino.perfil_sensorial = {**existing, **data.perfil_sensorial}

    if data.observaciones_clinicas:
        perf = nino.perfil_sensorial or {}
        perf["observaciones_clinicas"] = data.observaciones_clinicas
        nino.perfil_sensorial = perf

    # Verificar campos mínimos para avanzar a listo_para_plan
    campos_faltantes = []
    if not nino.objetivos_intervencion:
        campos_faltantes.append("objetivos_intervencion")
    if not nino.perfil_sensorial:
        campos_faltantes.append("perfil_sensorial")

    if not campos_faltantes:
        nino.estado_clinico = EstadoClinico.listo_para_plan
        nino.perfil_completado_at = datetime.utcnow()
        db.add(DecisionClinica(
            terapeuta_id=terapeuta.id,
            nino_id=nino.id,
            recomendacion_id="perfil_clinico",
            accion="COMPLETAR",
            observacion="Perfil clínico completado. Listo para generar plan.",
        ))
    else:
        nino.estado_clinico = EstadoClinico.perfil_clinico_incompleto

    db.commit()
    return PerfilClinicoResponse(
        estado_clinico=nino.estado_clinico.value,
        perfil_completado_at=nino.perfil_completado_at,
        campos_faltantes=campos_faltantes,
        mensaje="Perfil clínico guardado. Paciente listo para plan." if not campos_faltantes
                else f"Guardado. Aún faltan: {', '.join(campos_faltantes)}.",
    )


@router.post("/dashboard/familia/paciente", status_code=201)
def crear_paciente_familia(
    data: CrearPacienteFamiliaRequest,
    current_user: Usuario = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Crea un niño desde el wizard de admisión familiar.
    El niño queda en estado 'pendiente_asignacion' hasta que un terapeuta lo vincule.
    """
    tutor = db.query(PadreTutor).filter(PadreTutor.usuario_id == current_user.id).first()
    if not tutor:
        raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

    # Construir perfil_sensorial JSONB con estructura consistente
    hitos = data.hitos.model_dump() if data.hitos else {}
    sensorial_raw = data.sensorial.model_dump() if data.sensorial else {}

    # Extraer intereses de intereses_obsesivos del sensorial para el motor IA
    intereses = sensorial_raw.get("intereses_obsesivos", [])
    if "Ninguno" in intereses:
        intereses = [i for i in intereses if i != "Ninguno"]

    perfil_sensorial = {
        "hitos": hitos,
        "hipersensibilidad": sensorial_raw.get("hipersensibilidad", []),
        "hiposensibilidad": sensorial_raw.get("hiposensibilidad", []),
        "comportamientos_repetitivos": sensorial_raw.get("comportamientos_repetitivos", []),
        "intereses": intereses,
        "estimulos_aversivos": sensorial_raw.get("estimulos_aversivos") or {},
        "fuente": "admision_familiar",
    }

    nuevo_nino = Nino(
        nombre=data.nombre,
        fecha_nacimiento=data.fecha_nacimiento,
        nivel_cognitivo=NivelCognitivo.Medio,   # El terapeuta ajustará esto
        diagnostico=data.diagnostico,
        documento_diagnostico=data.documento_diagnostico,
        perfil_sensorial=perfil_sensorial,
        tutor_id=tutor.id,
        # Estado inicial: sin terapeuta, esperando asignación
        estado_clinico=EstadoClinico.pendiente_asignacion,
        creado_por=tutor.id,
        activo=True,
    )
    db.add(nuevo_nino)
    db.commit()
    db.refresh(nuevo_nino)

    # Trazabilidad: registrar creación (sin terapeuta_id, usamos un campo genérico)
    # La DecisionClinica requiere terapeuta_id; para trazabilidad familiar
    # usaremos un log en los metadatos del perfil_sensorial por ahora.
    # (El registro completo de trazabilidad con terapeuta ocurre en la vinculación)

    return {
        "status": "ok",
        "nino_id": str(nuevo_nino.id),
        "estado_clinico": nuevo_nino.estado_clinico.value,
        "message": "Paciente registrado. Un terapeuta lo vinculará pronto.",
    }
