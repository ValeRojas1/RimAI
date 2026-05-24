"""
dashboard_controller.py
-----------------------
Endpoints que consume el panel Flutter en el lado del terapeuta y la familia.

Rutas expuestas (prefijo /api/dashboard):
  GET  /resumen                            -> DashboardData del terapeuta logueado
  GET  /terapeuta/pendientes               -> Niños sin terapeuta asignado
  POST /terapeuta/vincular-paciente        -> Vincular niño a terapeuta por email/código
  POST /terapeuta/vincular/{nino_id}       -> Vincular niño a terapeuta por id directo
  GET  /familia/resumen                    -> DashboardData del tutor logueado
  POST /familia/paciente                   -> Registrar niño desde la app familiar
  POST /dashboard/paciente/{nino_id}/plan/generar -> Generar plan IA para un niño

Rutas adicionales sin prefijo /dashboard:
  GET  /api/ninos/{nino_id}                -> Perfil completo del niño
  GET  /api/ninos/{nino_id}/plan           -> Plan activo de un niño
  GET  /api/ninos/{nino_id}/progreso       -> Métricas de progreso clínico
  PATCH /api/ninos/{nino_id}/perfil-clinico -> Actualizar perfil clínico
  GET  /api/ia/asistente/{nino_id}         -> Datos del asistente IA para un niño
"""

import json
import os
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import psycopg2
from psycopg2.extras import Json, RealDictCursor
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.adapters.inbound.api.dependencies import get_current_user
from app.adapters.outbound.storage.cloud_storage_adapter import CloudStorageAdapter
from app.ai.motor import motor_adaptativo

router = APIRouter(tags=["dashboard"])

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
)


def _conn():
    return psycopg2.connect(DATABASE_URL)


def _crear_notificacion_tutor(cur, nino_id, titulo, mensaje):
    cur.execute(
        """
        INSERT INTO notificaciones (usuario_id, titulo, mensaje)
        SELECT pt.usuario_id, %s, %s
        FROM ninos n
        JOIN padres_tutores pt ON pt.id = n.tutor_id
        WHERE n.id = %s
        """,
        (titulo, mensaje, nino_id),
    )


# ── Pydantic models ────────────────────────────────────────────────────────────

@router.get("/api/files/evaluations/{filename}")
def descargar_documento_clinico(
    filename: str,
    current_user: dict = Depends(get_current_user),
):
    safe_name = os.path.basename(filename)
    storage = CloudStorageAdapter()
    path = os.path.join(storage.upload_dir, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Documento no encontrado")
    return FileResponse(path, filename=safe_name)


class VincularPacienteRequest(BaseModel):
    email: Optional[str] = None
    nino_id: Optional[str] = None
    nombre: Optional[str] = None


class RegistrarNinoRequest(BaseModel):
    nombre: str
    fecha_nacimiento: str          # "YYYY-MM-DD"
    nivel_cognitivo: Optional[str] = "Bajo"
    diagnostico: Optional[str] = None
    intereses: Optional[List[str]] = []
    estimulos_aversivos: Optional[Dict[str, Any]] = {}
    hitos: Optional[Dict[str, Any]] = {}
    sensorial: Optional[Dict[str, Any]] = {}
    rutinas_regulacion: Optional[List[str]] = []
    documentos_clinicos: Optional[Dict[str, Any]] = {}
    medicacion_actual: Optional[str] = None


class ActividadRequest(BaseModel):
    nombre: str
    categoria: str
    nivel_dificultad: str
    duracion_estimada: int
    materiales: Optional[List[str]] = []
    instrucciones: str
    plan_id: Optional[str] = None


class ResultadoActividadRequest(BaseModel):
    actividad_id: str
    aciertos: int
    repeticiones: int
    tiempo_respuesta: Optional[float] = 0
    nivel_ayuda_requerido: Optional[int] = 0
    nivel_dificultad_usado: Optional[str] = "Medio"
    observaciones: Optional[str] = None


class CrearSesionRequest(BaseModel):
    nino_id: str
    plan_id: str
    resultados: List[ResultadoActividadRequest]


class SolicitarAjusteDificultadRequest(BaseModel):
    plan_id: str
    actividad_id: str
    accion: str
    dificultad_actual: str
    dificultad_sugerida: str
    tasa_aciertos: Optional[float] = None
    muestras: Optional[int] = None
    observacion: Optional[str] = None


class ResolverSolicitudAjusteRequest(BaseModel):
    aceptar: bool
    observacion: Optional[str] = None


class ActualizarDificultadActividadRequest(BaseModel):
    nivel_dificultad: str
    origen: Optional[str] = "manual"
    observacion: Optional[str] = None
    tasa_aciertos: Optional[float] = None
    muestras: Optional[int] = None


# ── Helpers ────────────────────────────────────────────────────────────────────

class ValidarNivelTeaRequest(BaseModel):
    nivel_tea: int
    observacion: Optional[str] = None


class ActualizarEstadoPlanRequest(BaseModel):
    estado: str
    observacion: Optional[str] = None


MAX_ACTIVIDADES_PLAN = 3
MAX_DURACION_PLAN_SEGUNDOS = 3600
MIN_TIEMPO_ACTIVIDAD_SEGUNDOS = 30


def _calc_edad(fecha_nac) -> int:
    if fecha_nac is None:
        return 0
    hoy = date.today()
    if isinstance(fecha_nac, str):
        fecha_nac = date.fromisoformat(fecha_nac)
    if isinstance(fecha_nac, datetime):
        fecha_nac = fecha_nac.date()
    return hoy.year - fecha_nac.year - (
        (hoy.month, hoy.day) < (fecha_nac.month, fecha_nac.day)
    )


def _has_clinical_evidence(req: RegistrarNinoRequest) -> bool:
    documentos = req.documentos_clinicos or {}
    has_docs = any(bool(v) for v in documentos.values())
    return bool((req.diagnostico or "").strip() or (req.medicacion_actual or "").strip() or has_docs)


def _perfil_tiene_evidencia_clinica(
    perfil: Optional[Dict[str, Any]],
    diagnostico: Optional[str] = None,
) -> bool:
    perfil = perfil or {}
    documentos = perfil.get("documentos_clinicos") or {}
    medicacion = perfil.get("medicacion_actual")
    return bool(
        (diagnostico or "").strip()
        or (str(medicacion).strip() if medicacion is not None else "")
        or any(bool(v) for v in documentos.values())
    )


def _infer_nivel_tea(diagnostico: Optional[str], perfil: Optional[Dict[str, Any]]) -> int:
    text = (diagnostico or "").lower()
    triaje = _triaje_from_perfil(perfil)
    scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
    nivel_scq = str(scq.get("nivel_indicio") or "").lower()
    if "nivel 3" in text or "nivel iii" in text or "alto" in nivel_scq:
        return 3
    if "nivel 2" in text or "nivel ii" in text or "moderado" in nivel_scq:
        return 2
    return 1


def _objetivos_desde_perfil(perfil: Optional[Dict[str, Any]]) -> List[str]:
    perfil = perfil or {}
    hitos = perfil.get("hitos") or {}
    sensorial = perfil.get("sensorial") or {}
    objetivos = []
    comunicacion = hitos.get("comunicacion")
    if comunicacion:
        objetivos.append(f"Fortalecer comunicacion funcional ({comunicacion}).")
    if perfil.get("rutinas_regulacion"):
        objetivos.append("Usar rutinas de regulacion registradas por la familia.")
    if sensorial.get("hipersensibilidad") or perfil.get("estimulosAversivos"):
        objetivos.append("Adaptar actividades a sensibilidades y estimulos aversivos.")
    if perfil.get("intereses"):
        objetivos.append("Incorporar intereses del nino como motivadores terapeuticos.")
    return objetivos or [
        "Fortalecer comunicacion funcional.",
        "Mejorar tolerancia a actividades guiadas.",
        "Promover autonomia en rutinas diarias.",
    ]


def _triaje_from_perfil(perfil: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not perfil:
        return {}
    triaje = perfil.get("triaje")
    return triaje if isinstance(triaje, dict) else {}


def _documentos_from_req(
    existentes: Optional[Dict[str, Any]],
    nuevos: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    documentos = dict(existentes or {})
    for key, value in (nuevos or {}).items():
        if not value:
            documentos.pop(key, None)
            continue
        if (
            key in documentos
            and isinstance(documentos[key], dict)
            and isinstance(value, str)
            and documentos[key].get("nombre") == value
        ):
            continue
        documentos[key] = value
    return documentos


def _build_perfil_familiar(
    req: RegistrarNinoRequest,
    perfil_actual: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    perfil_actual = perfil_actual or {}
    triaje_actual = _triaje_from_perfil(perfil_actual)
    documentos = _documentos_from_req(
        perfil_actual.get("documentos_clinicos"),
        req.documentos_clinicos,
    )
    evidencia_clinica = bool(
        (req.diagnostico or "").strip()
        or (req.medicacion_actual or "").strip()
        or any(bool(v) for v in documentos.values())
    )
    scq_completado = bool(triaje_actual.get("scq_completado", False))
    envio_previo = bool(triaje_actual.get("autorizado_envio_terapeuta", False))

    triaje = {
        "tiene_evidencia_clinica": evidencia_clinica,
        "requiere_scq": not evidencia_clinica,
        "scq_completado": scq_completado,
        "autorizado_envio_terapeuta": evidencia_clinica or (scq_completado and envio_previo),
        "uso_no_diagnostico": True,
    }
    if isinstance(triaje_actual.get("scq"), dict):
        triaje["scq"] = triaje_actual["scq"]

    return {
        "hitos": req.hitos or {},
        "sensorial": req.sensorial or {},
        "intereses": req.intereses or [],
        "estimulosAversivos": req.estimulos_aversivos or {},
        "rutinas_regulacion": req.rutinas_regulacion or [],
        "documentos_clinicos": documentos,
        "medicacion_actual": req.medicacion_actual,
        "umbralSensorial": perfil_actual.get("umbralSensorial", "medio"),
        "preferenciasEntorno": perfil_actual.get("preferenciasEntorno", []),
        "triaje": triaje,
    }


def _normalize_dificultad(value: Optional[str]) -> str:
    dificultad = (value or "Medio").strip().capitalize()
    return dificultad if dificultad in ("Bajo", "Medio", "Alto") else "Medio"


def _normalize_estado_plan(value: Optional[str]) -> str:
    estado = (value or "").strip().lower()
    if estado not in ("borrador", "aprobado", "publicado"):
        raise HTTPException(status_code=400, detail="Estado de plan no valido")
    return estado


def _normalize_nivel_tea(value: Any) -> int:
    try:
        nivel = int(value)
    except (TypeError, ValueError):
        text = str(value or "").lower()
        if "1" in text:
            nivel = 1
        elif "2" in text:
            nivel = 2
        elif "3" in text:
            nivel = 3
        else:
            nivel = 0
    if nivel not in (1, 2, 3):
        raise HTTPException(status_code=400, detail="El nivel TEA debe ser 1, 2 o 3")
    return nivel


def _modo_ejecucion_por_tea(nivel_tea: Optional[int]) -> Dict[str, Any]:
    nivel = int(nivel_tea or 0)
    requiere = nivel != 1
    return {
        "modo_ejecucion": "acompanada" if requiere else "autonoma",
        "requiere_acompanamiento": requiere,
    }


def _validar_plan_publicable(cur, plan_id: str, terapeuta_id: str) -> Dict[str, Any]:
    cur.execute(
        """
        SELECT
            pt.id,
            pt.nino_id,
            pt.estado_plan,
            pt.limite_actividades,
            pt.limite_duracion_segundos,
            n.nivel_tea_validado,
            n.perfil_validado_at
        FROM planes_terapeuticos pt
        JOIN ninos n ON n.id = pt.nino_id
        WHERE pt.id = %s
          AND pt.terapeuta_id = %s
          AND pt.activo = TRUE
        """,
        (plan_id, terapeuta_id),
    )
    plan = cur.fetchone()
    if not plan:
        raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

    cur.execute(
        """
        SELECT
            COUNT(*) AS actividades,
            COALESCE(SUM(COALESCE(a.duracion_estimada, 0)), 0) AS duracion_total,
            COUNT(*) FILTER (WHERE COALESCE(a.duracion_estimada, 0) <= 0) AS sin_duracion
        FROM plan_actividades pa
        JOIN actividades a ON a.id = pa.actividad_id
        WHERE pa.plan_id = %s
        """,
        (plan_id,),
    )
    resumen = cur.fetchone()
    errores = []
    actividades = int(resumen["actividades"] or 0)
    duracion_total = int(resumen["duracion_total"] or 0)
    sin_duracion = int(resumen["sin_duracion"] or 0)

    if not plan["nivel_tea_validado"]:
        errores.append("El terapeuta debe validar el nivel TEA antes de aprobar o publicar el plan.")
    if not plan["perfil_validado_at"]:
        errores.append("El perfil clinico debe estar validado por el terapeuta.")
    if actividades == 0:
        errores.append("El plan debe tener al menos una actividad.")
    if actividades > MAX_ACTIVIDADES_PLAN:
        errores.append("El plan no puede tener mas de 3 actividades.")
    if sin_duracion > 0:
        errores.append("Todas las actividades deben tener duracion definida.")
    if duracion_total > MAX_DURACION_PLAN_SEGUNDOS:
        errores.append("La duracion total del plan no puede superar 60 minutos.")

    if errores:
        raise HTTPException(
            status_code=422,
            detail={
                "mensaje": "El plan no cumple las reglas de negocio para publicarse.",
                "errores": errores,
                "actividades": actividades,
                "duracion_total_segundos": duracion_total,
            },
        )

    return {
        "plan_id": str(plan["id"]),
        "nino_id": str(plan["nino_id"]),
        "nivel_tea_validado": plan["nivel_tea_validado"],
        "actividades": actividades,
        "duracion_total_segundos": duracion_total,
    }


def _ajustar_nivel(actual: str, direccion: str) -> Optional[str]:
    niveles = ["Bajo", "Medio", "Alto"]
    actual = _normalize_dificultad(actual)
    index = niveles.index(actual)
    if direccion == "aumentar" and index < len(niveles) - 1:
        return niveles[index + 1]
    if direccion == "reducir" and index > 0:
        return niveles[index - 1]
    return None


def _evaluar_ajuste_dificultad(
    cur,
    nino_id: str,
    plan_id: str,
    actividad_id: str,
) -> Optional[Dict[str, Any]]:
    cur.execute(
        """
        SELECT
            ra.aciertos,
            ra.repeticiones,
            ra.nivel_dificultad_usado,
            a.nombre AS actividad_nombre,
            pt.terapeuta_id,
            COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad, pt.nivel_dificultad_actual) AS nivel_dificultad_actual
        FROM resultados_actividad ra
        JOIN sesiones s ON s.id = ra.sesion_id
        JOIN actividades a ON a.id = ra.actividad_id
        JOIN planes_terapeuticos pt ON pt.id = s.plan_id
        LEFT JOIN plan_actividades pa
          ON pa.plan_id = s.plan_id
         AND pa.actividad_id = ra.actividad_id
        WHERE s.nino_id = %s
          AND s.plan_id = %s
          AND ra.actividad_id = %s
          AND s.estado = 'completada'
        ORDER BY ra.timestamp DESC
        LIMIT 3
        """,
        (nino_id, plan_id, actividad_id),
    )
    rows = cur.fetchall()
    if len(rows) < 1:
        return {
            "actividad_id": actividad_id,
            "accion": "mantener",
            "registrado": False,
            "aplicable": False,
            "muestras": len(rows),
            "razon": "Se necesita al menos un resultado de esta actividad para ajustar.",
        }

    total_intentos = sum(r["repeticiones"] or 0 for r in rows)
    if total_intentos <= 0:
        return {
            "actividad_id": actividad_id,
            "accion": "mantener",
            "registrado": False,
            "aplicable": False,
            "muestras": len(rows),
            "razon": "No hay intentos suficientes para calcular desempeno.",
        }

    total_aciertos = sum(r["aciertos"] or 0 for r in rows)
    tasa = round(total_aciertos / total_intentos, 4)
    direccion = None
    accion = None
    if tasa >= 0.8:
        direccion = "aumentar"
        accion = "AUMENTAR_DIFICULTAD"
    elif tasa < 0.4:
        direccion = "reducir"
        accion = "REDUCIR_DIFICULTAD"

    actual = _normalize_dificultad(rows[0]["nivel_dificultad_actual"])
    if not direccion or not accion:
        return {
            "actividad_id": actividad_id,
            "actividad_nombre": rows[0]["actividad_nombre"],
            "accion": "mantener",
            "tasa_aciertos": tasa,
            "muestras": len(rows),
            "umbral_superior": 0.8,
            "umbral_inferior": 0.4,
            "dificultad_actual": actual,
            "dificultad_sugerida": actual,
            "registrado": False,
            "aplicable": False,
            "razon": "El desempeno no supera 80% ni cae por debajo de 40%.",
        }

    sugerida = _ajustar_nivel(actual, direccion)
    if not sugerida:
        return {
            "actividad_id": actividad_id,
            "actividad_nombre": rows[0]["actividad_nombre"],
            "accion": "mantener",
            "tasa_aciertos": tasa,
            "muestras": len(rows),
            "umbral_superior": 0.8,
            "umbral_inferior": 0.4,
            "dificultad_actual": actual,
            "dificultad_sugerida": actual,
            "registrado": False,
            "aplicable": False,
            "razon": "La actividad ya esta en el limite de dificultad.",
        }

    payload = {
        "actividad_id": actividad_id,
        "actividad_nombre": rows[0]["actividad_nombre"],
        "tasa_aciertos": tasa,
        "muestras": len(rows),
        "umbral_superior": 0.8,
        "umbral_inferior": 0.4,
        "dificultad_actual": actual,
        "dificultad_sugerida": sugerida,
    }
    return {
        **payload,
        "accion": direccion,
        "registrado": False,
        "aplicable": True,
        "razon": "Sugerencia pendiente de aprobacion del terapeuta.",
    }


def _extract_words(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return " ".join(_extract_words(v) for v in value.values())
    if isinstance(value, list):
        return " ".join(_extract_words(v) for v in value)
    return str(value)


def _score_actividad(act: Dict[str, Any], nino: Dict[str, Any], dificultad: str) -> int:
    perfil = nino.get("perfil_sensorial") or {}
    objetivos = nino.get("objetivos_intervencion") or []
    texto_perfil = _extract_words(perfil).lower()
    texto_objetivos = _extract_words(objetivos).lower()
    texto_act = " ".join(
        [
            str(act.get("tipo") or ""),
            str(act.get("nombre") or ""),
            str(act.get("instrucciones") or ""),
        ]
    ).lower()

    score = 0
    if act.get("nivel_dificultad") == dificultad:
        score += 8
    elif dificultad == "Medio":
        score += 3
    elif act.get("nivel_dificultad") == "Medio":
        score += 2

    if any(w in texto_objetivos for w in ("comunicacion", "lenguaje", "verbal", "social")):
        if any(w in texto_act for w in ("comunicacion", "turnos", "social", "lenguaje")):
            score += 6
    if any(w in texto_objetivos for w in ("atencion", "conjunta", "seguimiento")):
        if any(w in texto_act for w in ("atencion", "seguimiento", "visual", "clasificacion")):
            score += 6
    if any(w in texto_objetivos for w in ("regulacion", "emocional", "transicion")):
        if any(w in texto_act for w in ("regulacion", "emocional", "calma", "respiracion", "sensorial")):
            score += 6

    if any(w in texto_perfil for w in ("ruidos fuertes", "auditiv", "licuadora", "sirenas")):
        if any(w in texto_act for w in ("musica", "sonido", "ritmica", "auditiv")):
            score -= 8
        if any(w in texto_act for w in ("visual", "calma", "presion", "propiocept")):
            score += 4
    if any(w in texto_perfil for w in ("movimiento constante", "presion profunda", "morder objetos")):
        if any(w in texto_act for w in ("movimiento", "propiocept", "presion", "motor")):
            score += 4
    if any(w in texto_perfil for w in ("luces brillantes", "visual")):
        if any(w in texto_act for w in ("luz", "visual", "colores")):
            score -= 2

    return score


# ── GET /api/dashboard/resumen ─────────────────────────────────────────────────

@router.get("/api/dashboard/resumen")
def resumen_terapeuta(current_user: dict = Depends(get_current_user)):
    """Devuelve el resumen del dashboard para el terapeuta autenticado."""
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # 1. Datos del terapeuta
            cur.execute(
                """
                SELECT u.nombre, t.id AS terapeuta_id
                FROM usuarios u
                JOIN terapeutas t ON t.usuario_id = u.id
                WHERE u.id = %s
                """,
                (user_id,),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Terapeuta no encontrado")

            terapeuta_id = str(ter["terapeuta_id"])

            # 2. Pacientes activos asignados
            cur.execute(
                """
                SELECT
                    n.id,
                    n.nombre,
                    n.fecha_nacimiento,
                    n.nivel_cognitivo,
                    n.estado_clinico,
                    pt.id   AS plan_activo_id,
                    pt.nombre AS plan_activo,
                    s.fecha_inicio AS ultima_sesion_fecha,
                    s.estado        AS ultima_sesion_estado,
                    (
                        SELECT ROUND(
                            CAST(SUM(ra.aciertos) AS NUMERIC) /
                            NULLIF(SUM(ra.repeticiones), 0), 4
                        )
                        FROM resultados_actividad ra
                        WHERE ra.sesion_id = s.id
                    ) AS tasa_aciertos
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                LEFT JOIN sesiones s
                    ON s.id = (
                        SELECT id FROM sesiones
                        WHERE nino_id = n.id
                        ORDER BY fecha_inicio DESC
                        LIMIT 1
                    )
                WHERE n.terapeuta_id = %s AND n.activo = TRUE
                ORDER BY n.nombre
                """,
                (terapeuta_id,),
            )
            ninos = cur.fetchall()

            # 3. Sesiones esta semana
            cur.execute(
                """
                SELECT COUNT(*) AS cnt
                FROM sesiones s
                JOIN ninos n ON n.id = s.nino_id
                WHERE n.terapeuta_id = %s
                  AND s.fecha_inicio >= date_trunc('week', NOW())
                """,
                (terapeuta_id,),
            )
            sesiones_semana = cur.fetchone()["cnt"] or 0

            # 4. Alertas de baja adherencia (simplificado: sesiones con tasa < 0.7)
            cur.execute(
                """
                SELECT COUNT(DISTINCT n.id) AS cnt
                FROM ninos n
                JOIN sesiones s ON s.nino_id = n.id
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE n.terapeuta_id = %s
                  AND n.activo = TRUE
                GROUP BY n.id
                HAVING ROUND(
                    CAST(SUM(ra.aciertos) AS NUMERIC) /
                    NULLIF(SUM(ra.repeticiones), 0), 2
                ) < 0.7
                """,
                (terapeuta_id,),
            )
            alertas_rows = cur.fetchall()
            alertas = len(alertas_rows)

    pacientes_list = []
    for n in ninos:
        pacientes_list.append(
            {
                "id": str(n["id"]),
                "nombre": n["nombre"],
                "edad": _calc_edad(n["fecha_nacimiento"]),
                "nivel_cognitivo": n["nivel_cognitivo"] or "Sin datos",
                "estado_clinico": n["estado_clinico"] or "activo",
                "plan_activo": n["plan_activo"],
                "plan_activo_id": str(n["plan_activo_id"]) if n["plan_activo_id"] else None,
                "ultima_sesion": {
                    "fecha": n["ultima_sesion_fecha"].isoformat()
                    if n["ultima_sesion_fecha"]
                    else None,
                    "tasa_aciertos": float(n["tasa_aciertos"])
                    if n["tasa_aciertos"] is not None
                    else None,
                    "estado": n["ultima_sesion_estado"],
                }
                if n["ultima_sesion_fecha"]
                else None,
            }
        )

    return {
        "terapeuta_id": terapeuta_id,
        "terapeuta_nombre": ter["nombre"],
        "total_pacientes": len(pacientes_list),
        "sesiones_esta_semana": sesiones_semana,
        "alertas_baja_adherencia": alertas,
        "pacientes": pacientes_list,
    }


# ── GET /api/dashboard/terapeuta/pendientes ────────────────────────────────────

@router.get("/api/dashboard/terapeuta/pendientes")
def pacientes_pendientes(current_user: dict = Depends(get_current_user)):
    """Lista de niños sin terapeuta asignado (pendiente_asignacion)."""
    if current_user["role"] not in ("terapeuta", "admin"):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    n.id,
                    n.nombre,
                    n.fecha_nacimiento,
                    n.nivel_cognitivo,
                    n.estado_clinico,
                    n.diagnostico,
                    n.created_at AS fecha_registro,
                    n.perfil_sensorial,
                    u.nombre AS tutor_nombre
                FROM ninos n
                LEFT JOIN padres_tutores pt ON pt.id = n.tutor_id
                LEFT JOIN usuarios u ON u.id = pt.usuario_id
                WHERE n.terapeuta_id IS NULL AND n.activo = TRUE
                  AND (
                    COALESCE(n.perfil_sensorial->'triaje'->>'requiere_scq', 'false') <> 'true'
                    OR COALESCE(n.perfil_sensorial->'triaje'->>'autorizado_envio_terapeuta', 'false') = 'true'
                  )
                ORDER BY n.created_at DESC
                """
            )
            rows = cur.fetchall()

    result = []
    for r in rows:
        sensorial = r["perfil_sensorial"] or {}
        hitos = sensorial.get("hitos", {})
        triaje = _triaje_from_perfil(sensorial)
        scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
        result.append(
            {
                "id": str(r["id"]),
                "nombre": r["nombre"],
                "edad": _calc_edad(r["fecha_nacimiento"]),
                "estado_clinico": r["estado_clinico"] or "pendiente_asignacion",
                "fecha_registro": r["fecha_registro"].isoformat()
                if r["fecha_registro"]
                else None,
                "diagnostico": r["diagnostico"],
                "comunicacion": hitos.get("comunicacion"),
                "intereses": sensorial.get("intereses", []),
                "tutor_nombre": r["tutor_nombre"],
                "requiere_scq": triaje.get("requiere_scq", False),
                "scq_completado": triaje.get("scq_completado", False),
                "scq_puntaje": scq.get("puntaje_total"),
                "scq_nivel": scq.get("nivel_indicio"),
                "documentos_clinicos": sensorial.get("documentos_clinicos", {}),
                "medicacion_actual": sensorial.get("medicacion_actual"),
                "hitos": hitos,
                "estimulos_aversivos": sensorial.get("estimulosAversivos", {}),
                "rutinas_regulacion": sensorial.get("rutinas_regulacion", []),
                "sensorial_familia": sensorial.get("sensorial", {}),
            }
        )
    return result


# ── POST /api/dashboard/terapeuta/vincular-paciente ───────────────────────────

@router.post("/api/dashboard/terapeuta/vincular-paciente")
def vincular_paciente_por_email(
    req: VincularPacienteRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Obtener terapeuta_id
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            if req.nino_id:
                cur.execute(
                    "SELECT id, diagnostico, perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                    (req.nino_id,),
                )
            elif req.email:
                cur.execute(
                    """
                    SELECT n.id, n.diagnostico, n.perfil_sensorial FROM ninos n
                    JOIN padres_tutores pt ON pt.id = n.tutor_id
                    JOIN usuarios u ON u.id = pt.usuario_id
                    WHERE lower(u.email) = lower(%s) AND n.activo = TRUE
                    LIMIT 1
                    """,
                    (req.email,),
                )
            else:
                raise HTTPException(status_code=400, detail="Debe indicar nino_id o email")

            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            perfil = nino.get("perfil_sensorial") or {}
            triaje = _triaje_from_perfil(perfil)
            requiere_scq = bool(triaje.get("requiere_scq", False))
            tiene_evidencia = _perfil_tiene_evidencia_clinica(
                perfil,
                nino.get("diagnostico"),
            )
            nuevo_estado = (
                "perfil_clinico_incompleto"
                if requiere_scq and not tiene_evidencia
                else "vinculado_terapeuta"
            )

            cur.execute(
                """
                UPDATE ninos
                SET terapeuta_id = %s,
                    estado_clinico = %s,
                    vinculado_por = %s,
                    vinculado_at = NOW()
                WHERE id = %s
                """,
                (ter["id"], nuevo_estado, ter["id"], nino["id"]),
            )

            # Notificar al tutor sobre la vinculación
            cur.execute("SELECT nombre FROM usuarios WHERE id = %s", (current_user["id"],))
            user_row = cur.fetchone()
            terapeuta_nombre = user_row["nombre"] if user_row else "Un terapeuta"

            cur.execute("SELECT nombre FROM ninos WHERE id = %s", (nino["id"],))
            nino_row = cur.fetchone()
            nino_nombre = nino_row["nombre"] if nino_row else "tu hijo/a"

            mensaje = f"Tu hijo/a {nino_nombre} ha sido vinculado/a al terapeuta {terapeuta_nombre}."
            _crear_notificacion_tutor(cur, nino["id"], "Terapeuta Vinculado", mensaje)

    return {"ok": True, "nino_id": str(nino["id"])}


# ── POST /api/dashboard/terapeuta/vincular/{nino_id} ──────────────────────────

@router.post("/api/dashboard/terapeuta/vincular/{nino_id}")
def vincular_paciente_por_id(
    nino_id: str,
    omitir_perfil: bool = False,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden vincular")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                "SELECT id, diagnostico, perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            perfil = nino.get("perfil_sensorial") or {}
            triaje = _triaje_from_perfil(perfil)
            requiere_scq = bool(triaje.get("requiere_scq", False))
            tiene_evidencia = _perfil_tiene_evidencia_clinica(
                perfil,
                nino.get("diagnostico"),
            )
            
            perfil_obligatorio = requiere_scq and not tiene_evidencia
            
            if omitir_perfil and perfil_obligatorio:
                raise HTTPException(
                    status_code=400,
                    detail="El perfil clínico es obligatorio para casos SCQ sin evidencia previa"
                )

            if omitir_perfil:
                nivel_tea = _infer_nivel_tea(nino.get("diagnostico"), perfil)
                objetivos = _objetivos_desde_perfil(perfil)
                cur.execute(
                    """
                    UPDATE ninos
                    SET terapeuta_id = %s,
                        estado_clinico = 'listo_para_plan',
                        vinculado_por = %s,
                        vinculado_at = NOW(),
                        perfil_completado_at = NOW(),
                        nivel_tea_validado = %s,
                        objetivos_intervencion = %s
                    WHERE id = %s
                    """,
                    (ter["id"], ter["id"], nivel_tea, objetivos, nino["id"]),
                )
            else:
                nuevo_estado = (
                    "perfil_clinico_incompleto"
                    if perfil_obligatorio
                    else "vinculado_terapeuta"
                )
                cur.execute(
                    """
                    UPDATE ninos
                    SET terapeuta_id = %s,
                        estado_clinico = %s,
                        vinculado_por = %s,
                        vinculado_at = NOW()
                    WHERE id = %s
                    """,
                    (ter["id"], nuevo_estado, ter["id"], nino["id"]),
                )

            # Notificar al tutor sobre la vinculación
            cur.execute("SELECT nombre FROM usuarios WHERE id = %s", (current_user["id"],))
            user_row = cur.fetchone()
            terapeuta_nombre = user_row["nombre"] if user_row else "Un terapeuta"

            cur.execute("SELECT nombre FROM ninos WHERE id = %s", (nino_id,))
            nino_row = cur.fetchone()
            nino_nombre = nino_row["nombre"] if nino_row else "tu hijo/a"

            mensaje = f"Tu hijo/a {nino_nombre} ha sido vinculado/a al terapeuta {terapeuta_nombre}."
            _crear_notificacion_tutor(cur, nino_id, "Terapeuta Vinculado", mensaje)

    return {"ok": True, "nino_id": nino_id}


# ── GET /api/dashboard/familia/resumen ────────────────────────────────────────

@router.get("/api/dashboard/familia/resumen")
def resumen_familia(current_user: dict = Depends(get_current_user)):
    """Resumen del panel familiar: lista de niños vinculados al tutor."""
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT
                    n.id, n.nombre, n.fecha_nacimiento,
                    n.nivel_cognitivo, n.estado_clinico, n.diagnostico,
                    n.perfil_sensorial,
                    pt.id AS plan_activo_id,
                    pt.nombre AS plan_activo,
                    pt.estado_plan AS plan_estado
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id
                   AND pt.activo = TRUE
                   AND pt.estado_plan = 'publicado'
                   AND pt.publicado_para_tutor = TRUE
                WHERE n.tutor_id = %s AND n.activo = TRUE
                """,
                (tutor["id"],),
            )
            ninos = cur.fetchall()

    pacientes_list = []
    for n in ninos:
        perfil = n["perfil_sensorial"] or {}
        triaje = _triaje_from_perfil(perfil)
        scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
        pacientes_list.append({
            "id": str(n["id"]),
            "nombre": n["nombre"],
            "fecha_nacimiento": n["fecha_nacimiento"].isoformat()
            if n["fecha_nacimiento"]
            else None,
            "edad": _calc_edad(n["fecha_nacimiento"]),
            "nivel_cognitivo": n["nivel_cognitivo"] or "Sin datos",
            "diagnostico": n["diagnostico"],
            "estado_clinico": n["estado_clinico"] or "pendiente_asignacion",
            "plan_activo": n["plan_activo"],
            "plan_activo_id": str(n["plan_activo_id"]) if n["plan_activo_id"] else None,
            "plan_estado": n["plan_estado"],
            "ultima_sesion": None,
            "hitos": perfil.get("hitos", {}),
            "sensorial": perfil.get("sensorial", {}),
            "intereses": perfil.get("intereses", []),
            "estimulos_aversivos": perfil.get("estimulosAversivos", {}),
            "rutinas_regulacion": perfil.get("rutinas_regulacion", []),
            "documentos_clinicos": perfil.get("documentos_clinicos", {}),
            "medicacion_actual": perfil.get("medicacion_actual"),
            "requiere_scq": triaje.get("requiere_scq", False),
            "scq_completado": triaje.get("scq_completado", False),
            "scq_autorizado_envio": triaje.get("autorizado_envio_terapeuta", False),
            "scq_puntaje": scq.get("puntaje_total"),
            "scq_nivel": scq.get("nivel_indicio"),
        })

    return {
        "terapeuta_id": None,
        "terapeuta_nombre": None,
        "total_pacientes": len(pacientes_list),
        "sesiones_esta_semana": 0,
        "alertas_baja_adherencia": 0,
        "pacientes": pacientes_list,
    }


# ── GET /api/dashboard/familia/notificaciones ──────────────────────────────────
@router.get("/api/dashboard/familia/notificaciones")
def obtener_notificaciones(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo los tutores pueden acceder a las notificaciones")
    
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, titulo, mensaje, leido, created_at
                FROM notificaciones
                WHERE usuario_id = %s
                ORDER BY created_at DESC
                LIMIT 50
                """,
                (current_user["id"],),
            )
            rows = cur.fetchall()
            
    return [
        {
            "id": str(r["id"]),
            "titulo": r["titulo"],
            "mensaje": r["mensaje"],
            "leido": r["leido"],
            "created_at": r["created_at"].isoformat() if r["created_at"] else None
        }
        for r in rows
    ]


# ── PATCH /api/dashboard/familia/notificaciones/{notificacion_id}/leer ────────────
@router.patch("/api/dashboard/familia/notificaciones/{notificacion_id}/leer")
def marcar_notificacion_leida(
    notificacion_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo los tutores pueden leer notificaciones")
        
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                UPDATE notificaciones
                SET leido = TRUE
                WHERE id = %s AND usuario_id = %s
                RETURNING id
                """,
                (notificacion_id, current_user["id"]),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Notificación no encontrada o no pertenece al usuario")
                
    return {"ok": True, "notificacion_id": notificacion_id}


# ── POST /api/dashboard/familia/paciente ──────────────────────────────────────

@router.post("/api/dashboard/familia/paciente")
def registrar_nino(
    req: RegistrarNinoRequest,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            perfil_sensorial = _build_perfil_familiar(req)
            triaje = _triaje_from_perfil(perfil_sensorial)

            cur.execute(
                """
                INSERT INTO ninos (
                    nombre, fecha_nacimiento, nivel_cognitivo,
                    diagnostico, perfil_sensorial, tutor_id, activo, estado_clinico
                )
                VALUES (%s, %s, %s, %s, %s::jsonb, %s, TRUE, 'pendiente_asignacion')
                RETURNING id
                """,
                (
                    req.nombre,
                    req.fecha_nacimiento,
                    req.nivel_cognitivo,
                    req.diagnostico,
                    Json(perfil_sensorial),
                    tutor["id"],
                ),
            )
            nino = cur.fetchone()

    return {
        "id": str(nino["id"]),
        "nombre": req.nombre,
        "requiere_scq": triaje.get("requiere_scq", False),
        "autorizado_envio_terapeuta": triaje.get("autorizado_envio_terapeuta", False),
    }


@router.patch("/api/dashboard/familia/paciente/{nino_id}")
def actualizar_nino_familia(
    nino_id: str,
    req: RegistrarNinoRequest,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT n.id, n.perfil_sensorial
                FROM ninos n
                WHERE n.id = %s
                  AND n.activo = TRUE
                  AND (
                    n.tutor_id = %s
                    OR n.creado_por = %s
                  )
                """,
                (nino_id, tutor["id"], tutor["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil_sensorial = _build_perfil_familiar(req, nino["perfil_sensorial"] or {})
            triaje = _triaje_from_perfil(perfil_sensorial)

            cur.execute(
                """
                UPDATE ninos
                SET nombre = %s,
                    fecha_nacimiento = %s,
                    nivel_cognitivo = %s,
                    diagnostico = %s,
                    perfil_sensorial = %s::jsonb
                WHERE id = %s
                RETURNING id
                """,
                (
                    req.nombre,
                    req.fecha_nacimiento,
                    req.nivel_cognitivo,
                    req.diagnostico,
                    Json(perfil_sensorial),
                    nino_id,
                ),
            )
            updated = cur.fetchone()

    return {
        "id": str(updated["id"]),
        "nombre": req.nombre,
        "requiere_scq": triaje.get("requiere_scq", False),
        "autorizado_envio_terapeuta": triaje.get("autorizado_envio_terapeuta", False),
    }


@router.delete("/api/dashboard/familia/paciente/{nino_id}")
def eliminar_nino_familia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    user_id = current_user["id"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (user_id,),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET activo = FALSE
                WHERE id = %s
                  AND activo = TRUE
                  AND (
                    tutor_id = %s
                    OR creado_por = %s
                  )
                RETURNING id
                """,
                (nino_id, tutor["id"], tutor["id"]),
            )
            deleted = cur.fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

    return {"ok": True, "nino_id": str(deleted["id"])}


@router.post("/api/dashboard/familia/paciente/{nino_id}/documento")
def subir_documento_clinico(
    nino_id: str,
    tipo: str = Form(...),
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede adjuntar documentos")

    storage = CloudStorageAdapter()
    file_url = storage.upload_file(file.file, file.filename or "documento", file.content_type or "application/octet-stream")

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
                (nino_id, current_user["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")

            perfil = nino["perfil_sensorial"] or {}
            documentos = perfil.get("documentos_clinicos") or {}
            documentos[tipo] = {
                "nombre": file.filename,
                "url": file_url,
                "content_type": file.content_type,
            }
            perfil["documentos_clinicos"] = documentos

            triaje = _triaje_from_perfil(perfil)
            triaje["tiene_evidencia_clinica"] = True
            triaje["requiere_scq"] = False
            triaje["autorizado_envio_terapeuta"] = True
            perfil["triaje"] = triaje

            cur.execute(
                """
                UPDATE ninos
                SET perfil_sensorial = %s::jsonb
                WHERE id = %s
                """,
                (Json(perfil), nino_id),
            )

    return {"ok": True, "tipo": tipo, "url": file_url}


# ── Actividades ocupacionales del terapeuta ───────────────────────────────────

@router.get("/api/dashboard/terapeuta/actividades")
def listar_actividades_ocupacionales(
    plan_id: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("terapeuta", "admin"):
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden listar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            terapeuta_id = None
            if current_user["role"] == "terapeuta":
                cur.execute(
                    "SELECT id FROM terapeutas WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                ter = cur.fetchone()
                if not ter:
                    raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
                terapeuta_id = ter["id"]

            if plan_id:
                if current_user["role"] == "terapeuta":
                    cur.execute(
                        """
                        SELECT id FROM planes_terapeuticos
                        WHERE id = %s
                          AND terapeuta_id = %s
                          AND activo = TRUE
                        """,
                        (plan_id, terapeuta_id),
                    )
                else:
                    cur.execute(
                        """
                        SELECT id FROM planes_terapeuticos
                        WHERE id = %s AND activo = TRUE
                        """,
                        (plan_id,),
                    )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Plan activo no encontrado")

            cur.execute(
                """
                SELECT
                    a.id, a.tipo, a.nombre, a.instrucciones,
                    COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad) AS nivel_dificultad,
                    a.nivel_dificultad AS nivel_catalogo,
                    a.duracion_estimada,
                    a.recursos_multimedia,
                    CASE WHEN pa.actividad_id IS NULL THEN FALSE ELSE TRUE END AS asociado
                FROM actividades a
                LEFT JOIN plan_actividades pa
                  ON pa.actividad_id = a.id
                 AND (%s::uuid IS NOT NULL AND pa.plan_id = %s::uuid)
                WHERE a.activo = TRUE
                ORDER BY a.nombre
                """,
                (plan_id, plan_id),
            )
            rows = cur.fetchall()

    return [
        {
            "id": str(r["id"]),
            "categoria": r["tipo"],
            "tipo": r["tipo"],
            "nombre": r["nombre"],
            "instrucciones": r["instrucciones"],
            "nivel_dificultad": r["nivel_dificultad"],
            "nivel_catalogo": r["nivel_catalogo"],
            "duracion_estimada": r["duracion_estimada"],
            "materiales": (r["recursos_multimedia"] or {}).get("materiales", []),
            "asociado": r["asociado"],
        }
        for r in rows
    ]


@router.post("/api/dashboard/terapeuta/actividades")
def crear_actividad_ocupacional(
    req: ActividadRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden registrar actividades")

    if not req.nombre.strip() or not req.categoria.strip() or not req.instrucciones.strip():
        raise HTTPException(status_code=400, detail="Nombre, categoría e instrucciones son obligatorios")
    if req.duracion_estimada <= 0:
        raise HTTPException(status_code=400, detail="La duración debe ser mayor a cero")

    dificultad = _normalize_dificultad(req.nivel_dificultad)
    materiales = [m.strip() for m in (req.materiales or []) if m and m.strip()]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            plan_context = None
            if req.plan_id:
                cur.execute(
                    """
                    SELECT pt.id, n.nivel_tea_validado
                    FROM planes_terapeuticos pt
                    JOIN ninos n ON n.id = pt.nino_id
                    WHERE pt.id = %s
                      AND pt.terapeuta_id = %s
                      AND pt.activo = TRUE
                    """,
                    (req.plan_id, ter["id"]),
                )
                plan_context = cur.fetchone()
                if not plan_context:
                    raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")
                cur.execute(
                    """
                    SELECT
                        COUNT(*) AS actividades,
                        COALESCE(SUM(COALESCE(a.duracion_estimada, 0)), 0) AS duracion_total
                    FROM plan_actividades pa
                    JOIN actividades a ON a.id = pa.actividad_id
                    WHERE pa.plan_id = %s
                    """,
                    (req.plan_id,),
                )
                resumen_plan = cur.fetchone()
                if int(resumen_plan["actividades"] or 0) >= MAX_ACTIVIDADES_PLAN:
                    raise HTTPException(status_code=422, detail="El plan no puede tener mas de 3 actividades")
                duracion_total = int(resumen_plan["duracion_total"] or 0)
                if duracion_total + req.duracion_estimada > MAX_DURACION_PLAN_SEGUNDOS:
                    raise HTTPException(status_code=422, detail="La duracion total del plan no puede superar 60 minutos")

            cur.execute(
                """
                INSERT INTO actividades (
                    tipo, nombre, instrucciones, nivel_dificultad,
                    duracion_estimada, recursos_multimedia, activo
                )
                VALUES (%s, %s, %s, %s, %s, %s::jsonb, TRUE)
                RETURNING id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada, recursos_multimedia
                """,
                (
                    req.categoria.strip(),
                    req.nombre.strip(),
                    req.instrucciones.strip(),
                    dificultad,
                    req.duracion_estimada,
                    Json({"materiales": materiales}),
                ),
            )
            actividad = cur.fetchone()

            asociado = False
            if req.plan_id:
                ejecucion = _modo_ejecucion_por_tea(plan_context["nivel_tea_validado"])
                cur.execute(
                    "SELECT COALESCE(MAX(orden), 0) + 1 AS orden FROM plan_actividades WHERE plan_id = %s",
                    (req.plan_id,),
                )
                orden = cur.fetchone()["orden"]
                cur.execute(
                    """
                    INSERT INTO plan_actividades (
                        plan_id, actividad_id, orden, nivel_dificultad_actual,
                        modo_ejecucion, requiere_acompanamiento
                    )
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (plan_id, actividad_id)
                    DO UPDATE SET
                        orden = EXCLUDED.orden,
                        nivel_dificultad_actual = EXCLUDED.nivel_dificultad_actual,
                        modo_ejecucion = EXCLUDED.modo_ejecucion,
                        requiere_acompanamiento = EXCLUDED.requiere_acompanamiento
                    """,
                    (
                        req.plan_id,
                        actividad["id"],
                        orden,
                        dificultad,
                        ejecucion["modo_ejecucion"],
                        ejecucion["requiere_acompanamiento"],
                    ),
                )
                asociado = True

    return {
        "id": str(actividad["id"]),
        "categoria": actividad["tipo"],
        "tipo": actividad["tipo"],
        "nombre": actividad["nombre"],
        "instrucciones": actividad["instrucciones"],
        "nivel_dificultad": actividad["nivel_dificultad"],
        "duracion_estimada": actividad["duracion_estimada"],
        "materiales": (actividad["recursos_multimedia"] or {}).get("materiales", []),
        "asociado": asociado,
    }


@router.post("/api/dashboard/terapeuta/planes/{plan_id}/actividades/{actividad_id}")
def asociar_actividad_a_plan(
    plan_id: str,
    actividad_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden asociar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT pt.id, n.nivel_tea_validado
                FROM planes_terapeuticos pt
                JOIN ninos n ON n.id = pt.nino_id
                WHERE pt.id = %s AND pt.terapeuta_id = %s AND pt.activo = TRUE
                """,
                (plan_id, ter["id"]),
            )
            plan_context = cur.fetchone()
            if not plan_context:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

            cur.execute(
                "SELECT id, nivel_dificultad, duracion_estimada FROM actividades WHERE id = %s AND activo = TRUE",
                (actividad_id,),
            )
            actividad = cur.fetchone()
            if not actividad:
                raise HTTPException(status_code=404, detail="Actividad no encontrada")

            cur.execute(
                """
                SELECT
                    COUNT(*) AS actividades,
                    COALESCE(SUM(COALESCE(a.duracion_estimada, 0)), 0) AS duracion_total,
                    BOOL_OR(pa.actividad_id = %s) AS ya_asociada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                """,
                (actividad_id, plan_id),
            )
            resumen_plan = cur.fetchone()
            ya_asociada = bool(resumen_plan["ya_asociada"])
            if not ya_asociada and int(resumen_plan["actividades"] or 0) >= MAX_ACTIVIDADES_PLAN:
                raise HTTPException(status_code=422, detail="El plan no puede tener mas de 3 actividades")
            duracion_total = int(resumen_plan["duracion_total"] or 0)
            if not ya_asociada and duracion_total + int(actividad["duracion_estimada"] or 0) > MAX_DURACION_PLAN_SEGUNDOS:
                raise HTTPException(status_code=422, detail="La duracion total del plan no puede superar 60 minutos")

            ejecucion = _modo_ejecucion_por_tea(plan_context["nivel_tea_validado"])
            cur.execute(
                "SELECT COALESCE(MAX(orden), 0) + 1 AS orden FROM plan_actividades WHERE plan_id = %s",
                (plan_id,),
            )
            orden = cur.fetchone()["orden"]
            cur.execute(
                """
                INSERT INTO plan_actividades (
                    plan_id, actividad_id, orden, nivel_dificultad_actual,
                    modo_ejecucion, requiere_acompanamiento
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (plan_id, actividad_id) DO NOTHING
                """,
                (
                    plan_id,
                    actividad_id,
                    orden,
                    actividad["nivel_dificultad"],
                    ejecucion["modo_ejecucion"],
                    ejecucion["requiere_acompanamiento"],
                ),
            )

    return {"ok": True, "plan_id": plan_id, "actividad_id": actividad_id}


@router.delete("/api/dashboard/terapeuta/planes/{plan_id}/actividades/{actividad_id}")
def desasociar_actividad_de_plan(
    plan_id: str,
    actividad_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden desasociar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT pt.id FROM planes_terapeuticos pt
                WHERE pt.id = %s AND pt.terapeuta_id = %s AND pt.activo = TRUE
                """,
                (plan_id, ter["id"]),
            )
            plan_context = cur.fetchone()
            if not plan_context:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

            cur.execute(
                "DELETE FROM plan_actividades WHERE plan_id = %s AND actividad_id = %s RETURNING actividad_id",
                (plan_id, actividad_id),
            )
            deleted = cur.fetchone()
            if not deleted:
                raise HTTPException(status_code=404, detail="Actividad no asociada a este plan")

    return {"ok": True, "plan_id": plan_id, "actividad_id": actividad_id}


# ── GET /api/ninos/{nino_id}/plan ─────────────────────────────────────────────

@router.patch("/api/dashboard/terapeuta/planes/{plan_id}/actividades/{actividad_id}/reemplazar/{nueva_actividad_id}")
def reemplazar_actividad_en_plan(
    plan_id: str,
    actividad_id: str,
    nueva_actividad_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden reemplazar actividades")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT pt.id, n.nivel_tea_validado, pa.orden
                FROM planes_terapeuticos pt
                JOIN ninos n ON n.id = pt.nino_id
                JOIN plan_actividades pa ON pa.plan_id = pt.id
                WHERE pt.id = %s
                  AND pt.terapeuta_id = %s
                  AND pt.activo = TRUE
                  AND pa.actividad_id = %s
                """,
                (plan_id, ter["id"], actividad_id),
            )
            plan_context = cur.fetchone()
            if not plan_context:
                raise HTTPException(status_code=404, detail="Actividad original no encontrada en el plan")

            cur.execute(
                "SELECT id, nivel_dificultad, duracion_estimada FROM actividades WHERE id = %s AND activo = TRUE",
                (nueva_actividad_id,),
            )
            nueva = cur.fetchone()
            if not nueva:
                raise HTTPException(status_code=404, detail="Nueva actividad no encontrada")

            if nueva_actividad_id != actividad_id:
                cur.execute(
                    "SELECT 1 FROM plan_actividades WHERE plan_id = %s AND actividad_id = %s",
                    (plan_id, nueva_actividad_id),
                )
                if cur.fetchone():
                    raise HTTPException(status_code=409, detail="La actividad seleccionada ya esta en el plan")

            cur.execute(
                """
                SELECT
                    COALESCE(SUM(COALESCE(a.duracion_estimada, 0)), 0)
                    - COALESCE(MAX(CASE WHEN pa.actividad_id = %s THEN a.duracion_estimada ELSE 0 END), 0)
                    AS duracion_sin_actual
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                """,
                (actividad_id, plan_id),
            )
            duracion_sin_actual = int(cur.fetchone()["duracion_sin_actual"] or 0)
            if duracion_sin_actual + int(nueva["duracion_estimada"] or 0) > MAX_DURACION_PLAN_SEGUNDOS:
                raise HTTPException(status_code=422, detail="La duracion total del plan no puede superar 60 minutos")

            ejecucion = _modo_ejecucion_por_tea(plan_context["nivel_tea_validado"])
            cur.execute(
                """
                UPDATE plan_actividades
                SET actividad_id = %s,
                    nivel_dificultad_actual = %s,
                    modo_ejecucion = %s,
                    requiere_acompanamiento = %s
                WHERE plan_id = %s AND actividad_id = %s
                """,
                (
                    nueva_actividad_id,
                    nueva["nivel_dificultad"],
                    ejecucion["modo_ejecucion"],
                    ejecucion["requiere_acompanamiento"],
                    plan_id,
                    actividad_id,
                ),
            )

    return {
        "ok": True,
        "plan_id": plan_id,
        "actividad_id": nueva_actividad_id,
        "actividad_reemplazada_id": actividad_id,
    }


@router.patch("/api/dashboard/terapeuta/planes/{plan_id}/actividades/{actividad_id}/dificultad")
def actualizar_dificultad_actividad_plan(
    plan_id: str,
    actividad_id: str,
    req: ActualizarDificultadActividadRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden ajustar dificultad")

    nueva = _normalize_dificultad(req.nivel_dificultad)
    niveles = ["Bajo", "Medio", "Alto"]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT
                    pt.nino_id,
                    COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad, pt.nivel_dificultad_actual) AS dificultad_actual,
                    a.nombre AS actividad_nombre
                FROM planes_terapeuticos pt
                JOIN plan_actividades pa ON pa.plan_id = pt.id
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pt.id = %s
                  AND pa.actividad_id = %s
                  AND pt.terapeuta_id = %s
                  AND pt.activo = TRUE
                """,
                (plan_id, actividad_id, ter["id"]),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Actividad no encontrada en el plan activo")

            actual = _normalize_dificultad(row["dificultad_actual"])
            delta = niveles.index(nueva) - niveles.index(actual)
            direccion = "mantener"
            if delta > 0:
                direccion = "aumentar"
            elif delta < 0:
                direccion = "reducir"

            accion = {
                "aumentar": "AUMENTAR_DIFICULTAD",
                "reducir": "REDUCIR_DIFICULTAD",
                "mantener": "MANTENER_DIFICULTAD",
            }[direccion]

            detalle = {
                "actividad_id": actividad_id,
                "actividad_nombre": row["actividad_nombre"],
                "dificultad_actual": actual,
                "dificultad_sugerida": nueva,
                "accion": direccion,
                "origen": req.origen or "manual",
                "observacion": req.observacion,
                "tasa_aciertos": req.tasa_aciertos,
                "muestras": req.muestras,
            }

            cur.execute(
                """
                UPDATE plan_actividades
                SET nivel_dificultad_actual = %s
                WHERE plan_id = %s AND actividad_id = %s
                """,
                (nueva, plan_id, actividad_id),
            )
            cur.execute(
                """
                UPDATE planes_terapeuticos
                SET nivel_dificultad_actual = %s,
                    criterios_progresion = COALESCE(criterios_progresion, '{}'::jsonb)
                        || jsonb_build_object('ultimo_ajuste', %s::jsonb)
                WHERE id = %s
                """,
                (nueva, Json(detalle), plan_id),
            )
            cur.execute(
                """
                INSERT INTO decisiones_clinicas
                    (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, created_at
                """,
                (
                    ter["id"],
                    row["nino_id"],
                    "ajuste_dificultad_actividad",
                    accion,
                    json.dumps(detalle, ensure_ascii=False),
                ),
            )
            decision = cur.fetchone()

    return {
        "ok": True,
        "registrado": True,
        "decision_id": str(decision["id"]),
        "created_at": decision["created_at"].isoformat(),
        **detalle,
    }


@router.patch("/api/dashboard/terapeuta/ninos/{nino_id}/validacion-tea")
def validar_nivel_tea(
    nino_id: str,
    req: ValidarNivelTeaRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden validar nivel TEA")

    nivel_tea = _normalize_nivel_tea(req.nivel_tea)
    ejecucion = _modo_ejecucion_por_tea(nivel_tea)

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET nivel_tea_validado = %s,
                    perfil_validado_por = %s,
                    perfil_validado_at = NOW(),
                    estado_clinico = CASE
                        WHEN estado_clinico IN ('pendiente_asignacion', 'vinculado_terapeuta', 'perfil_clinico_incompleto')
                        THEN 'listo_para_plan'
                        ELSE estado_clinico
                    END
                WHERE id = %s
                  AND terapeuta_id = %s
                  AND activo = TRUE
                RETURNING id, estado_clinico
                """,
                (nivel_tea, ter["id"], nino_id, ter["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="NiÃ±o no encontrado para este terapeuta")

            cur.execute(
                """
                UPDATE plan_actividades pa
                SET modo_ejecucion = %s,
                    requiere_acompanamiento = %s
                FROM planes_terapeuticos pt
                WHERE pt.id = pa.plan_id
                  AND pt.nino_id = %s
                  AND pt.activo = TRUE
                """,
                (ejecucion["modo_ejecucion"], ejecucion["requiere_acompanamiento"], nino_id),
            )

            detalle = {
                "nivel_tea": nivel_tea,
                "requiere_acompanamiento": ejecucion["requiere_acompanamiento"],
                "observacion": req.observacion,
            }
            cur.execute(
                """
                INSERT INTO decisiones_clinicas
                    (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (
                    ter["id"],
                    nino_id,
                    "validacion_nivel_tea",
                    "VALIDAR_NIVEL_TEA",
                    json.dumps(detalle, ensure_ascii=False),
                ),
            )

    return {
        "ok": True,
        "nino_id": nino_id,
        "estado_clinico": nino["estado_clinico"],
        **detalle,
    }


@router.patch("/api/dashboard/terapeuta/planes/{plan_id}/estado")
def actualizar_estado_plan(
    plan_id: str,
    req: ActualizarEstadoPlanRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden aprobar o publicar planes")

    estado = _normalize_estado_plan(req.estado)

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            if estado in ("aprobado", "publicado"):
                cur.execute(
                    """
                    UPDATE ninos n
                    SET perfil_validado_por = %s,
                        perfil_validado_at = COALESCE(n.perfil_validado_at, NOW())
                    FROM planes_terapeuticos pt
                    WHERE pt.nino_id = n.id
                      AND pt.id = %s
                      AND pt.terapeuta_id = %s
                      AND n.nivel_tea_validado IS NOT NULL
                      AND n.activo = TRUE
                    """,
                    (ter["id"], plan_id, ter["id"]),
                )

            resumen = None
            if estado in ("aprobado", "publicado"):
                resumen = _validar_plan_publicable(cur, plan_id, str(ter["id"]))

            cur.execute(
                """
                UPDATE planes_terapeuticos
                SET estado_plan = %s,
                    aprobado_at = CASE
                        WHEN %s IN ('aprobado', 'publicado') THEN COALESCE(aprobado_at, NOW())
                        WHEN %s = 'borrador' THEN NULL
                        ELSE aprobado_at
                    END,
                    publicado_at = CASE
                        WHEN %s = 'publicado' THEN COALESCE(publicado_at, NOW())
                        WHEN %s = 'borrador' THEN NULL
                        ELSE publicado_at
                    END,
                    publicado_para_tutor = (%s = 'publicado')
                WHERE id = %s
                  AND terapeuta_id = %s
                  AND activo = TRUE
                RETURNING id, nino_id, estado_plan, aprobado_at, publicado_at, publicado_para_tutor
                """,
                (estado, estado, estado, estado, estado, estado, plan_id, ter["id"]),
            )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado para este terapeuta")

            if estado == "publicado":
                cur.execute(
                    "UPDATE ninos SET estado_clinico = 'plan_activo' WHERE id = %s",
                    (plan["nino_id"],),
                )

                # Contar planes para saber el número de sesión
                cur.execute(
                    "SELECT COUNT(*) AS total FROM planes_terapeuticos WHERE nino_id = %s",
                    (plan["nino_id"],),
                )
                count_row = cur.fetchone()
                sesion_numero = count_row["total"] if count_row and count_row["total"] else 1
                
                # Obtener nombre del niño
                cur.execute("SELECT nombre FROM ninos WHERE id = %s", (plan["nino_id"],))
                nino_row = cur.fetchone()
                nino_nombre = nino_row["nombre"] if nino_row else "tu hijo/a"
                
                mensaje = f"¡Buenas noticias! El plan terapéutico de tu hijo/a {nino_nombre} para la sesión {sesion_numero} ya está disponible y aprobado."
                _crear_notificacion_tutor(cur, plan["nino_id"], "Nuevo plan terapéutico", mensaje)

            detalle = {
                "plan_id": plan_id,
                "estado": estado,
                "observacion": req.observacion,
                "resumen_reglas": resumen,
            }
            cur.execute(
                """
                INSERT INTO decisiones_clinicas
                    (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (
                    ter["id"],
                    plan["nino_id"],
                    "estado_plan",
                    f"PLAN_{estado.upper()}",
                    json.dumps(detalle, ensure_ascii=False, default=str),
                ),
            )

    return {
        "ok": True,
        "plan_id": str(plan["id"]),
        "nino_id": str(plan["nino_id"]),
        "estado_plan": plan["estado_plan"],
        "aprobado_at": plan["aprobado_at"].isoformat() if plan["aprobado_at"] else None,
        "publicado_at": plan["publicado_at"].isoformat() if plan["publicado_at"] else None,
        "publicado_para_tutor": plan["publicado_para_tutor"],
        "resumen_reglas": resumen,
    }


@router.get("/api/ninos/{nino_id}/plan")
def obtener_plan_activo(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            role = current_user["role"]
            if role in ("padre_tutor", "tutor"):
                cur.execute(
                    "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                tutor = cur.fetchone()
                if not tutor:
                    raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")
                cur.execute(
                    """
                    SELECT
                        pt.id, pt.nombre, pt.nino_id, n.nombre AS nino_nombre,
                        pt.nivel_dificultad_actual, pt.estado_plan,
                        pt.aprobado_at, pt.publicado_at, pt.publicado_para_tutor,
                        pt.limite_actividades, pt.limite_duracion_segundos,
                        n.nivel_tea_validado
                    FROM planes_terapeuticos pt
                    JOIN ninos n ON n.id = pt.nino_id
                    WHERE pt.nino_id = %s
                      AND pt.activo = TRUE
                      AND n.tutor_id = %s
                      AND pt.estado_plan = 'publicado'
                      AND pt.publicado_para_tutor = TRUE
                ORDER BY pt.created_at DESC, pt.fecha_inicio DESC
                    LIMIT 1
                    """,
                    (nino_id, tutor["id"]),
                )
            elif role == "terapeuta":
                cur.execute(
                    "SELECT id FROM terapeutas WHERE usuario_id = %s",
                    (current_user["id"],),
                )
                ter = cur.fetchone()
                if not ter:
                    raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
                cur.execute(
                    """
                    SELECT
                        pt.id, pt.nombre, pt.nino_id, n.nombre AS nino_nombre,
                        pt.nivel_dificultad_actual, pt.estado_plan,
                        pt.aprobado_at, pt.publicado_at, pt.publicado_para_tutor,
                        pt.limite_actividades, pt.limite_duracion_segundos,
                        n.nivel_tea_validado
                    FROM planes_terapeuticos pt
                    JOIN ninos n ON n.id = pt.nino_id
                    WHERE pt.nino_id = %s
                      AND pt.activo = TRUE
                      AND pt.terapeuta_id = %s
                ORDER BY pt.created_at DESC, pt.fecha_inicio DESC
                    LIMIT 1
                    """,
                    (nino_id, ter["id"]),
                )
            else:
                cur.execute(
                    """
                    SELECT
                        pt.id, pt.nombre, pt.nino_id, n.nombre AS nino_nombre,
                        pt.nivel_dificultad_actual, pt.estado_plan,
                        pt.aprobado_at, pt.publicado_at, pt.publicado_para_tutor,
                        pt.limite_actividades, pt.limite_duracion_segundos,
                        n.nivel_tea_validado
                    FROM planes_terapeuticos pt
                    JOIN ninos n ON n.id = pt.nino_id
                    WHERE pt.nino_id = %s AND pt.activo = TRUE
                ORDER BY pt.created_at DESC, pt.fecha_inicio DESC
                    LIMIT 1
                    """,
                    (nino_id,),
                )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan publicado no encontrado")

            # Calcular el número de sesión (total de planes creados para este niño)
            cur.execute(
                "SELECT COUNT(*) AS total FROM planes_terapeuticos WHERE nino_id = %s",
                (nino_id,),
            )
            count_row = cur.fetchone()
            sesion_numero = count_row["total"] if count_row and count_row["total"] else 1

            cur.execute(
                """
                SELECT a.id, a.nombre, a.tipo, a.instrucciones,
                       COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad) AS nivel_dificultad,
                       a.nivel_dificultad AS nivel_catalogo,
                       a.duracion_estimada,
                       a.recursos_multimedia,
                       pa.modo_ejecucion,
                       pa.requiere_acompanamiento,
                       EXISTS (
                           SELECT 1
                           FROM sesiones s
                           JOIN resultados_actividad ra ON ra.sesion_id = s.id
                           WHERE s.plan_id = pa.plan_id
                             AND s.nino_id = %s
                             AND s.estado = 'completada'
                             AND ra.actividad_id = pa.actividad_id
                       ) AS completada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                ORDER BY pa.orden
                """,
                (nino_id, plan["id"]),
            )
            actividades = cur.fetchall()

    return {
        "id": str(plan["id"]),
        "nombre": plan["nombre"],
        "nino_id": str(plan["nino_id"]),
        "nino_nombre": plan["nino_nombre"],
        "nivel_dificultad_actual": plan["nivel_dificultad_actual"],
        "estado_plan": plan["estado_plan"],
        "sesion_numero": sesion_numero,
        "aprobado_at": plan["aprobado_at"].isoformat() if plan["aprobado_at"] else None,
        "publicado_at": plan["publicado_at"].isoformat() if plan["publicado_at"] else None,
        "publicado_para_tutor": plan["publicado_para_tutor"],
        "limite_actividades": plan["limite_actividades"],
        "limite_duracion_segundos": plan["limite_duracion_segundos"],
        "nivel_tea_validado": plan["nivel_tea_validado"],
        "actividades": [
            {
                "id": str(a["id"]),
                "nombre": a["nombre"],
                "tipo": a["tipo"],
                "instrucciones": a["instrucciones"],
                "nivel_dificultad": a["nivel_dificultad"],
                "nivel_catalogo": a["nivel_catalogo"],
                "duracion_estimada": a["duracion_estimada"],
                "materiales": (a["recursos_multimedia"] or {}).get("materiales", []),
                "modo_ejecucion": a["modo_ejecucion"],
                "requiere_acompanamiento": a["requiere_acompanamiento"],
                "completada": a["completada"],
            }
            for a in actividades
        ],
    }


# ── POST /api/sesiones ───────────────────────────────────────────────────────
# Guarda resultados de actividades y registra ajustes adaptativos de dificultad.

@router.post("/api/sesiones")
def crear_sesion(
    req: CrearSesionRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] == "terapeuta":
        raise HTTPException(
            status_code=403,
            detail=(
                "El terapeuta valida y supervisa el plan, pero la ejecucion de "
                "actividades terapeuticas publicadas corresponde al tutor."
            ),
        )
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede registrar ejecuciones de plan")
    if not req.resultados:
        raise HTTPException(status_code=400, detail="La sesion debe incluir resultados")

    for resultado in req.resultados:
        if resultado.repeticiones <= 0:
            raise HTTPException(status_code=400, detail="Las repeticiones deben ser mayores a cero")
        if resultado.aciertos < 0 or resultado.aciertos > resultado.repeticiones:
            raise HTTPException(status_code=400, detail="Los aciertos no pueden exceder las repeticiones")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (current_user["id"],),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT pt.id, pt.nino_id, pt.nivel_dificultad_actual
                FROM planes_terapeuticos pt
                JOIN ninos n ON n.id = pt.nino_id
                WHERE pt.id = %s
                  AND pt.nino_id = %s
                  AND pt.activo = TRUE
                  AND pt.estado_plan = 'publicado'
                  AND pt.publicado_para_tutor = TRUE
                  AND n.tutor_id = %s
                """,
                (req.plan_id, req.nino_id, tutor["id"]),
            )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan publicado no encontrado para este tutor")

            actividad_ids = [resultado.actividad_id for resultado in req.resultados]
            cur.execute(
                """
                SELECT COUNT(*) AS actividades_validas
                FROM plan_actividades
                WHERE plan_id = %s
                  AND actividad_id = ANY(%s::uuid[])
                """,
                (req.plan_id, actividad_ids),
            )
            validas = int(cur.fetchone()["actividades_validas"] or 0)
            if validas != len(set(actividad_ids)):
                raise HTTPException(status_code=400, detail="La sesion incluye actividades que no pertenecen al plan publicado")

            cur.execute(
                """
                SELECT a.id, COALESCE(a.duracion_estimada, 0) AS duracion_estimada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                  AND pa.actividad_id = ANY(%s::uuid[])
                """,
                (req.plan_id, actividad_ids),
            )
            duraciones = {
                str(row["id"]): int(row["duracion_estimada"] or 0)
                for row in cur.fetchall()
            }
            for resultado in req.resultados:
                segundos = float(resultado.tiempo_respuesta or 0)
                if segundos < MIN_TIEMPO_ACTIVIDAD_SEGUNDOS:
                    raise HTTPException(
                        status_code=422,
                        detail={
                            "codigo": "actividad_muy_rapida",
                            "mensaje": "Tiempo minimo de actividad no alcanzado.",
                            "minimo_segundos": MIN_TIEMPO_ACTIVIDAD_SEGUNDOS,
                        },
                    )
                duracion = duraciones.get(str(resultado.actividad_id), 0)
                if duracion > 0 and segundos > duracion:
                    raise HTTPException(
                        status_code=422,
                        detail={
                            "codigo": "tiempo_agotado",
                            "mensaje": "El tiempo estimado de la actividad termino.",
                            "duracion_estimada_segundos": duracion,
                        },
                    )

            cur.execute(
                """
                SELECT
                    s.id AS sesion_id,
                    ra.actividad_id,
                    ra.aciertos,
                    ra.repeticiones,
                    COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad, pt.nivel_dificultad_actual) AS nivel_dificultad_actual
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN planes_terapeuticos pt ON pt.id = s.plan_id
                JOIN actividades a ON a.id = ra.actividad_id
                LEFT JOIN plan_actividades pa
                  ON pa.plan_id = s.plan_id
                 AND pa.actividad_id = ra.actividad_id
                WHERE s.nino_id = %s
                  AND s.plan_id = %s
                  AND s.estado = 'completada'
                  AND ra.actividad_id = ANY(%s::uuid[])
                ORDER BY s.fecha_inicio DESC
                LIMIT 1
                """,
                (req.nino_id, req.plan_id, actividad_ids),
            )
            existente = cur.fetchone()
            if existente:
                total_intentos = int(existente["repeticiones"] or 0)
                total_aciertos = int(existente["aciertos"] or 0)
                tasa = round(total_aciertos / total_intentos, 4) if total_intentos else 0
                return {
                    "ok": True,
                    "ya_registrada": True,
                    "sesion_id": str(existente["sesion_id"]),
                    "total_aciertos": total_aciertos,
                    "total_intentos": total_intentos,
                    "tasa_aciertos": tasa,
                    "nivel_dificultad_recomendado": existente["nivel_dificultad_actual"],
                    "ajustes_dificultad": [],
                }

            cur.execute(
                """
                INSERT INTO sesiones
                    (nino_id, plan_id, fecha_inicio, fecha_fin, estado, sync_at,
                     ejecutado_por_rol, ejecutado_por_usuario_id, origen_registro)
                VALUES (%s, %s, NOW(), NOW(), 'completada', NOW(), %s, %s, 'familia_app')
                RETURNING id
                """,
                (req.nino_id, req.plan_id, current_user["role"], current_user["id"]),
            )
            sesion = cur.fetchone()

            ajustes = []
            total_aciertos = 0
            total_intentos = 0
            for resultado in req.resultados:
                dificultad = _normalize_dificultad(resultado.nivel_dificultad_usado)
                total_aciertos += resultado.aciertos
                total_intentos += resultado.repeticiones
                cur.execute(
                    """
                    INSERT INTO resultados_actividad
                        (sesion_id, actividad_id, tiempo_respuesta, aciertos, repeticiones,
                         nivel_ayuda_requerido, nivel_dificultad_usado, observaciones)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        sesion["id"],
                        resultado.actividad_id,
                        resultado.tiempo_respuesta,
                        resultado.aciertos,
                        resultado.repeticiones,
                        resultado.nivel_ayuda_requerido or 0,
                        dificultad,
                        resultado.observaciones,
                    ),
                )

                ajuste = _evaluar_ajuste_dificultad(
                    cur,
                    req.nino_id,
                    req.plan_id,
                    resultado.actividad_id,
                )
                if ajuste:
                    ajustes.append(ajuste)

    tasa = round(total_aciertos / total_intentos, 4) if total_intentos else 0
    nivel_recomendado = ajustes[-1]["dificultad_sugerida"] if ajustes else plan["nivel_dificultad_actual"]
    return {
        "ok": True,
        "sesion_id": str(sesion["id"]),
        "total_aciertos": total_aciertos,
        "total_intentos": total_intentos,
        "tasa_aciertos": tasa,
        "nivel_dificultad_recomendado": nivel_recomendado,
        "ajustes_dificultad": ajustes,
    }


@router.get("/api/ninos/{nino_id}/ajustes-dificultad")
def obtener_ajustes_dificultad(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden ver ajustes")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT dc.id, dc.accion, dc.observacion, dc.created_at
                FROM decisiones_clinicas dc
                JOIN terapeutas t ON t.id = dc.terapeuta_id
                WHERE dc.nino_id = %s
                  AND t.usuario_id = %s
                  AND dc.accion IN ('AUMENTAR_DIFICULTAD', 'REDUCIR_DIFICULTAD')
                ORDER BY dc.created_at DESC
                LIMIT 20
                """,
                (nino_id, current_user["id"]),
            )
            rows = cur.fetchall()

    ajustes = []
    for row in rows:
        try:
            detalle = json.loads(row["observacion"] or "{}")
        except json.JSONDecodeError:
            detalle = {"observacion": row["observacion"]}
        ajustes.append(
            {
                "id": str(row["id"]),
                "accion": "aumentar" if row["accion"] == "AUMENTAR_DIFICULTAD" else "reducir",
                "created_at": row["created_at"].isoformat(),
                **detalle,
            }
        )
    return {"ajustes": ajustes}


# ── PATCH /api/ninos/{nino_id}/perfil-clinico ─────────────────────────────────

@router.post("/api/sesiones/{sesion_id}/solicitud-ajuste")
def solicitar_ajuste_dificultad(
    sesion_id: str,
    req: SolicitarAjusteDificultadRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Solo el tutor puede solicitar ajustes")

    direccion = (req.accion or "").lower()
    if direccion not in ("aumentar", "reducir"):
        raise HTTPException(status_code=400, detail="Accion de ajuste invalida")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM padres_tutores WHERE usuario_id = %s",
                (current_user["id"],),
            )
            tutor = cur.fetchone()
            if not tutor:
                raise HTTPException(status_code=404, detail="Perfil de tutor no encontrado")

            cur.execute(
                """
                SELECT
                    s.id AS sesion_id,
                    s.nino_id,
                    s.plan_id,
                    n.nombre AS nino_nombre,
                    pt.terapeuta_id,
                    a.nombre AS actividad_nombre,
                    ra.aciertos,
                    ra.repeticiones
                FROM sesiones s
                JOIN ninos n ON n.id = s.nino_id
                JOIN planes_terapeuticos pt ON pt.id = s.plan_id
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN actividades a ON a.id = ra.actividad_id
                WHERE s.id = %s
                  AND s.plan_id = %s
                  AND ra.actividad_id = %s
                  AND n.tutor_id = %s
                  AND s.estado = 'completada'
                """,
                (sesion_id, req.plan_id, req.actividad_id, tutor["id"]),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Sesion o actividad no encontrada para este tutor")

            detalle = {
                "sesion_id": sesion_id,
                "plan_id": req.plan_id,
                "nino_id": str(row["nino_id"]),
                "nino_nombre": row["nino_nombre"],
                "actividad_id": req.actividad_id,
                "actividad_nombre": row["actividad_nombre"],
                "accion": direccion,
                "dificultad_actual": _normalize_dificultad(req.dificultad_actual),
                "dificultad_sugerida": _normalize_dificultad(req.dificultad_sugerida),
                "tasa_aciertos": req.tasa_aciertos,
                "muestras": req.muestras,
                "aciertos": row["aciertos"],
                "intentos": row["repeticiones"],
                "observacion_tutor": req.observacion,
            }
            cur.execute(
                """
                INSERT INTO decisiones_clinicas
                    (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, created_at
                """,
                (
                    row["terapeuta_id"],
                    row["nino_id"],
                    "solicitud_ajuste_dificultad",
                    "SOLICITAR_AUMENTAR_DIFICULTAD" if direccion == "aumentar" else "SOLICITAR_REDUCIR_DIFICULTAD",
                    json.dumps(detalle, ensure_ascii=False),
                ),
            )
            decision = cur.fetchone()
            cur.execute(
                """
                INSERT INTO notificaciones (usuario_id, titulo, mensaje)
                SELECT t.usuario_id, %s, %s
                FROM terapeutas t
                WHERE t.id = %s
                """,
                (
                    "Solicitud de ajuste de dificultad",
                    f"La familia solicito {direccion} la dificultad de {row['actividad_nombre']} para {row['nino_nombre']}.",
                    row["terapeuta_id"],
                ),
            )

    return {
        "ok": True,
        "solicitud_id": str(decision["id"]),
        "created_at": decision["created_at"].isoformat(),
        **detalle,
    }


@router.get("/api/ninos/{nino_id}/sesiones-revision")
def obtener_sesiones_revision(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden revisar sesiones")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                "SELECT id, nombre FROM ninos WHERE id = %s AND terapeuta_id = %s AND activo = TRUE",
                (nino_id, ter["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Nino no encontrado para este terapeuta")

            cur.execute(
                """
                SELECT
                    s.id AS sesion_id,
                    s.plan_id,
                    s.fecha_inicio,
                    ROW_NUMBER() OVER (PARTITION BY s.nino_id ORDER BY s.fecha_inicio ASC) AS sesion_numero,
                    ROUND(CAST(SUM(ra.aciertos) AS NUMERIC) / NULLIF(SUM(ra.repeticiones), 0), 4) AS tasa_aciertos,
                    SUM(ra.aciertos) AS total_aciertos,
                    SUM(ra.repeticiones) AS total_intentos
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN planes_terapeuticos pt ON pt.id = s.plan_id
                WHERE s.nino_id = %s
                  AND pt.terapeuta_id = %s
                  AND s.estado = 'completada'
                GROUP BY s.id, s.plan_id, s.fecha_inicio, s.nino_id
                ORDER BY s.fecha_inicio DESC
                LIMIT 20
                """,
                (nino_id, ter["id"]),
            )
            sesiones = cur.fetchall()
            sesion_ids = [row["sesion_id"] for row in sesiones]

            resultados_por_sesion: Dict[str, List[Dict[str, Any]]] = {}
            if sesion_ids:
                cur.execute(
                    """
                    SELECT
                        ra.sesion_id,
                        ra.actividad_id,
                        a.nombre AS actividad_nombre,
                        a.instrucciones,
                        ra.aciertos,
                        ra.repeticiones,
                        ra.tiempo_respuesta,
                        ra.nivel_ayuda_requerido,
                        ra.nivel_dificultad_usado,
                        ra.observaciones
                    FROM resultados_actividad ra
                    JOIN actividades a ON a.id = ra.actividad_id
                    WHERE ra.sesion_id = ANY(%s::uuid[])
                    ORDER BY ra.timestamp ASC
                    """,
                    (sesion_ids,),
                )
                for row in cur.fetchall():
                    resultados_por_sesion.setdefault(str(row["sesion_id"]), []).append(row)

            cur.execute(
                """
                SELECT id, accion, recomendacion_id, observacion, created_at
                FROM decisiones_clinicas
                WHERE nino_id = %s
                  AND terapeuta_id = %s
                  AND (
                    accion IN ('SOLICITAR_AUMENTAR_DIFICULTAD', 'SOLICITAR_REDUCIR_DIFICULTAD')
                    OR recomendacion_id IN ('resolver_solicitud_ajuste', 'ajuste_dificultad_actividad')
                  )
                ORDER BY created_at DESC
                """,
                (nino_id, ter["id"]),
            )
            decisiones = cur.fetchall()

    solicitudes: Dict[str, Dict[str, Any]] = {}
    resoluciones: Dict[str, Dict[str, Any]] = {}
    for row in decisiones:
        try:
            detalle = json.loads(row["observacion"] or "{}")
        except json.JSONDecodeError:
            detalle = {}
        solicitud_id = detalle.get("solicitud_id")
        if solicitud_id:
            resoluciones[str(solicitud_id)] = {"accion": row["accion"], "created_at": row["created_at"].isoformat(), **detalle}
            continue
        if row["accion"] in ("SOLICITAR_AUMENTAR_DIFICULTAD", "SOLICITAR_REDUCIR_DIFICULTAD"):
            detalle["id"] = str(row["id"])
            detalle["created_at"] = row["created_at"].isoformat()
            detalle["estado"] = "pendiente"
            solicitudes[str(row["id"])] = detalle

    for solicitud_id, resolucion in resoluciones.items():
        if solicitud_id in solicitudes:
            solicitudes[solicitud_id]["estado"] = (
                "aprobada" if resolucion["accion"] in ("AUMENTAR_DIFICULTAD", "REDUCIR_DIFICULTAD") else "rechazada"
            )
            solicitudes[solicitud_id]["resolucion"] = resolucion

    payload_sesiones = []
    for sesion in sesiones:
        sid = str(sesion["sesion_id"])
        actividades = []
        for actividad in resultados_por_sesion.get(sid, []):
            aid = str(actividad["actividad_id"])
            solicitud = next(
                (item for item in solicitudes.values() if item.get("sesion_id") == sid and item.get("actividad_id") == aid),
                None,
            )
            intentos = int(actividad["repeticiones"] or 0)
            aciertos = int(actividad["aciertos"] or 0)
            actividades.append({
                "actividad_id": aid,
                "actividad_nombre": actividad["actividad_nombre"],
                "instrucciones": actividad["instrucciones"],
                "aciertos": aciertos,
                "intentos": intentos,
                "tasa_aciertos": round(aciertos / intentos, 4) if intentos else 0,
                "tiempo_respuesta": actividad["tiempo_respuesta"],
                "nivel_ayuda_requerido": actividad["nivel_ayuda_requerido"],
                "nivel_dificultad_usado": actividad["nivel_dificultad_usado"],
                "observaciones": actividad["observaciones"],
                "solicitud_ajuste": solicitud,
            })
        payload_sesiones.append({
            "id": sid,
            "plan_id": str(sesion["plan_id"]),
            "sesion_numero": int(sesion["sesion_numero"] or 1),
            "fecha": sesion["fecha_inicio"].isoformat(),
            "tasa_aciertos": float(sesion["tasa_aciertos"] or 0),
            "total_aciertos": int(sesion["total_aciertos"] or 0),
            "total_intentos": int(sesion["total_intentos"] or 0),
            "actividades": actividades,
        })

    return {"nino_id": nino_id, "nino_nombre": nino["nombre"], "sesiones": payload_sesiones}


@router.post("/api/dashboard/terapeuta/solicitudes-ajuste/{decision_id}/resolver")
def resolver_solicitud_ajuste(
    decision_id: str,
    req: ResolverSolicitudAjusteRequest,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden resolver solicitudes")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT id, nino_id, accion, observacion
                FROM decisiones_clinicas
                WHERE id = %s
                  AND terapeuta_id = %s
                  AND accion IN ('SOLICITAR_AUMENTAR_DIFICULTAD', 'SOLICITAR_REDUCIR_DIFICULTAD')
                """,
                (decision_id, ter["id"]),
            )
            solicitud = cur.fetchone()
            if not solicitud:
                raise HTTPException(status_code=404, detail="Solicitud no encontrada")
            try:
                detalle = json.loads(solicitud["observacion"] or "{}")
            except json.JSONDecodeError:
                raise HTTPException(status_code=400, detail="Solicitud sin detalle valido")

            sugerida = _normalize_dificultad(detalle.get("dificultad_sugerida"))
            accion = "RECHAZAR_AJUSTE_DIFICULTAD"
            if req.aceptar:
                accion = "AUMENTAR_DIFICULTAD" if detalle.get("accion") == "aumentar" else "REDUCIR_DIFICULTAD"
                cur.execute(
                    """
                    UPDATE plan_actividades
                    SET nivel_dificultad_actual = %s
                    WHERE plan_id = %s AND actividad_id = %s
                    """,
                    (sugerida, detalle.get("plan_id"), detalle.get("actividad_id")),
                )
                cur.execute(
                    """
                    UPDATE planes_terapeuticos
                    SET nivel_dificultad_actual = %s,
                        criterios_progresion = COALESCE(criterios_progresion, '{}'::jsonb)
                            || jsonb_build_object('ultimo_ajuste', %s::jsonb)
                    WHERE id = %s AND terapeuta_id = %s
                    """,
                    (sugerida, Json({**detalle, "solicitud_id": decision_id}), detalle.get("plan_id"), ter["id"]),
                )

            resolucion = {**detalle, "solicitud_id": decision_id, "aceptar": req.aceptar, "observacion_terapeuta": req.observacion}
            cur.execute(
                """
                INSERT INTO decisiones_clinicas
                    (terapeuta_id, nino_id, recomendacion_id, accion, observacion)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, created_at
                """,
                (ter["id"], solicitud["nino_id"], "resolver_solicitud_ajuste", accion, json.dumps(resolucion, ensure_ascii=False)),
            )
            decision = cur.fetchone()

    return {
        "ok": True,
        "decision_id": str(decision["id"]),
        "created_at": decision["created_at"].isoformat(),
        "estado": "aprobada" if req.aceptar else "rechazada",
        **resolucion,
    }


@router.patch("/api/ninos/{nino_id}/perfil-clinico")
def actualizar_perfil_clinico(
    nino_id: str,
    datos: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    campos_permitidos = {"nivel_cognitivo", "diagnostico", "perfil_sensorial",
                         "objetivos_intervencion", "estado_clinico"}
    updates = {k: v for k, v in datos.items() if k in campos_permitidos}
    observaciones = datos.get("observaciones_clinicas")

    if observaciones:
        perfil = updates.get("perfil_sensorial") or {}
        if isinstance(perfil, dict):
            perfil["observaciones_clinicas"] = observaciones
            updates["perfil_sensorial"] = perfil

    if updates.get("objetivos_intervencion") and updates.get("perfil_sensorial"):
        updates["estado_clinico"] = "listo_para_plan"

    if not updates:
        raise HTTPException(status_code=400, detail="Sin campos válidos para actualizar")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            nino_row = cur.fetchone()
            if not nino_row:
                raise HTTPException(status_code=404, detail="Niño no encontrado")
            
            existing_perfil = nino_row["perfil_sensorial"] or {}
            
            if "perfil_sensorial" in updates:
                merged_perfil = dict(existing_perfil)
                merged_perfil.update(updates["perfil_sensorial"])
                updates["perfil_sensorial"] = merged_perfil

            set_clauses = []
            values = []
            for key, value in updates.items():
                if key == "perfil_sensorial":
                    set_clauses.append(f"{key} = %s::jsonb")
                    values.append(Json(value))
                else:
                    set_clauses.append(f"{key} = %s")
                    values.append(value)

            if updates.get("estado_clinico") == "listo_para_plan":
                set_clauses.append("perfil_completado_at = NOW()")

            values.append(nino_id)

            cur.execute(
                f"UPDATE ninos SET {', '.join(set_clauses)} WHERE id = %s RETURNING id, estado_clinico",
                values,
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

    return {
        "ok": True,
        "nino_id": nino_id,
        "estado_clinico": row["estado_clinico"],
        "mensaje": "Perfil clínico guardado correctamente.",
    }


# ── POST /api/dashboard/paciente/{nino_id}/plan/generar ───────────────────────

@router.post("/api/dashboard/paciente/{nino_id}/plan/generar")
def generar_plan_ia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Genera un plan terapéutico para el niño usando la lógica del motor de reglas.
    Versión PMV: asigna las 3 actividades del catálogo respetando el perfil sensorial.
    """
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden generar planes")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id FROM terapeutas WHERE usuario_id = %s",
                (current_user["id"],),
            )
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT
                    id, nombre, fecha_nacimiento, nivel_cognitivo, diagnostico, perfil_sensorial,
                    objetivos_intervencion, estado_clinico, nivel_tea_validado,
                    perfil_validado_at
                FROM ninos
                WHERE id = %s AND activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            perfil_sensorial = nino.get("perfil_sensorial") or {}
            triaje = _triaje_from_perfil(perfil_sensorial)
            requiere_scq = bool(triaje.get("requiere_scq", False))
            tiene_evidencia = _perfil_tiene_evidencia_clinica(
                perfil_sensorial,
                nino.get("diagnostico"),
            )
            perfil_obligatorio = requiere_scq and not tiene_evidencia

            if perfil_obligatorio and (
                not nino.get("nivel_tea_validado") or not nino.get("perfil_validado_at")
            ):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "mensaje": (
                            "Este caso viene de SCQ sin evidencia clinica previa. "
                            "El terapeuta debe validar el perfil clinico y el nivel TEA "
                            "antes de generar el plan terapeutico."
                        )
                    },
                )

            nivel_tea_plan = nino.get("nivel_tea_validado") or _infer_nivel_tea(
                nino.get("diagnostico"),
                perfil_sensorial,
            )
            objetivos = nino.get("objetivos_intervencion") or _objetivos_desde_perfil(perfil_sensorial)
            nino["objetivos_intervencion"] = objetivos
            nino["nivel_tea_validado"] = nivel_tea_plan
            
            # Un perfil se considera completo si tiene fecha de nacimiento, nivel cognitivo/apoyo,
            # y datos de perfil sensorial y objetivos cargados
            if not nino.get("nivel_cognitivo") or not perfil_sensorial or not objetivos:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "mensaje": (
                            "El perfil clínico-funcional del niño está incompleto. "
                            "Por favor, complete el perfil sensorial, el nivel cognitivo y los objetivos "
                            "de intervención antes de generar el plan."
                        )
                    }
                )

            # Verificar si ya tiene plan activo y calcular el siguiente numero de sesion.
            cur.execute(
                "SELECT id FROM planes_terapeuticos WHERE nino_id = %s AND activo = TRUE ORDER BY created_at DESC LIMIT 1",
                (nino_id,),
            )
            existing = cur.fetchone()
            cur.execute(
                "SELECT COUNT(*) AS total FROM planes_terapeuticos WHERE nino_id = %s",
                (nino_id,),
            )
            total_planes = int((cur.fetchone() or {}).get("total") or 0)
            siguiente_sesion = total_planes + 1

            # Procesar el motor adaptativo Random Forest (WHEN de la Historia de Usuario)
            # El motor procesa edad, nivel_cognitivo (apoyo), perfil_sensorial, y objetivos (habilidades)
            dificultad_ia, confianza = motor_adaptativo.predecir_dificultad(nino)

            # Mapeo de la dificultad del motor (Básico, Intermedio, Avanzado) al ENUM de la base de datos (Bajo, Medio, Alto)
            map_dificultad_db = {
                "Básico": "Bajo",
                "Intermedio": "Medio",
                "Avanzado": "Alto",
            }
            nivel_dificultad_db = map_dificultad_db.get(dificultad_ia, "Medio")

            if existing:
                cur.execute(
                    """
                    UPDATE planes_terapeuticos
                    SET activo = FALSE,
                        fecha_fin = CURRENT_DATE
                    WHERE id = %s
                    """,
                    (existing["id"],),
                )
            cur.execute(
                """
                INSERT INTO planes_terapeuticos
                    (nombre, nino_id, terapeuta_id, fecha_inicio, nivel_dificultad_actual,
                     criterios_progresion, activo, estado_plan, publicado_para_tutor)
                VALUES (%s, %s, %s, CURRENT_DATE, %s, %s::jsonb, TRUE, 'borrador', FALSE)
                RETURNING id
                """,
                (
                    f"Plan IA - Sesion {siguiente_sesion} - {nino['nombre']}",
                    nino_id,
                    ter["id"],
                    nivel_dificultad_db,
                    '{"umbralAciertos": 0.8, "sesionesConsecutivas": 3}',
                ),
            )
            plan = cur.fetchone()

            # Actualizar el estado clínico del niño a 'plan_activo' para coherencia global
            cur.execute(
                """
                UPDATE ninos
                SET estado_clinico = 'listo_para_plan'
                WHERE id = %s
                """,
                (nino_id,),
            )

            cur.execute(
                """
                SELECT id, tipo, nombre, instrucciones, nivel_dificultad, duracion_estimada, recursos_multimedia
                FROM actividades
                WHERE activo = TRUE
                """
            )
            catalogo = cur.fetchall()
            if not catalogo:
                raise HTTPException(
                    status_code=422,
                    detail={"mensaje": "No hay actividades ocupacionales configuradas para generar el plan."},
                )

            acts = sorted(
                catalogo,
                key=lambda a: (
                    -_score_actividad(a, nino, nivel_dificultad_db),
                    a["nombre"],
                ),
            )[: min(3, len(catalogo))]
            ejecucion = _modo_ejecucion_por_tea(nivel_tea_plan)
            for i, act in enumerate(acts, start=1):
                cur.execute(
                    """
                    INSERT INTO plan_actividades (
                        plan_id, actividad_id, orden, nivel_dificultad_actual,
                        modo_ejecucion, requiere_acompanamiento
                    )
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (plan_id, actividad_id) DO NOTHING
                    """,
                    (
                        plan["id"],
                        act["id"],
                        i,
                        nivel_dificultad_db,
                        ejecucion["modo_ejecucion"],
                        ejecucion["requiere_acompanamiento"],
                    ),
                )

    return {
        "mensaje": f"Sesion {siguiente_sesion} generada con exito",
        "plan_id": str(plan["id"]),
        "nino_id": nino_id,
        "sesion_numero": siguiente_sesion,
        "dificultad_inicial": dificultad_ia,
        "confianza_ia": confianza,
        "estado_plan": "borrador",
        "requiere_revision_terapeuta": True,
        "perfil_clinico_obligatorio": perfil_obligatorio,
        "nivel_tea_usado": nivel_tea_plan,
    }


# ── GET /api/ninos/{nino_id} ─────────────────────────────────────────────────────
# Perfil completo del niño (usado por TherapeuticProfileScreen)

@router.get("/api/ninos/{nino_id}")
def obtener_perfil_nino(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    n.id, n.nombre, n.fecha_nacimiento, n.nivel_cognitivo,
                    n.diagnostico, n.perfil_sensorial, n.objetivos_intervencion,
                    n.estado_clinico, n.documento_diagnostico,
                    n.nivel_tea_validado, n.perfil_validado_at,
                    pt.id AS plan_activo_id,
                    pt.estado_plan AS plan_estado
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                WHERE n.id = %s AND n.activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

    sensorial = nino["perfil_sensorial"] or {}
    triaje = _triaje_from_perfil(sensorial)
    scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
    return {
        "id": str(nino["id"]),
        "nombre": nino["nombre"],
        "edad": _calc_edad(nino["fecha_nacimiento"]),
        "diagnostico": nino["diagnostico"],
        "nivel_cognitivo": nino["nivel_cognitivo"] or "Medio",
        "perfil_sensorial": sensorial,
        "objetivos_intervencion": nino["objetivos_intervencion"] or [],
        "intereses": sensorial.get("intereses", []),
        "estimulos_aversivos": sensorial.get("estimulosAversivos", {}),
        "rutinas_regulacion": sensorial.get("rutinas_regulacion", []),
        "documentos_clinicos": sensorial.get("documentos_clinicos", {}),
        "medicacion_actual": sensorial.get("medicacion_actual"),
        "requiere_scq": triaje.get("requiere_scq", False),
        "scq_completado": triaje.get("scq_completado", False),
        "scq_autorizado_envio": triaje.get("autorizado_envio_terapeuta", False),
        "scq_puntaje": scq.get("puntaje_total"),
        "scq_nivel": scq.get("nivel_indicio"),
        "tiene_evidencia_clinica": _perfil_tiene_evidencia_clinica(
            sensorial,
            nino["diagnostico"],
        ),
        "documento_diagnostico": nino["documento_diagnostico"],
        "plan_activo_id": str(nino["plan_activo_id"]) if nino["plan_activo_id"] else None,
        "plan_estado": nino["plan_estado"],
        "estado_clinico": nino["estado_clinico"] or "pendiente_asignacion",
        "nivel_tea_validado": nino["nivel_tea_validado"],
        "perfil_validado": nino["perfil_validado_at"] is not None,
        "perfil_validado_at": nino["perfil_validado_at"].isoformat() if nino["perfil_validado_at"] else None,
    }


# ── GET /api/ninos/{nino_id}/progreso ────────────────────────────────────────────
# Métricas de progreso clínico (usado por ProgressScreen)

@router.get("/api/ninos/{nino_id}/progreso")
def obtener_progreso(
    nino_id: str,
    periodo: str = "Esta semana",
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # Filtro de fecha según período
            if periodo == "Esta semana":
                fecha_desde = "date_trunc('week', NOW())"
            elif periodo == "Este mes":
                fecha_desde = "date_trunc('month', NOW())"
            else:
                fecha_desde = "'2000-01-01'::date"

            cur.execute(
                f"""
                SELECT
                    COUNT(DISTINCT s.id) AS sesiones_completadas,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa_aciertos
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s
                  AND s.fecha_inicio >= {fecha_desde}
                  AND s.estado = 'completada'
                """,
                (nino_id,),
            )
            resumen = cur.fetchone()

            # Historia de aciertos por sesión (últimas 8)
            cur.execute(
                """
                SELECT
                    s.id,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s AND s.estado = 'completada'
                GROUP BY s.id, s.fecha_inicio
                ORDER BY s.fecha_inicio DESC
                LIMIT 8
                """,
                (nino_id,),
            )
            historia_rows = cur.fetchall()

    sesiones = resumen["sesiones_completadas"] or 0
    tasa = float(resumen["tasa_aciertos"]) if resumen["tasa_aciertos"] else 0.0
    historia = [float(r["tasa"]) for r in reversed(historia_rows) if r["tasa"] is not None]
    if not historia:
        historia = [0.0]

    # Adherencia simplificada: proporción de sesiones completadas vs esperadas (objetivo 5/semana)
    adherencia = min(1.0, sesiones / 5.0) if periodo == "Esta semana" else min(1.0, tasa)

    return {
        "sesiones_completadas": sesiones,
        "tasa_aciertos": tasa,
        "adherencia": adherencia,
        "historia_aciertos": historia,
    }


# ── GET /api/ia/asistente/{nino_id} ─────────────────────────────────────────────
# Datos para el Asistente IA (usado por IAAssistantScreen)

@router.get("/api/ia/asistente/{nino_id}")
def obtener_asistente_ia(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT n.nombre, n.nivel_cognitivo, n.perfil_sensorial
                FROM ninos n
                WHERE n.id = %s AND n.activo = TRUE
                """,
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            # Obtener actividades del plan activo para generar recomendaciones
            cur.execute(
                """
                SELECT
                    a.id,
                    a.nombre,
                    a.tipo,
                    a.instrucciones,
                    COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad) AS nivel_dificultad,
                    a.duracion_estimada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                JOIN planes_terapeuticos pt ON pt.id = pa.plan_id
                WHERE pt.nino_id = %s AND pt.activo = TRUE
                ORDER BY pa.orden
                """,
                (nino_id,),
            )
            actividades = cur.fetchall()

            # Última sesión para calcular carga cognitiva
            cur.execute(
                """
                SELECT
                    ROUND(CAST(SUM(ra.aciertos) AS NUMERIC) / NULLIF(SUM(ra.repeticiones), 0), 4) AS tasa,
                    AVG(ra.tiempo_respuesta) AS tiempo_promedio
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s AND s.estado = 'completada'
                  AND s.fecha_inicio >= NOW() - INTERVAL '7 days'
                """,
                (nino_id,),
            )
            ultima = cur.fetchone()

    tasa = float(ultima["tasa"]) if ultima and ultima["tasa"] else 0.65
    tiempo_prom = float(ultima["tiempo_promedio"]) if ultima and ultima["tiempo_promedio"] else 3.0
    # Carga cognitiva inversa a la tasa de aciertos
    carga = round(max(0.1, min(0.95, 1.0 - tasa)), 2)
    calma = round(min(10.0, 10.0 * tasa), 1)

    # Recomendaciones basadas en las actividades del plan
    recomendaciones = []
    for act in actividades:
        confianza = round(tasa * 0.9 + 0.05, 2) if tasa > 0 else 0.70
        recomendaciones.append({
            "id": str(act["id"]),
            "actividad": act["nombre"],
            "justificacion": act["instrucciones"] or f"Actividad de tipo {act['tipo']} adecuada al perfil del paciente.",
            "confianza": confianza,
            "fecha_respuesta": datetime.utcnow().isoformat(),
            "estado": "PENDIENTE",
            "observacion": None,
        })

    # Plan de sesión sugerido
    plan_sesion = []
    for i, act in enumerate(actividades):
        duracion = act["duracion_estimada"] or 300
        plan_sesion.append({
            "id": str(act["id"]),
            "title": act["nombre"],
            "description": act["instrucciones"] or act["tipo"],
            "duration": f"{duracion // 60} min",
            "has_scanning": False,
        })

    return {
        "nino_id": nino_id,
        "nino_nombre": nino["nombre"],
        "analisis_cognitivo": {
            "carga_cognitiva": carga,
            "foco_estimado": f"{int(15 * tasa)} min",
            "nivel_calma": calma,
        },
        "recomendaciones": recomendaciones,
        "plan_sesion": plan_sesion,
    }
