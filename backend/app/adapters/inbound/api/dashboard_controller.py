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
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional
from uuid import UUID

import psycopg2
from psycopg2.extras import Json, RealDictCursor
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
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

def _config_notificaciones_usuario(cur, usuario_id) -> Dict[str, Any]:
    cur.execute(
        """
        SELECT
            canal_preferido, alertas_clinicas, recordatorios_familia,
            COALESCE(umbral_inactividad_dias, 7) AS umbral_inactividad_dias
        FROM configuracion_notificaciones
        WHERE usuario_id = %s
        """,
        (usuario_id,),
    )
    row = cur.fetchone()
    if not row:
        return {
            "canal_preferido": "in_app",
            "alertas_clinicas": True,
            "recordatorios_familia": True,
            "umbral_inactividad_dias": 7,
        }
    return {
        "canal_preferido": row["canal_preferido"] or "in_app",
        "alertas_clinicas": row["alertas_clinicas"] is not False,
        "recordatorios_familia": row["recordatorios_familia"] is not False,
        "umbral_inactividad_dias": int(row["umbral_inactividad_dias"] or 7),
    }


def _crear_notificacion_usuario(
    cur,
    usuario_id,
    titulo: str,
    mensaje: str,
    *,
    tipo: str = "general",
    canal: str = "in_app",
    entidad_tipo: Optional[str] = None,
    entidad_id: Optional[str] = None,
    payload: Optional[Dict[str, Any]] = None,
):
    cur.execute(
        """
        INSERT INTO notificaciones (
            usuario_id, titulo, mensaje, tipo, canal, estado_envio,
            entidad_tipo, entidad_id, payload, delivered_at
        )
        VALUES (%s, %s, %s, %s, %s, 'enviada', %s, %s, %s::jsonb, NOW())
        RETURNING id
        """,
        (
            usuario_id,
            titulo,
            mensaje,
            tipo,
            canal,
            entidad_tipo,
            entidad_id,
            Json(payload or {}),
        ),
    )
    row = cur.fetchone()
    return row["id"] if row else None


def _json_auditoria(payload: Optional[Dict[str, Any]]) -> Json:
    return Json(payload or {}, dumps=lambda value: json.dumps(value, ensure_ascii=False, default=str))


def _registrar_auditoria(
    cur,
    *,
    usuario_id,
    rol_usuario: str,
    accion: str,
    entidad_afectada: str,
    entidad_id,
    nino_id=None,
    payload_anterior: Optional[Dict[str, Any]] = None,
    payload_nuevo: Optional[Dict[str, Any]] = None,
):
    cur.execute(
        """
        INSERT INTO logs_auditoria (
            usuario_id, rol_usuario, accion, entidad_afectada, entidad_id,
            nino_id, payload_anterior, payload_nuevo, fecha_evento
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s::jsonb, NOW())
        RETURNING id
        """,
        (
            usuario_id,
            rol_usuario,
            accion,
            entidad_afectada,
            str(entidad_id),
            str(nino_id) if nino_id else None,
            _json_auditoria(payload_anterior),
            _json_auditoria(payload_nuevo),
        ),
    )
    row = cur.fetchone()
    return row["id"] if row else None


def _registrar_log_alerta(cur, usuario_id, accion: str, alerta_id, payload: Dict[str, Any]):
    return _registrar_auditoria(
        cur,
        usuario_id=usuario_id,
        rol_usuario="sistema",
        accion=accion,
        entidad_afectada="alertas_clinicas",
        entidad_id=alerta_id,
        nino_id=payload.get("nino_id"),
        payload_nuevo=payload,
    )


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
    consentimiento_datos_sensibles: Optional[bool] = False
    consentimiento_informado_version: Optional[str] = "LPDP-29733-v1"
    acepta_uso_no_diagnostico: Optional[bool] = False


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
    client_event_id: Optional[UUID] = None


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

class ActualizarConfigNotificacionesRequest(BaseModel):
    canal_preferido: Optional[str] = "in_app"
    alertas_clinicas: Optional[bool] = True
    recordatorios_familia: Optional[bool] = True
    umbral_inactividad_dias: Optional[int] = 7


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


def _contiene_datos_sensibles(req: RegistrarNinoRequest) -> bool:
    return bool(
        (req.diagnostico or "").strip()
        or (req.medicacion_actual or "").strip()
        or any(bool(v) for v in (req.documentos_clinicos or {}).values())
        or any(bool(v) for v in (req.hitos or {}).values())
        or any(bool(v) for v in (req.sensorial or {}).values())
        or bool(req.rutinas_regulacion)
        or bool(req.estimulos_aversivos)
    )


def _validar_consentimiento_sensible(req: RegistrarNinoRequest):
    if _contiene_datos_sensibles(req) and not req.consentimiento_datos_sensibles:
        raise HTTPException(
            status_code=422,
            detail={
                "codigo": "consentimiento_datos_sensibles_requerido",
                "mensaje": (
                    "Debes confirmar el consentimiento informado para tratar datos "
                    "sensibles del niño antes de registrar o actualizar el perfil."
                ),
            },
        )
    if not req.acepta_uso_no_diagnostico:
        raise HTTPException(
            status_code=422,
            detail={
                "codigo": "aviso_no_diagnostico_requerido",
                "mensaje": (
                    "Debes confirmar que RimAI opera como herramienta de apoyo "
                    "clinico y no como diagnostico clinico."
                ),
            },
        )


def _registrar_consentimiento(
    cur,
    *,
    nino_id,
    tutor_id,
    usuario_id,
    version: Optional[str],
    finalidad: str,
    payload: Optional[Dict[str, Any]] = None,
):
    cur.execute(
        """
        INSERT INTO consentimientos_informados (
            nino_id, tutor_id, usuario_id, version, finalidad,
            datos_sensibles, aceptado, payload
        )
        VALUES (%s, %s, %s, %s, %s, TRUE, TRUE, %s::jsonb)
        RETURNING id, accepted_at
        """,
        (
            nino_id,
            tutor_id,
            usuario_id,
            version or "LPDP-29733-v1",
            finalidad,
            _json_auditoria(payload),
        ),
    )
    return cur.fetchone()


def _tiene_consentimiento_activo(cur, nino_id) -> bool:
    cur.execute(
        """
        SELECT 1
        FROM consentimientos_informados
        WHERE nino_id = %s
          AND aceptado = TRUE
          AND revoked_at IS NULL
        LIMIT 1
        """,
        (nino_id,),
    )
    return cur.fetchone() is not None


def _autorizar_acceso_nino(nino_id: str, current_user: Dict[str, Any]):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT terapeuta_id, tutor_id FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            acceso = cur.fetchone()
            if not acceso:
                raise HTTPException(status_code=404, detail="Niño no encontrado")
            if current_user["role"] == "terapeuta":
                cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
                ter = cur.fetchone()
                if not ter or acceso["terapeuta_id"] != ter["id"]:
                    raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            elif current_user["role"] in ("padre_tutor", "tutor", "padre"):
                cur.execute("SELECT id FROM padres_tutores WHERE usuario_id = %s", (current_user["id"],))
                tutor = cur.fetchone()
                if not tutor or acceso["tutor_id"] != tutor["id"]:
                    raise HTTPException(status_code=403, detail="Acceso denegado al nino")
            elif current_user["role"] != "admin":
                raise HTTPException(status_code=403, detail="Acceso denegado")


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


def _list_from_profile(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, tuple):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, dict):
        items = []
        for key, item in value.items():
            if isinstance(item, list):
                items.extend(str(v).strip() for v in item if str(v).strip())
            elif item:
                items.append(str(key).strip())
        return [item for item in items if item]
    text = str(value).strip()
    return [text] if text else []


def _json_dict(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def _build_recomendaciones_actividad(nino: Dict[str, Any], actividad: Dict[str, Any]) -> List[str]:
    perfil = _json_dict(nino.get("perfil_sensorial"))
    recursos = _json_dict(actividad.get("recursos_multimedia"))
    recomendaciones = _list_from_profile(recursos.get("recomendaciones"))

    if actividad.get("requiere_acompanamiento"):
        recomendaciones.append("Acompana al nino durante toda la actividad y modela la primera respuesta.")
    else:
        recomendaciones.append("Permite que el nino intente la actividad con supervision cercana.")

    nivel = int(nino.get("nivel_tea_validado") or 0)
    if nivel >= 2:
        recomendaciones.append("Usa consignas breves, pausas predecibles y ayuda gradual si aparece frustracion.")

    nivel_cognitivo = str(nino.get("nivel_cognitivo") or "").lower()
    if "bajo" in nivel_cognitivo:
        recomendaciones.append("Divide la consigna en pasos pequenos y confirma comprension antes de avanzar.")
    elif "alto" in nivel_cognitivo:
        recomendaciones.append("Ofrece una meta clara y deja espacio para resolver con mayor autonomia.")

    intereses = _list_from_profile(perfil.get("intereses"))
    if intereses:
        recomendaciones.append(f"Conecta la consigna con intereses del nino: {', '.join(intereses[:3])}.")

    aversivos = _list_from_profile(
        perfil.get("estimulosAversivos") or perfil.get("estimulos_aversivos")
    )
    if aversivos:
        recomendaciones.append(f"Reduce o anticipa estimulos aversivos registrados: {', '.join(aversivos[:3])}.")

    rutinas = _list_from_profile(perfil.get("rutinas_regulacion"))
    if rutinas:
        recomendaciones.append(f"Inicia o cierra con una rutina de regulacion conocida: {rutinas[0]}.")

    duracion = actividad.get("duracion_estimada")
    if duracion:
        minutos = max(1, int(duracion) // 60)
        recomendaciones.append(f"Manten la actividad dentro de {minutos} min y registra si requiere mas tiempo.")

    seen = set()
    unicas = []
    for item in recomendaciones:
        clean = str(item).strip()
        key = clean.lower()
        if clean and key not in seen:
            seen.add(key)
            unicas.append(clean)
    return unicas[:6]


def _safe_float(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _pct(value: float) -> str:
    return f"{value * 100:.1f}%"


def _build_tendencia(sesiones: List[Dict[str, Any]]) -> Dict[str, Any]:
    tasas = [s["tasa_aciertos"] for s in sesiones if s["total_intentos"] > 0]
    if len(tasas) < 2:
        return {
            "direccion": "sin_datos_suficientes",
            "variacion_tasa_aciertos": 0.0,
            "primer_valor": tasas[0] if tasas else 0.0,
            "ultimo_valor": tasas[-1] if tasas else 0.0,
        }
    variacion = round(tasas[-1] - tasas[0], 4)
    if variacion > 0.05:
        direccion = "mejora"
    elif variacion < -0.05:
        direccion = "descenso"
    else:
        direccion = "estable"
    return {
        "direccion": direccion,
        "variacion_tasa_aciertos": variacion,
        "primer_valor": tasas[0],
        "ultimo_valor": tasas[-1],
    }


def _pdf_escape(text: Any) -> str:
    clean = str(text).replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return clean.encode("latin-1", "replace").decode("latin-1")


def _build_simple_pdf(lines: List[str]) -> bytes:
    page_chunks = [lines[i:i + 42] for i in range(0, max(len(lines), 1), 42)]
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "",  # pages placeholder
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    page_ids = []
    for chunk in page_chunks:
        content_lines = ["BT", "/F1 10 Tf", "50 790 Td", "14 TL"]
        for line in chunk:
            content_lines.append(f"({_pdf_escape(line)}) Tj")
            content_lines.append("T*")
        content_lines.append("ET")
        stream = "\n".join(content_lines)
        content_obj_id = len(objects) + 2
        page_obj = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
            f"/Resources << /Font << /F1 3 0 R >> >> /Contents {content_obj_id} 0 R >>"
        )
        page_ids.append(len(objects) + 1)
        objects.append(page_obj)
        objects.append(f"<< /Length {len(stream.encode('latin-1', 'replace'))} >>\nstream\n{stream}\nendstream")

    kids = " ".join(f"{page_id} 0 R" for page_id in page_ids)
    objects[1] = f"<< /Type /Pages /Kids [{kids}] /Count {len(page_ids)} >>"

    output = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode("ascii"))
        output.extend(obj.encode("latin-1", "replace"))
        output.extend(b"\nendobj\n")

    xref_pos = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    output.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    output.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_pos}\n%%EOF\n".encode("ascii")
    )
    return bytes(output)


def _build_reporte_pdf(reporte: Dict[str, Any]) -> bytes:
    nino = reporte["nino"]
    resumen = reporte["resumen"]
    tendencia = reporte["tendencias"]
    periodo = reporte["periodo"]
    lines = [
        "RimAI - Reporte terapeutico",
        f"Paciente: {nino['nombre']} | Edad: {nino['edad']} | Nivel TEA: {nino.get('nivel_tea_validado') or 'pendiente'}",
        f"Periodo: {periodo['inicio']} a {periodo['fin']}",
        f"Generado: {reporte['generado_at']}",
        "",
        "Resumen",
        f"Sesiones completadas: {resumen['sesiones_completadas']}",
        f"Actividades registradas: {resumen['actividades_registradas']}",
        f"Tasa global de aciertos: {_pct(resumen['tasa_aciertos_global'])}",
        f"Cumplimiento: {_pct(resumen['cumplimiento_global'])}",
        f"Tiempo promedio: {resumen['promedio_tiempo_segundos']:.1f} segundos",
        f"Nivel de ayuda promedio: {resumen['promedio_ayuda']:.1f}",
        "",
        "Tendencias",
        f"Direccion: {tendencia['direccion']}",
        f"Variacion tasa aciertos: {_pct(tendencia['variacion_tasa_aciertos'])}",
        "",
        "Progreso por habilidad",
    ]
    for item in reporte["progreso_por_habilidad"]:
        lines.append(
            f"- {item['habilidad']}: {_pct(item['tasa_aciertos'])}, "
            f"{item['actividades']} actividades, ayuda {item['promedio_ayuda']:.1f}"
        )
    lines.extend(["", "Sesiones"])
    for sesion in reporte["sesiones"]:
        lines.append(
            f"- {sesion['fecha']}: {_pct(sesion['tasa_aciertos'])}, "
            f"{sesion['total_aciertos']}/{sesion['total_intentos']} aciertos, "
            f"ayuda {sesion['promedio_ayuda']:.1f}"
        )
    lines.extend(["", "Observaciones"])
    if reporte["observaciones"]:
        for obs in reporte["observaciones"]:
            lines.append(f"- {obs['fecha']} | {obs['actividad']}: {obs['observacion']}")
    else:
        lines.append("Sin observaciones registradas en el periodo.")
    return _build_simple_pdf(lines)


def _emitir_alerta_clinica(
    cur,
    nino: Dict[str, Any],
    *,
    tipo: str,
    severidad: str,
    titulo: str,
    mensaje: str,
    metricas: Dict[str, Any],
    recordatorio_familia: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    dedupe_key = f"{tipo}:{nino['id']}:{datetime.utcnow().date().isoformat()}"
    ter_config = _config_notificaciones_usuario(cur, nino["terapeuta_usuario_id"])
    tutor_config = _config_notificaciones_usuario(cur, nino["tutor_usuario_id"]) if nino.get("tutor_usuario_id") else {
        "canal_preferido": "in_app",
        "recordatorios_familia": False,
    }
    canal = ter_config["canal_preferido"]

    cur.execute(
        """
        INSERT INTO alertas_clinicas (
            nino_id, terapeuta_id, tutor_id, tipo, severidad, titulo,
            mensaje, canal, estado_envio, metricas, dedupe_key
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'registrada', %s::jsonb, %s)
        ON CONFLICT (dedupe_key) DO NOTHING
        RETURNING id, created_at
        """,
        (
            nino["id"],
            nino["terapeuta_id"],
            nino.get("tutor_id"),
            tipo,
            severidad,
            titulo,
            mensaje,
            canal,
            Json(metricas),
            dedupe_key,
        ),
    )
    alerta = cur.fetchone()
    if not alerta:
        return None

    payload = {
        "alerta_id": str(alerta["id"]),
        "nino_id": str(nino["id"]),
        "nino_nombre": nino["nombre"],
        "tipo": tipo,
        "severidad": severidad,
        "metricas": metricas,
    }

    notificacion_terapeuta_id = None
    if ter_config["alertas_clinicas"]:
        notificacion_terapeuta_id = _crear_notificacion_usuario(
            cur,
            nino["terapeuta_usuario_id"],
            titulo,
            mensaje,
            tipo="alerta_clinica",
            canal=canal,
            entidad_tipo="alertas_clinicas",
            entidad_id=str(alerta["id"]),
            payload=payload,
        )

    notificacion_familia_id = None
    if recordatorio_familia and nino.get("tutor_usuario_id") and tutor_config["recordatorios_familia"]:
        notificacion_familia_id = _crear_notificacion_usuario(
            cur,
            nino["tutor_usuario_id"],
            "Recordatorio de actividad terapeutica",
            recordatorio_familia,
            tipo="recordatorio_familia",
            canal=tutor_config["canal_preferido"],
            entidad_tipo="alertas_clinicas",
            entidad_id=str(alerta["id"]),
            payload=payload,
        )

    cur.execute(
        """
        UPDATE alertas_clinicas
        SET estado_envio = 'enviada',
            notificacion_terapeuta_id = %s,
            notificacion_familia_id = %s,
            updated_at = NOW()
        WHERE id = %s
        """,
        (notificacion_terapeuta_id, notificacion_familia_id, alerta["id"]),
    )
    _registrar_log_alerta(cur, nino["terapeuta_usuario_id"], "ALERTA_CLINICA_GENERADA", alerta["id"], payload)
    return {
        "id": str(alerta["id"]),
        "tipo": tipo,
        "severidad": severidad,
        "titulo": titulo,
        "mensaje": mensaje,
        "created_at": alerta["created_at"].isoformat() if alerta["created_at"] else None,
    }


def _predecir_riesgo_abandono(
    cur,
    nino: Dict[str, Any],
    *,
    umbral_inactividad_dias: int = 7,
) -> Dict[str, Any]:
    cur.execute(
        """
        SELECT
            MAX(fecha_inicio) AS ultima_sesion,
            COUNT(*) FILTER (WHERE fecha_inicio >= NOW() - INTERVAL '14 days') AS sesiones_14,
            COUNT(*) FILTER (WHERE fecha_inicio >= NOW() - INTERVAL '30 days') AS sesiones_30,
            COUNT(*) FILTER (
                WHERE fecha_inicio >= NOW() - INTERVAL '30 days'
                  AND estado = 'completada'
            ) AS completadas_30,
            COUNT(*) FILTER (
                WHERE fecha_inicio >= NOW() - INTERVAL '30 days'
                  AND estado = 'interrumpida'
            ) AS interrumpidas_30
        FROM sesiones
        WHERE nino_id = %s
        """,
        (nino["id"],),
    )
    sesiones = cur.fetchone() or {}
    ultima = sesiones.get("ultima_sesion")
    publicado_at = nino.get("plan_publicado_at") or datetime.utcnow()
    dias_sin_actividad = (
        int((datetime.utcnow() - ultima.replace(tzinfo=None)).days)
        if ultima else
        int((datetime.utcnow() - publicado_at.replace(tzinfo=None)).days)
    )

    cur.execute(
        """
        SELECT
            COUNT(pa.actividad_id) AS total_plan,
            COUNT(pa.actividad_id) FILTER (
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM sesiones s
                    JOIN resultados_actividad ra ON ra.sesion_id = s.id
                    WHERE s.plan_id = pa.plan_id
                      AND s.nino_id = %s
                      AND s.estado = 'completada'
                      AND ra.actividad_id = pa.actividad_id
                )
            ) AS pendientes
        FROM plan_actividades pa
        WHERE pa.plan_id = %s
        """,
        (nino["id"], nino["plan_id"]),
    )
    pendientes_row = cur.fetchone() or {}
    total_plan = int(pendientes_row.get("total_plan") or 0)
    pendientes = int(pendientes_row.get("pendientes") or 0)
    proporcion_pendiente = round(pendientes / total_plan, 4) if total_plan else 0.0

    sesiones_30 = int(sesiones.get("sesiones_30") or 0)
    sesiones_14 = int(sesiones.get("sesiones_14") or 0)
    interrumpidas_30 = int(sesiones.get("interrumpidas_30") or 0)
    completadas_30 = int(sesiones.get("completadas_30") or 0)
    tasa_interrupcion = round(interrumpidas_30 / sesiones_30, 4) if sesiones_30 else 0.0

    score = 0
    factores = []
    if dias_sin_actividad > umbral_inactividad_dias * 2:
        score += 3
        factores.append("inactividad_prolongada")
    elif dias_sin_actividad > umbral_inactividad_dias:
        score += 2
        factores.append("inactividad_mayor_umbral")

    if sesiones_14 == 0:
        score += 2
        factores.append("sin_sesiones_ultimos_14_dias")
    elif sesiones_14 < 2:
        score += 1
        factores.append("baja_frecuencia_reciente")

    if sesiones_30 >= 2 and tasa_interrupcion >= 0.4:
        score += 2
        factores.append("interrupciones_frecuentes")
    elif sesiones_30 >= 2 and tasa_interrupcion >= 0.2:
        score += 1
        factores.append("interrupciones_observadas")

    if total_plan > 0 and proporcion_pendiente >= 0.75 and dias_sin_actividad > umbral_inactividad_dias:
        score += 2
        factores.append("actividades_pendientes_altas")
    elif total_plan > 0 and proporcion_pendiente >= 0.5:
        score += 1
        factores.append("actividades_pendientes_moderadas")

    if sesiones_30 < 2 and dias_sin_actividad > umbral_inactividad_dias:
        score += 1
        factores.append("baja_continuidad_30_dias")

    if score >= 5:
        nivel = "alto"
    elif score >= 3:
        nivel = "moderado"
    else:
        nivel = "bajo"

    return {
        "nivel": nivel,
        "score": score,
        "umbral_inactividad_dias": umbral_inactividad_dias,
        "dias_sin_actividad": dias_sin_actividad,
        "sesiones_14_dias": sesiones_14,
        "sesiones_30_dias": sesiones_30,
        "sesiones_completadas_30_dias": completadas_30,
        "sesiones_interrumpidas_30_dias": interrumpidas_30,
        "tasa_interrupcion_30_dias": tasa_interrupcion,
        "actividades_plan": total_plan,
        "actividades_pendientes": pendientes,
        "proporcion_actividades_pendientes": proporcion_pendiente,
        "factores": factores,
        "nota_clinica": "Herramienta de apoyo clinico; no constituye diagnostico.",
    }


def _evaluar_alertas_clinicas(
    cur,
    terapeuta_id,
    *,
    nino_id: Optional[str] = None,
) -> List[Dict[str, Any]]:
    filtro_nino = "AND n.id = %s" if nino_id else ""
    params = [terapeuta_id]
    if nino_id:
        params.append(nino_id)

    cur.execute(
        f"""
        SELECT
            n.id,
            n.nombre,
            n.tutor_id,
            n.terapeuta_id,
            pt.id AS plan_id,
            COALESCE(pt.publicado_at, pt.created_at) AS plan_publicado_at,
            ter.usuario_id AS terapeuta_usuario_id,
            tutor.usuario_id AS tutor_usuario_id
        FROM ninos n
        JOIN terapeutas ter ON ter.id = n.terapeuta_id
        LEFT JOIN padres_tutores tutor ON tutor.id = n.tutor_id
        JOIN planes_terapeuticos pt
          ON pt.nino_id = n.id
         AND pt.activo = TRUE
         AND pt.estado_plan = 'publicado'
         AND pt.publicado_para_tutor = TRUE
        WHERE n.terapeuta_id = %s
          AND n.activo = TRUE
          {filtro_nino}
        """,
        tuple(params),
    )
    ninos = cur.fetchall()
    nuevas_alertas: List[Dict[str, Any]] = []

    for nino in ninos:
        ter_config = _config_notificaciones_usuario(cur, nino["terapeuta_usuario_id"])
        umbral_inactividad = int(ter_config.get("umbral_inactividad_dias") or 7)
        riesgo_abandono = _predecir_riesgo_abandono(
            cur,
            nino,
            umbral_inactividad_dias=umbral_inactividad,
        )
        cur.execute(
            """
            SELECT
                MAX(fecha_inicio) AS ultima_sesion,
                COUNT(*) FILTER (WHERE fecha_inicio >= NOW() - INTERVAL '7 days') AS sesiones_7,
                COUNT(*) FILTER (WHERE fecha_inicio >= NOW() - INTERVAL '14 days') AS sesiones_14,
                COUNT(*) FILTER (WHERE fecha_inicio >= NOW() - INTERVAL '30 days') AS sesiones_30
            FROM sesiones
            WHERE nino_id = %s AND estado = 'completada'
            """,
            (nino["id"],),
        )
        actividad = cur.fetchone() or {}
        ultima = actividad.get("ultima_sesion")
        dias_sin_actividad = (
            int((datetime.utcnow() - ultima.replace(tzinfo=None)).days)
            if ultima else
            int((datetime.utcnow() - nino["plan_publicado_at"].replace(tzinfo=None)).days)
        )
        sesiones_14 = int(actividad.get("sesiones_14") or 0)
        dias_sin_actividad = int(riesgo_abandono["dias_sin_actividad"])
        sesiones_14 = int(riesgo_abandono["sesiones_14_dias"])

        cur.execute(
            """
            SELECT
                COUNT(ra.id) AS actividades,
                ROUND(
                    CAST(SUM(COALESCE(ra.aciertos, 0)) AS NUMERIC)
                    / NULLIF(SUM(NULLIF(ra.repeticiones, 0)), 0),
                    4
                ) AS tasa_aciertos,
                AVG(
                    CASE
                        WHEN COALESCE(ra.repeticiones, 0) > 0
                        THEN COALESCE(ra.aciertos, 0)::float / ra.repeticiones
                        ELSE NULL
                    END
                ) AS cumplimiento,
                AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda
            FROM sesiones s
            JOIN resultados_actividad ra ON ra.sesion_id = s.id
            WHERE s.nino_id = %s
              AND s.estado = 'completada'
              AND s.fecha_inicio >= NOW() - INTERVAL '30 days'
            """,
            (nino["id"],),
        )
        progreso = cur.fetchone() or {}
        cumplimiento = _safe_float(progreso.get("cumplimiento"))
        tasa_aciertos = _safe_float(progreso.get("tasa_aciertos"))
        actividades = int(progreso.get("actividades") or 0)

        cur.execute(
            """
            SELECT
                s.fecha_inicio,
                ROUND(
                    CAST(SUM(COALESCE(ra.aciertos, 0)) AS NUMERIC)
                    / NULLIF(SUM(NULLIF(ra.repeticiones, 0)), 0),
                    4
                ) AS tasa_aciertos
            FROM sesiones s
            JOIN resultados_actividad ra ON ra.sesion_id = s.id
            WHERE s.nino_id = %s
              AND s.estado = 'completada'
            GROUP BY s.id, s.fecha_inicio
            ORDER BY s.fecha_inicio DESC
            LIMIT 6
            """,
            (nino["id"],),
        )
        sesion_metricas = list(reversed(cur.fetchall()))
        retroceso = 0.0
        if len(sesion_metricas) >= 4:
            mitad = len(sesion_metricas) // 2
            previas = [_safe_float(row["tasa_aciertos"]) for row in sesion_metricas[:mitad]]
            recientes = [_safe_float(row["tasa_aciertos"]) for row in sesion_metricas[mitad:]]
            promedio_previo = sum(previas) / len(previas)
            promedio_reciente = sum(recientes) / len(recientes)
            retroceso = round(promedio_previo - promedio_reciente, 4)

        base_metricas = {
            "dias_sin_actividad": dias_sin_actividad,
            "sesiones_14_dias": sesiones_14,
            "sesiones_30_dias": int(actividad.get("sesiones_30") or 0),
            "actividades_30_dias": actividades,
            "cumplimiento_30_dias": cumplimiento,
            "tasa_aciertos_30_dias": tasa_aciertos,
            "retroceso_tasa_aciertos": retroceso,
            "riesgo_abandono": riesgo_abandono,
        }

        if riesgo_abandono["nivel"] == "alto":
            nuevas_alertas.append(
                _emitir_alerta_clinica(
                    cur,
                    nino,
                    tipo="riesgo_abandono_alto",
                    severidad="CRITICA",
                    titulo=f"Riesgo alto de abandono: {nino['nombre']}",
                    mensaje=(
                        f"{nino['nombre']} presenta riesgo alto de abandono terapeutico "
                        f"(puntaje {riesgo_abandono['score']}). "
                        "Usa esta señal como apoyo clinico, no como diagnostico."
                    ),
                    metricas=base_metricas,
                )
            )

        if dias_sin_actividad > umbral_inactividad:
            nuevas_alertas.append(
                _emitir_alerta_clinica(
                    cur,
                    nino,
                    tipo="sin_actividad_umbral",
                    severidad="ADVERTENCIA" if dias_sin_actividad < umbral_inactividad * 2 else "CRITICA",
                    titulo=f"Sin actividad registrada: {nino['nombre']}",
                    mensaje=(
                        f"{nino['nombre']} acumula {dias_sin_actividad} dias sin actividad registrada. "
                        f"El umbral configurado es {umbral_inactividad} dias."
                    ),
                    metricas=base_metricas,
                    recordatorio_familia=(
                        f"No se registran actividades de {nino['nombre']} hace mas de {umbral_inactividad} dias. "
                        "Retoma el plan publicado o coordina con el terapeuta si hubo dificultades."
                    ),
                )
            )

        if sesiones_14 < 2 and dias_sin_actividad <= umbral_inactividad:
            nuevas_alertas.append(
                _emitir_alerta_clinica(
                    cur,
                    nino,
                    tipo="uso_irregular",
                    severidad="ADVERTENCIA",
                    titulo=f"Patron de uso irregular: {nino['nombre']}",
                    mensaje=(
                        f"{nino['nombre']} registra menos de 2 sesiones en los ultimos 14 dias. "
                        "Sugiere revisar barreras de ejecucion con la familia."
                    ),
                    metricas=base_metricas,
                    recordatorio_familia=(
                        f"El plan de {nino['nombre']} se esta ejecutando con baja frecuencia. "
                        "Intenta retomar una rutina semanal estable."
                    ),
                )
            )

        if actividades >= 2 and cumplimiento < 0.6:
            nuevas_alertas.append(
                _emitir_alerta_clinica(
                    cur,
                    nino,
                    tipo="baja_adherencia",
                    severidad="CRITICA" if cumplimiento < 0.45 else "ADVERTENCIA",
                    titulo=f"Baja adherencia: {nino['nombre']}",
                    mensaje=(
                        f"Cumplimiento reciente de {nino['nombre']}: {cumplimiento * 100:.0f}%. "
                        "Revisa dificultad, apoyos y continuidad del plan."
                    ),
                    metricas=base_metricas,
                )
            )

        if retroceso >= 0.2:
            nuevas_alertas.append(
                _emitir_alerta_clinica(
                    cur,
                    nino,
                    tipo="retroceso_significativo",
                    severidad="CRITICA" if retroceso >= 0.35 else "ADVERTENCIA",
                    titulo=f"Retroceso significativo: {nino['nombre']}",
                    mensaje=(
                        f"La tasa de aciertos de {nino['nombre']} descendio {retroceso * 100:.0f} puntos "
                        "respecto a sesiones previas."
                    ),
                    metricas=base_metricas,
                )
            )

    return [alerta for alerta in nuevas_alertas if alerta]


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
            _evaluar_alertas_clinicas(cur, ter["terapeuta_id"])

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
                    pt.publicado_at AS plan_publicado_at,
                    pt.created_at AS plan_created_at,
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

            # 4. Alertas clinicas pendientes generadas por evaluacion automatica.
            cur.execute(
                """
                SELECT COUNT(*) AS cnt
                FROM alertas_clinicas
                WHERE terapeuta_id = %s
                  AND resuelta = FALSE
                """,
                (terapeuta_id,),
            )
            alertas = int((cur.fetchone() or {}).get("cnt") or 0)
            config_notificaciones = _config_notificaciones_usuario(cur, user_id)
            riesgo_por_nino: Dict[str, Dict[str, Any]] = {}
            for nino in ninos:
                if nino["plan_activo_id"]:
                    riesgo_por_nino[str(nino["id"])] = _predecir_riesgo_abandono(
                        cur,
                        {
                            "id": nino["id"],
                            "plan_id": nino["plan_activo_id"],
                            "plan_publicado_at": (
                                nino["plan_publicado_at"]
                                or nino["plan_created_at"]
                                or datetime.utcnow()
                            ),
                        },
                        umbral_inactividad_dias=int(
                            config_notificaciones.get("umbral_inactividad_dias") or 7
                        ),
                    )

    pacientes_list = []
    for n in ninos:
        riesgo_abandono = riesgo_por_nino.get(str(n["id"]), {
            "nivel": "bajo",
            "score": 0,
            "umbral_inactividad_dias": int(config_notificaciones.get("umbral_inactividad_dias") or 7),
            "dias_sin_actividad": 0,
            "sesiones_14_dias": 0,
            "sesiones_30_dias": 0,
            "sesiones_completadas_30_dias": 0,
            "sesiones_interrumpidas_30_dias": 0,
            "tasa_interrupcion_30_dias": 0,
            "actividades_plan": 0,
            "actividades_pendientes": 0,
            "proporcion_actividades_pendientes": 0,
            "factores": [],
            "nota_clinica": "Herramienta de apoyo clinico; no constituye diagnostico.",
        })
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
                "riesgo_abandono": riesgo_abandono,
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

@router.get("/api/dashboard/notificaciones/configuracion")
def obtener_configuracion_notificaciones(current_user: dict = Depends(get_current_user)):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            config = _config_notificaciones_usuario(cur, current_user["id"])
    return config


@router.patch("/api/dashboard/notificaciones/configuracion")
def actualizar_configuracion_notificaciones(
    req: ActualizarConfigNotificacionesRequest,
    current_user: dict = Depends(get_current_user),
):
    canal = (req.canal_preferido or "in_app").strip()
    if canal not in ("in_app", "email", "sms"):
        raise HTTPException(status_code=400, detail="Canal de notificacion no soportado")
    umbral = int(req.umbral_inactividad_dias or 7)
    if umbral < 1 or umbral > 60:
        raise HTTPException(status_code=400, detail="El umbral de inactividad debe estar entre 1 y 60 dias")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                INSERT INTO configuracion_notificaciones (
                    usuario_id, canal_preferido, alertas_clinicas,
                    recordatorios_familia, umbral_inactividad_dias, updated_at
                )
                VALUES (%s, %s, %s, %s, %s, NOW())
                ON CONFLICT (usuario_id) DO UPDATE
                SET canal_preferido = EXCLUDED.canal_preferido,
                    alertas_clinicas = EXCLUDED.alertas_clinicas,
                    recordatorios_familia = EXCLUDED.recordatorios_familia,
                    umbral_inactividad_dias = EXCLUDED.umbral_inactividad_dias,
                    updated_at = NOW()
                RETURNING canal_preferido, alertas_clinicas, recordatorios_familia, umbral_inactividad_dias
                """,
                (
                    current_user["id"],
                    canal,
                    req.alertas_clinicas is not False,
                    req.recordatorios_familia is not False,
                    umbral,
                ),
            )
            config = cur.fetchone()
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="CONFIG_NOTIFICACIONES_ACTUALIZADA",
                entidad_afectada="configuracion_notificaciones",
                entidad_id=current_user["id"],
                payload_nuevo=dict(config),
            )
    return dict(config)


@router.post("/api/dashboard/terapeuta/alertas/evaluar")
def evaluar_alertas_terapeuta(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden evaluar alertas clinicas")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
            nuevas = _evaluar_alertas_clinicas(cur, ter["id"])
    return {"generadas": len(nuevas), "alertas": nuevas}


@router.get("/api/dashboard/terapeuta/alertas")
def listar_alertas_terapeuta(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden ver alertas clinicas")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
            _evaluar_alertas_clinicas(cur, ter["id"])
            cur.execute(
                """
                SELECT
                    ac.id, ac.nino_id, n.nombre AS nino_nombre, ac.tipo,
                    ac.severidad, ac.titulo, ac.mensaje, ac.canal,
                    ac.estado_envio, ac.metricas, ac.resuelta, ac.created_at
                FROM alertas_clinicas ac
                JOIN ninos n ON n.id = ac.nino_id
                WHERE ac.terapeuta_id = %s
                ORDER BY ac.resuelta ASC, ac.created_at DESC
                LIMIT 100
                """,
                (ter["id"],),
            )
            rows = cur.fetchall()
    return [
        {
            "id": str(row["id"]),
            "nino_id": str(row["nino_id"]),
            "nino_nombre": row["nino_nombre"],
            "tipo": row["tipo"],
            "severidad": row["severidad"],
            "titulo": row["titulo"],
            "mensaje": row["mensaje"],
            "canal": row["canal"],
            "estado_envio": row["estado_envio"],
            "metricas": row["metricas"] or {},
            "resuelta": row["resuelta"],
            "created_at": row["created_at"].isoformat() if row["created_at"] else None,
        }
        for row in rows
    ]


@router.patch("/api/dashboard/terapeuta/alertas/{alerta_id}/resolver")
def resolver_alerta_terapeuta(
    alerta_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden resolver alertas clinicas")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            ter = cur.fetchone()
            if not ter:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")
            cur.execute(
                """
                UPDATE alertas_clinicas
                SET resuelta = TRUE, resuelta_at = NOW(), updated_at = NOW()
                WHERE id = %s AND terapeuta_id = %s
                RETURNING id, nino_id, tipo
                """,
                (alerta_id, ter["id"]),
            )
            alerta = cur.fetchone()
            if not alerta:
                raise HTTPException(status_code=404, detail="Alerta no encontrada")
            _registrar_log_alerta(
                cur,
                current_user["id"],
                "ALERTA_CLINICA_RESUELTA",
                alerta["id"],
                {"alerta_id": str(alerta["id"]), "nino_id": str(alerta["nino_id"]), "tipo": alerta["tipo"]},
            )
    return {"ok": True, "alerta_id": alerta_id}


@router.get("/api/dashboard/terapeuta/notificaciones")
def obtener_notificaciones_terapeuta(current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden acceder a estas notificaciones")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    id, titulo, mensaje, leido, created_at, tipo, canal,
                    estado_envio, entidad_tipo, entidad_id, payload
                FROM notificaciones
                WHERE usuario_id = %s
                ORDER BY created_at DESC
                LIMIT 100
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
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "tipo": r["tipo"],
            "canal": r["canal"],
            "estado_envio": r["estado_envio"],
            "entidad_tipo": r["entidad_tipo"],
            "entidad_id": str(r["entidad_id"]) if r["entidad_id"] else None,
            "payload": r["payload"] or {},
        }
        for r in rows
    ]


@router.patch("/api/dashboard/terapeuta/notificaciones/{notificacion_id}/leer")
def marcar_notificacion_terapeuta_leida(
    notificacion_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden leer estas notificaciones")

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
                raise HTTPException(status_code=404, detail="Notificacion no encontrada")
    return {"ok": True, "notificacion_id": notificacion_id}


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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NINO_VINCULADO_TERAPEUTA",
                entidad_afectada="ninos",
                entidad_id=nino["id"],
                nino_id=nino["id"],
                payload_anterior={
                    "terapeuta_id": None,
                    "estado_clinico": nino.get("estado_clinico"),
                },
                payload_nuevo={
                    "terapeuta_id": str(ter["id"]),
                    "estado_clinico": nuevo_estado,
                    "metodo": "email" if req.email else "nino_id",
                },
            )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NINO_VINCULADO_TERAPEUTA",
                entidad_afectada="ninos",
                entidad_id=nino["id"],
                nino_id=nino["id"],
                payload_nuevo={
                    "terapeuta_id": str(ter["id"]),
                    "estado_clinico": "listo_para_plan" if omitir_perfil else nuevo_estado,
                    "omitir_perfil": omitir_perfil,
                },
            )

    return {"ok": True, "nino_id": nino_id}


# ── GET /api/dashboard/familia/resumen ────────────────────────────────────────

@router.get("/api/dashboard/familia/resumen")
def resumen_familia(current_user: dict = Depends(get_current_user)):
    """Resumen del panel familiar con avance solo de los ninos vinculados."""
    if current_user["role"] not in ("padre_tutor", "tutor", "padre"):
        raise HTTPException(status_code=403, detail="Solo los tutores pueden acceder al modulo familiar")

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
                    n.perfil_sensorial, n.objetivos_intervencion,
                    n.nivel_tea_validado,
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

            nino_ids = [str(n["id"]) for n in ninos]
            progreso_por_nino: Dict[str, Dict[str, Any]] = {}
            ultima_sesion_por_nino: Dict[str, Dict[str, Any]] = {}
            recomendaciones_por_nino: Dict[str, List[str]] = {}
            sesiones_semana = 0

            if nino_ids:
                cur.execute(
                    """
                    SELECT
                        s.nino_id,
                        COUNT(DISTINCT s.id) AS sesiones_completadas,
                        COUNT(ra.id) AS actividades_registradas,
                        ROUND(
                            CAST(SUM(COALESCE(ra.aciertos, 0)) AS NUMERIC)
                            / NULLIF(SUM(NULLIF(ra.repeticiones, 0)), 0),
                            4
                        ) AS tasa_aciertos,
                        AVG(
                            CASE
                                WHEN COALESCE(ra.repeticiones, 0) > 0
                                THEN COALESCE(ra.aciertos, 0)::float / ra.repeticiones
                                ELSE NULL
                            END
                        ) AS cumplimiento,
                        AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda,
                        AVG(COALESCE(ra.tiempo_respuesta, 0)) AS promedio_tiempo_segundos
                    FROM sesiones s
                    JOIN resultados_actividad ra ON ra.sesion_id = s.id
                    WHERE s.nino_id = ANY(%s::uuid[])
                      AND s.estado = 'completada'
                      AND s.fecha_inicio >= NOW() - INTERVAL '30 days'
                    GROUP BY s.nino_id
                    """,
                    (nino_ids,),
                )
                progreso_por_nino = {
                    str(row["nino_id"]): row for row in cur.fetchall()
                }

                cur.execute(
                    """
                    SELECT DISTINCT ON (s.nino_id)
                        s.nino_id,
                        s.fecha_inicio,
                        s.estado,
                        EXTRACT(DAY FROM NOW() - s.fecha_inicio) AS dias_desde_ultima,
                        ROUND(
                            CAST(SUM(COALESCE(ra.aciertos, 0)) AS NUMERIC)
                            / NULLIF(SUM(NULLIF(ra.repeticiones, 0)), 0),
                            4
                        ) AS tasa_aciertos
                    FROM sesiones s
                    LEFT JOIN resultados_actividad ra ON ra.sesion_id = s.id
                    WHERE s.nino_id = ANY(%s::uuid[])
                    GROUP BY s.id, s.nino_id, s.fecha_inicio, s.estado
                    ORDER BY s.nino_id, s.fecha_inicio DESC
                    """,
                    (nino_ids,),
                )
                ultima_sesion_por_nino = {
                    str(row["nino_id"]): row for row in cur.fetchall()
                }

                cur.execute(
                    """
                    SELECT COUNT(*) AS cnt
                    FROM sesiones s
                    WHERE s.nino_id = ANY(%s::uuid[])
                      AND s.fecha_inicio >= date_trunc('week', NOW())
                    """,
                    (nino_ids,),
                )
                sesiones_semana = int((cur.fetchone() or {}).get("cnt") or 0)

                cur.execute(
                    """
                    SELECT
                        pt.nino_id,
                        a.id,
                        a.nombre,
                        a.tipo,
                        a.instrucciones,
                        a.recursos_multimedia,
                        COALESCE(pa.nivel_dificultad_actual, a.nivel_dificultad) AS nivel_dificultad,
                        a.duracion_estimada,
                        COALESCE(pa.modo_ejecucion, 'acompanada') AS modo_ejecucion,
                        COALESCE(pa.requiere_acompanamiento, TRUE) AS requiere_acompanamiento
                    FROM planes_terapeuticos pt
                    JOIN plan_actividades pa ON pa.plan_id = pt.id
                    JOIN actividades a ON a.id = pa.actividad_id
                    WHERE pt.nino_id = ANY(%s::uuid[])
                      AND pt.activo = TRUE
                      AND pt.estado_plan = 'publicado'
                      AND pt.publicado_para_tutor = TRUE
                    ORDER BY pt.nino_id, pa.orden
                    """,
                    (nino_ids,),
                )
                ninos_por_id = {str(n["id"]): n for n in ninos}
                for actividad in cur.fetchall():
                    nino_id = str(actividad["nino_id"])
                    recomendaciones = recomendaciones_por_nino.setdefault(nino_id, [])
                    if len(recomendaciones) >= 4:
                        continue
                    for recomendacion in _build_recomendaciones_actividad(
                        ninos_por_id[nino_id],
                        actividad,
                    ):
                        if len(recomendaciones) >= 4:
                            break
                        if recomendacion not in recomendaciones:
                            recomendaciones.append(recomendacion)

    pacientes_list = []
    total_alertas = 0
    for n in ninos:
        nino_id = str(n["id"])
        perfil = n["perfil_sensorial"] or {}
        triaje = _triaje_from_perfil(perfil)
        scq = triaje.get("scq", {}) if isinstance(triaje.get("scq"), dict) else {}
        progreso_row = progreso_por_nino.get(nino_id, {})
        ultima_row = ultima_sesion_por_nino.get(nino_id)

        progreso = {
            "periodo": "ultimos_30_dias",
            "sesiones_completadas": int(progreso_row.get("sesiones_completadas") or 0),
            "actividades_registradas": int(progreso_row.get("actividades_registradas") or 0),
            "tasa_aciertos": round(_safe_float(progreso_row.get("tasa_aciertos")), 4),
            "cumplimiento": round(_safe_float(progreso_row.get("cumplimiento")), 4),
            "promedio_ayuda": round(_safe_float(progreso_row.get("promedio_ayuda")), 2),
            "promedio_tiempo_segundos": round(_safe_float(progreso_row.get("promedio_tiempo_segundos")), 2),
        }

        alertas = []
        if triaje.get("requiere_scq", False) and not triaje.get("scq_completado", False):
            alertas.append("SCQ pendiente para completar la informacion clinica.")
        if not n["plan_activo_id"]:
            alertas.append("Aun no hay un plan terapeutico publicado para la familia.")
        elif progreso["sesiones_completadas"] == 0:
            alertas.append("Plan activo pendiente de registrar sesiones en los ultimos 30 dias.")
        else:
            if progreso["cumplimiento"] and progreso["cumplimiento"] < 0.6:
                alertas.append("Cumplimiento bajo en las actividades recientes.")
            if progreso["tasa_aciertos"] and progreso["tasa_aciertos"] < 0.6:
                alertas.append("Desempeno bajo en los registros recientes.")
            if progreso["promedio_ayuda"] >= 3:
                alertas.append("Nivel de ayuda elevado en las ultimas actividades.")

        if ultima_row and _safe_float(ultima_row.get("dias_desde_ultima")) >= 14:
            alertas.append("No se registran sesiones recientes en las ultimas dos semanas.")

        total_alertas += len(alertas)
        pacientes_list.append({
            "id": nino_id,
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
            "ultima_sesion": {
                "fecha": ultima_row["fecha_inicio"].isoformat()
                if ultima_row and ultima_row["fecha_inicio"]
                else None,
                "estado": ultima_row["estado"] if ultima_row else None,
                "tasa_aciertos": round(
                    _safe_float(ultima_row.get("tasa_aciertos") if ultima_row else None),
                    4,
                ),
            } if ultima_row else None,
            "progreso": progreso,
            "recomendaciones_activas": recomendaciones_por_nino.get(nino_id, [])[:4],
            "alertas": alertas,
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
        "sesiones_esta_semana": sesiones_semana,
        "alertas_baja_adherencia": total_alertas,
        "pacientes": pacientes_list,
    }


# ── GET /api/dashboard/familia/notificaciones ──────────────────────────────────
@router.get("/api/dashboard/familia/notificaciones")
def obtener_notificaciones(current_user: dict = Depends(get_current_user)):
    if current_user["role"] not in ("padre_tutor", "tutor", "padre"):
        raise HTTPException(status_code=403, detail="Solo los tutores pueden acceder a las notificaciones")
    
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    id, titulo, mensaje, leido, created_at, tipo, canal,
                    estado_envio, entidad_tipo, entidad_id, payload
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
            "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            "tipo": r["tipo"],
            "canal": r["canal"],
            "estado_envio": r["estado_envio"],
            "entidad_tipo": r["entidad_tipo"],
            "entidad_id": str(r["entidad_id"]) if r["entidad_id"] else None,
            "payload": r["payload"] or {},
        }
        for r in rows
    ]


# ── PATCH /api/dashboard/familia/notificaciones/{notificacion_id}/leer ────────────
@router.patch("/api/dashboard/familia/notificaciones/{notificacion_id}/leer")
def marcar_notificacion_leida(
    notificacion_id: str,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("padre_tutor", "tutor", "padre"):
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
    _validar_consentimiento_sensible(req)
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
            consentimiento = _registrar_consentimiento(
                cur,
                nino_id=nino["id"],
                tutor_id=tutor["id"],
                usuario_id=current_user["id"],
                version=req.consentimiento_informado_version,
                finalidad="registro_perfil_clinico_funcional",
                payload={
                    "datos_sensibles": _contiene_datos_sensibles(req),
                    "uso_no_diagnostico": req.acepta_uso_no_diagnostico,
                    "minima_recoleccion": True,
                },
            )
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NINO_REGISTRADO",
                entidad_afectada="ninos",
                entidad_id=nino["id"],
                nino_id=nino["id"],
                payload_nuevo={
                    "nombre": req.nombre,
                    "nivel_cognitivo": req.nivel_cognitivo,
                    "diagnostico": req.diagnostico,
                    "estado_clinico": "pendiente_asignacion",
                    "requiere_scq": triaje.get("requiere_scq", False),
                    "consentimiento_id": str(consentimiento["id"]),
                },
            )

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
    _validar_consentimiento_sensible(req)
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
            consentimiento = _registrar_consentimiento(
                cur,
                nino_id=updated["id"],
                tutor_id=tutor["id"],
                usuario_id=current_user["id"],
                version=req.consentimiento_informado_version,
                finalidad="actualizacion_perfil_clinico_funcional",
                payload={
                    "datos_sensibles": _contiene_datos_sensibles(req),
                    "uso_no_diagnostico": req.acepta_uso_no_diagnostico,
                    "minima_recoleccion": True,
                },
            )
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NINO_ACTUALIZADO_FAMILIA",
                entidad_afectada="ninos",
                entidad_id=updated["id"],
                nino_id=updated["id"],
                payload_anterior={"perfil_sensorial": nino["perfil_sensorial"]},
                payload_nuevo={
                    "nombre": req.nombre,
                    "fecha_nacimiento": req.fecha_nacimiento,
                    "nivel_cognitivo": req.nivel_cognitivo,
                    "diagnostico": req.diagnostico,
                    "requiere_scq": triaje.get("requiere_scq", False),
                    "consentimiento_id": str(consentimiento["id"]),
                },
            )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NINO_DESACTIVADO_FAMILIA",
                entidad_afectada="ninos",
                entidad_id=deleted["id"],
                nino_id=deleted["id"],
                payload_nuevo={"activo": False},
            )

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

            if not _tiene_consentimiento_activo(cur, nino_id):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "codigo": "consentimiento_datos_sensibles_requerido",
                        "mensaje": "Debes confirmar consentimiento informado antes de adjuntar documentos clinicos.",
                    },
                )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="DOCUMENTO_CLINICO_ADJUNTADO",
                entidad_afectada="ninos",
                entidad_id=nino_id,
                nino_id=nino_id,
                payload_nuevo={
                    "tipo": tipo,
                    "archivo": file.filename,
                    "content_type": file.content_type,
                    "url": file_url,
                },
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
                    SELECT pt.id, pt.nino_id, n.nivel_tea_validado
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="ACTIVIDAD_OCUPACIONAL_CREADA",
                entidad_afectada="actividades",
                entidad_id=actividad["id"],
                nino_id=plan_context["nino_id"] if plan_context else None,
                payload_nuevo={
                    "nombre": actividad["nombre"],
                    "tipo": actividad["tipo"],
                    "nivel_dificultad": actividad["nivel_dificultad"],
                    "duracion_estimada": actividad["duracion_estimada"],
                    "plan_id": req.plan_id,
                    "asociado": bool(req.plan_id),
                },
            )

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
                _registrar_auditoria(
                    cur,
                    usuario_id=current_user["id"],
                    rol_usuario=current_user["role"],
                    accion="ACTIVIDAD_ASOCIADA_PLAN",
                    entidad_afectada="plan_actividades",
                    entidad_id=f"{req.plan_id}:{actividad['id']}",
                    nino_id=plan_context["nino_id"],
                    payload_nuevo={
                        "plan_id": req.plan_id,
                        "actividad_id": str(actividad["id"]),
                        "orden": orden,
                        "nivel_dificultad_actual": dificultad,
                    },
                )

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
                SELECT pt.id, pt.nino_id, n.nivel_tea_validado
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="ACTIVIDAD_ASOCIADA_PLAN",
                entidad_afectada="plan_actividades",
                entidad_id=f"{plan_id}:{actividad_id}",
                nino_id=plan_context["nino_id"],
                payload_nuevo={
                    "plan_id": plan_id,
                    "actividad_id": actividad_id,
                    "orden": orden,
                    "nivel_dificultad_actual": actividad["nivel_dificultad"],
                },
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
                SELECT pt.id, pt.nino_id FROM planes_terapeuticos pt
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="ACTIVIDAD_DESASOCIADA_PLAN",
                entidad_afectada="plan_actividades",
                entidad_id=f"{plan_id}:{actividad_id}",
                nino_id=plan_context["nino_id"],
                payload_anterior={"plan_id": plan_id, "actividad_id": actividad_id},
                payload_nuevo={"eliminada": True},
            )

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
                SELECT pt.id, pt.nino_id, n.nivel_tea_validado, pa.orden
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="ACTIVIDAD_REEMPLAZADA_PLAN",
                entidad_afectada="plan_actividades",
                entidad_id=f"{plan_id}:{nueva_actividad_id}",
                nino_id=plan_context["nino_id"],
                payload_anterior={
                    "plan_id": plan_id,
                    "actividad_id": actividad_id,
                },
                payload_nuevo={
                    "plan_id": plan_id,
                    "actividad_id": nueva_actividad_id,
                    "nivel_dificultad_actual": nueva["nivel_dificultad"],
                    "modo_ejecucion": ejecucion["modo_ejecucion"],
                },
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="DIFICULTAD_ACTIVIDAD_ACTUALIZADA",
                entidad_afectada="plan_actividades",
                entidad_id=f"{plan_id}:{actividad_id}",
                nino_id=row["nino_id"],
                payload_anterior={"dificultad_actual": actual},
                payload_nuevo={**detalle, "decision_id": str(decision["id"])},
            )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="NIVEL_TEA_VALIDADO",
                entidad_afectada="ninos",
                entidad_id=nino_id,
                nino_id=nino_id,
                payload_nuevo={
                    **detalle,
                    "estado_clinico": nino["estado_clinico"],
                },
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="ESTADO_PLAN_ACTUALIZADO",
                entidad_afectada="planes_terapeuticos",
                entidad_id=plan["id"],
                nino_id=plan["nino_id"],
                payload_nuevo={
                    **detalle,
                    "estado_plan": plan["estado_plan"],
                    "publicado_para_tutor": plan["publicado_para_tutor"],
                },
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
                        n.nivel_tea_validado, n.nivel_cognitivo,
                        n.perfil_sensorial, n.objetivos_intervencion
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
                        n.nivel_tea_validado, n.nivel_cognitivo,
                        n.perfil_sensorial, n.objetivos_intervencion
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
                "materiales": _json_dict(a["recursos_multimedia"]).get("materiales", []),
                "recomendaciones_adaptadas": _build_recomendaciones_actividad(
                    plan,
                    a,
                ),
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
                SELECT pt.id, pt.nino_id, pt.terapeuta_id, pt.nivel_dificultad_actual
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

            if req.client_event_id:
                cur.execute(
                    """
                    SELECT
                        s.id AS sesion_id,
                        s.client_event_id,
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
                    WHERE s.client_event_id = %s::uuid
                      AND s.nino_id = %s
                      AND s.plan_id = %s
                      AND s.estado = 'completada'
                    ORDER BY s.fecha_inicio DESC
                    LIMIT 1
                    """,
                    (str(req.client_event_id), req.nino_id, req.plan_id),
                )
                evento_existente = cur.fetchone()
                if evento_existente:
                    total_intentos = int(evento_existente["repeticiones"] or 0)
                    total_aciertos = int(evento_existente["aciertos"] or 0)
                    tasa = round(total_aciertos / total_intentos, 4) if total_intentos else 0
                    return {
                        "ok": True,
                        "ya_registrada": True,
                        "sesion_id": str(evento_existente["sesion_id"]),
                        "client_event_id": str(evento_existente["client_event_id"]),
                        "total_aciertos": total_aciertos,
                        "total_intentos": total_intentos,
                        "tasa_aciertos": tasa,
                        "nivel_dificultad_recomendado": evento_existente["nivel_dificultad_actual"],
                        "ajustes_dificultad": [],
                    }

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
                    "client_event_id": str(req.client_event_id) if req.client_event_id else None,
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
                     ejecutado_por_rol, ejecutado_por_usuario_id, origen_registro,
                     client_event_id)
                VALUES (%s, %s, NOW(), NOW(), 'completada', NOW(), %s, %s, %s, %s)
                RETURNING id
                """,
                (
                    req.nino_id,
                    req.plan_id,
                    current_user["role"],
                    current_user["id"],
                    "familia_app_offline" if req.client_event_id else "familia_app",
                    str(req.client_event_id) if req.client_event_id else None,
                ),
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

            _evaluar_alertas_clinicas(cur, plan["terapeuta_id"], nino_id=req.nino_id)
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="SESION_TERAPEUTICA_REGISTRADA",
                entidad_afectada="sesiones",
                entidad_id=sesion["id"],
                nino_id=req.nino_id,
                payload_nuevo={
                    "plan_id": req.plan_id,
                    "client_event_id": str(req.client_event_id) if req.client_event_id else None,
                    "origen_registro": "familia_app_offline" if req.client_event_id else "familia_app",
                    "total_aciertos": total_aciertos,
                    "total_intentos": total_intentos,
                    "actividades": [
                        {
                            "actividad_id": resultado.actividad_id,
                            "aciertos": resultado.aciertos,
                            "repeticiones": resultado.repeticiones,
                            "tiempo_respuesta": resultado.tiempo_respuesta,
                            "nivel_ayuda_requerido": resultado.nivel_ayuda_requerido,
                        }
                        for resultado in req.resultados
                    ],
                },
            )

    tasa = round(total_aciertos / total_intentos, 4) if total_intentos else 0
    nivel_recomendado = ajustes[-1]["dificultad_sugerida"] if ajustes else plan["nivel_dificultad_actual"]
    return {
        "ok": True,
        "sesion_id": str(sesion["id"]),
        "client_event_id": str(req.client_event_id) if req.client_event_id else None,
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="SOLICITUD_AJUSTE_DIFICULTAD_CREADA",
                entidad_afectada="decisiones_clinicas",
                entidad_id=decision["id"],
                nino_id=row["nino_id"],
                payload_nuevo={**detalle, "decision_id": str(decision["id"])},
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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="SOLICITUD_AJUSTE_DIFICULTAD_RESUELTA",
                entidad_afectada="decisiones_clinicas",
                entidad_id=decision["id"],
                nino_id=solicitud["nino_id"],
                payload_anterior={
                    "solicitud_id": decision_id,
                    "accion_solicitada": solicitud["accion"],
                },
                payload_nuevo={
                    **resolucion,
                    "decision_id": str(decision["id"]),
                    "estado": "aprobada" if req.aceptar else "rechazada",
                },
            )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="PERFIL_CLINICO_ACTUALIZADO",
                entidad_afectada="ninos",
                entidad_id=nino_id,
                nino_id=nino_id,
                payload_anterior={"perfil_sensorial": existing_perfil},
                payload_nuevo={
                    "campos_actualizados": list(updates.keys()),
                    "estado_clinico": row["estado_clinico"],
                    "observaciones_clinicas": bool(observaciones),
                },
            )

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
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="PLAN_TERAPEUTICO_GENERADO",
                entidad_afectada="planes_terapeuticos",
                entidad_id=plan["id"],
                nino_id=nino_id,
                payload_anterior={
                    "plan_activo_anterior": str(existing["id"]) if existing else None,
                },
                payload_nuevo={
                    "sesion_numero": siguiente_sesion,
                    "dificultad_inicial": dificultad_ia,
                    "nivel_dificultad_db": nivel_dificultad_db,
                    "confianza_ia": confianza,
                    "actividades": [str(act["id"]) for act in acts],
                    "estado_plan": "borrador",
                },
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
                    n.terapeuta_id, n.tutor_id,
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
            if current_user["role"] == "terapeuta":
                cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
                ter = cur.fetchone()
                if not ter or nino["terapeuta_id"] != ter["id"]:
                    raise HTTPException(status_code=403, detail="Acceso denegado al perfil del nino")
            elif current_user["role"] in ("padre_tutor", "tutor", "padre"):
                cur.execute("SELECT id FROM padres_tutores WHERE usuario_id = %s", (current_user["id"],))
                tutor = cur.fetchone()
                if not tutor or nino["tutor_id"] != tutor["id"]:
                    raise HTTPException(status_code=403, detail="Acceso denegado al perfil del nino")
            elif current_user["role"] != "admin":
                raise HTTPException(status_code=403, detail="Acceso denegado")

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
    _autorizar_acceso_nino(nino_id, current_user)
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
                f"""
                SELECT
                    s.id,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                WHERE s.nino_id = %s
                  AND s.fecha_inicio >= {fecha_desde}
                  AND s.estado = 'completada'
                GROUP BY s.id, s.fecha_inicio
                ORDER BY s.fecha_inicio DESC
                LIMIT 8
                """,
                (nino_id,),
            )
            historia_rows = cur.fetchall()

            cur.execute(
                f"""
                SELECT
                    COALESCE(NULLIF(a.tipo, ''), 'Sin categoria') AS habilidad,
                    COUNT(DISTINCT s.id) AS sesiones,
                    COUNT(ra.id) AS actividades,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa_aciertos,
                    AVG(COALESCE(ra.tiempo_respuesta, 0)) AS promedio_tiempo,
                    AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda,
                    ROUND(
                        CAST(COUNT(*) FILTER (
                            WHERE ra.repeticiones > 0
                              AND CAST(ra.aciertos AS NUMERIC) / ra.repeticiones >= 0.8
                        ) AS NUMERIC) / NULLIF(COUNT(*), 0), 4
                    ) AS cumplimiento
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN actividades a ON a.id = ra.actividad_id
                WHERE s.nino_id = %s
                  AND s.fecha_inicio >= {fecha_desde}
                  AND s.estado = 'completada'
                GROUP BY habilidad
                ORDER BY habilidad ASC
                """,
                (nino_id,),
            )
            habilidades_rows = cur.fetchall()

            cur.execute(
                f"""
                WITH sesiones_filtradas AS (
                    SELECT s.id, s.plan_id, s.fecha_inicio
                    FROM sesiones s
                    WHERE s.nino_id = %s
                      AND s.fecha_inicio >= {fecha_desde}
                      AND s.estado = 'completada'
                )
                SELECT
                    sf.id AS sesion_id,
                    sf.plan_id,
                    sf.fecha_inicio,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa_aciertos,
                    SUM(ra.aciertos) AS total_aciertos,
                    SUM(ra.repeticiones) AS total_intentos,
                    AVG(COALESCE(ra.tiempo_respuesta, 0)) AS promedio_tiempo,
                    AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda,
                    ROUND(
                        CAST(COUNT(*) FILTER (
                            WHERE ra.repeticiones > 0
                              AND CAST(ra.aciertos AS NUMERIC) / ra.repeticiones >= 0.8
                        ) AS NUMERIC) / NULLIF(COUNT(*), 0), 4
                    ) AS cumplimiento
                FROM sesiones_filtradas sf
                JOIN resultados_actividad ra ON ra.sesion_id = sf.id
                GROUP BY sf.id, sf.plan_id, sf.fecha_inicio
                ORDER BY sf.fecha_inicio DESC
                LIMIT 12
                """,
                (nino_id,),
            )
            sesiones_rows = cur.fetchall()

            sesion_ids = [row["sesion_id"] for row in sesiones_rows]
            habilidades_por_sesion: Dict[str, List[Dict[str, Any]]] = {}
            observaciones_rows = []
            if sesion_ids:
                cur.execute(
                    """
                    SELECT
                        ra.sesion_id,
                        COALESCE(NULLIF(a.tipo, ''), 'Sin categoria') AS habilidad,
                        COUNT(ra.id) AS actividades,
                        ROUND(
                            CAST(SUM(ra.aciertos) AS NUMERIC) /
                            NULLIF(SUM(ra.repeticiones), 0), 4
                        ) AS tasa_aciertos,
                        AVG(COALESCE(ra.tiempo_respuesta, 0)) AS promedio_tiempo,
                        AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda
                    FROM resultados_actividad ra
                    JOIN actividades a ON a.id = ra.actividad_id
                    WHERE ra.sesion_id = ANY(%s::uuid[])
                    GROUP BY ra.sesion_id, habilidad
                    ORDER BY habilidad ASC
                    """,
                    (sesion_ids,),
                )
                for row in cur.fetchall():
                    sid = str(row["sesion_id"])
                    habilidades_por_sesion.setdefault(sid, []).append({
                        "habilidad": row["habilidad"],
                        "actividades": int(row["actividades"] or 0),
                        "tasa_aciertos": float(row["tasa_aciertos"] or 0),
                        "promedio_tiempo": float(row["promedio_tiempo"] or 0),
                        "promedio_ayuda": float(row["promedio_ayuda"] or 0),
                    })

                cur.execute(
                    """
                    SELECT
                        ra.observaciones,
                        ra.timestamp,
                        a.nombre AS actividad_nombre
                    FROM resultados_actividad ra
                    JOIN actividades a ON a.id = ra.actividad_id
                    WHERE ra.sesion_id = ANY(%s::uuid[])
                      AND NULLIF(TRIM(COALESCE(ra.observaciones, '')), '') IS NOT NULL
                    ORDER BY ra.timestamp DESC
                    LIMIT 5
                    """,
                    (sesion_ids,),
                )
                observaciones_rows = cur.fetchall()

    sesiones = resumen["sesiones_completadas"] or 0
    tasa = float(resumen["tasa_aciertos"]) if resumen["tasa_aciertos"] else 0.0
    historia = [float(r["tasa"]) for r in reversed(historia_rows) if r["tasa"] is not None]
    if not historia:
        historia = [0.0]

    # Adherencia simplificada: proporción de sesiones completadas vs esperadas (objetivo 5/semana)
    expected_by_period = {
        "Esta semana": 5.0,
        "Este mes": 20.0,
    }
    adherencia = min(
        1.0,
        sesiones / expected_by_period.get(periodo, max(float(sesiones), 1.0)),
    )

    habilidades = [
        {
            "habilidad": row["habilidad"],
            "sesiones": int(row["sesiones"] or 0),
            "actividades": int(row["actividades"] or 0),
            "tasa_aciertos": float(row["tasa_aciertos"] or 0),
            "promedio_tiempo": float(row["promedio_tiempo"] or 0),
            "promedio_ayuda": float(row["promedio_ayuda"] or 0),
            "cumplimiento": float(row["cumplimiento"] or 0),
        }
        for row in habilidades_rows
    ]

    sesiones_detalle = []
    for index, row in enumerate(reversed(sesiones_rows), start=1):
        sid = str(row["sesion_id"])
        fecha = row["fecha_inicio"]
        sesiones_detalle.append({
            "sesion_id": sid,
            "sesion_numero": index,
            "plan_id": str(row["plan_id"]),
            "fecha": fecha.isoformat() if fecha else None,
            "tasa_aciertos": float(row["tasa_aciertos"] or 0),
            "total_aciertos": int(row["total_aciertos"] or 0),
            "total_intentos": int(row["total_intentos"] or 0),
            "promedio_tiempo": float(row["promedio_tiempo"] or 0),
            "promedio_ayuda": float(row["promedio_ayuda"] or 0),
            "cumplimiento": float(row["cumplimiento"] or 0),
            "habilidades": habilidades_por_sesion.get(sid, []),
        })

    return {
        "periodo": periodo,
        "sesiones_completadas": sesiones,
        "tasa_aciertos": tasa,
        "adherencia": adherencia,
        "historia_aciertos": historia,
        "metricas_por_habilidad": habilidades,
        "sesiones": sesiones_detalle,
        "observaciones_recientes": [
            {
                "actividad": row["actividad_nombre"],
                "observacion": row["observaciones"],
                "fecha": row["timestamp"].isoformat() if row["timestamp"] else None,
            }
            for row in observaciones_rows
        ],
    }


# ── GET /api/dashboard/terapeuta/ninos/{nino_id}/reporte-terapeutico ──────────
# Genera reportes exportables del historial terapeutico real del niño.

@router.get("/api/dashboard/terapeuta/ninos/{nino_id}/reporte-terapeutico")
def generar_reporte_terapeutico(
    nino_id: str,
    formato: str = "json",
    inicio: Optional[datetime] = None,
    fin: Optional[datetime] = None,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] != "terapeuta":
        raise HTTPException(status_code=403, detail="Solo terapeutas pueden generar reportes terapeuticos")

    formato = (formato or "json").strip().lower()
    if formato not in ("json", "pdf"):
        raise HTTPException(status_code=400, detail="Formato no soportado. Usa json o pdf.")

    periodo_fin = fin or datetime.utcnow()
    periodo_inicio = inicio or (periodo_fin - timedelta(days=90))
    if periodo_inicio > periodo_fin:
        raise HTTPException(status_code=400, detail="La fecha de inicio no puede ser posterior a la fecha final")

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (current_user["id"],))
            terapeuta = cur.fetchone()
            if not terapeuta:
                raise HTTPException(status_code=404, detail="Perfil de terapeuta no encontrado")

            cur.execute(
                """
                SELECT
                    n.id,
                    n.nombre,
                    n.fecha_nacimiento,
                    n.nivel_cognitivo,
                    n.diagnostico,
                    n.nivel_tea_validado
                FROM ninos n
                WHERE n.id = %s
                  AND n.terapeuta_id = %s
                  AND n.activo = TRUE
                """,
                (nino_id, terapeuta["id"]),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado para este terapeuta")

            cur.execute(
                """
                SELECT
                    s.id AS sesion_id,
                    s.plan_id,
                    pt.nombre AS plan_nombre,
                    s.fecha_inicio,
                    s.fecha_fin,
                    COUNT(ra.id) AS actividades,
                    SUM(ra.aciertos) AS total_aciertos,
                    SUM(ra.repeticiones) AS total_intentos,
                    AVG(COALESCE(ra.tiempo_respuesta, 0)) AS promedio_tiempo,
                    AVG(COALESCE(ra.nivel_ayuda_requerido, 0)) AS promedio_ayuda,
                    ROUND(
                        CAST(SUM(ra.aciertos) AS NUMERIC) /
                        NULLIF(SUM(ra.repeticiones), 0), 4
                    ) AS tasa_aciertos,
                    ROUND(
                        CAST(COUNT(*) FILTER (
                            WHERE ra.repeticiones > 0
                              AND CAST(ra.aciertos AS NUMERIC) / ra.repeticiones >= 0.8
                        ) AS NUMERIC) / NULLIF(COUNT(*), 0), 4
                    ) AS cumplimiento
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN planes_terapeuticos pt ON pt.id = s.plan_id
                WHERE s.nino_id = %s
                  AND s.estado = 'completada'
                  AND s.fecha_inicio >= %s
                  AND s.fecha_inicio <= %s
                GROUP BY s.id, s.plan_id, pt.nombre, s.fecha_inicio, s.fecha_fin
                ORDER BY s.fecha_inicio ASC
                """,
                (nino_id, periodo_inicio, periodo_fin),
            )
            sesiones_rows = cur.fetchall()

            cur.execute(
                """
                SELECT
                    s.id AS sesion_id,
                    s.fecha_inicio,
                    ra.timestamp,
                    a.id AS actividad_id,
                    a.nombre AS actividad_nombre,
                    COALESCE(NULLIF(a.tipo, ''), 'Sin categoria') AS habilidad,
                    ra.aciertos,
                    ra.repeticiones,
                    COALESCE(ra.tiempo_respuesta, 0) AS tiempo_respuesta,
                    COALESCE(ra.nivel_ayuda_requerido, 0) AS nivel_ayuda_requerido,
                    ra.nivel_dificultad_usado,
                    ra.observaciones
                FROM sesiones s
                JOIN resultados_actividad ra ON ra.sesion_id = s.id
                JOIN actividades a ON a.id = ra.actividad_id
                WHERE s.nino_id = %s
                  AND s.estado = 'completada'
                  AND s.fecha_inicio >= %s
                  AND s.fecha_inicio <= %s
                ORDER BY s.fecha_inicio ASC, ra.timestamp ASC
                """,
                (nino_id, periodo_inicio, periodo_fin),
            )
            actividades_rows = cur.fetchall()

    sesiones = []
    for row in sesiones_rows:
        fecha_inicio = row["fecha_inicio"]
        fecha_fin = row["fecha_fin"]
        sesiones.append({
            "sesion_id": str(row["sesion_id"]),
            "plan_id": str(row["plan_id"]),
            "plan_nombre": row["plan_nombre"],
            "fecha": fecha_inicio.isoformat() if fecha_inicio else None,
            "fecha_fin": fecha_fin.isoformat() if fecha_fin else None,
            "actividades": int(row["actividades"] or 0),
            "total_aciertos": int(row["total_aciertos"] or 0),
            "total_intentos": int(row["total_intentos"] or 0),
            "promedio_tiempo_segundos": _safe_float(row["promedio_tiempo"]),
            "promedio_ayuda": _safe_float(row["promedio_ayuda"]),
            "tasa_aciertos": _safe_float(row["tasa_aciertos"]),
            "cumplimiento": _safe_float(row["cumplimiento"]),
        })

    total_aciertos = sum(item["total_aciertos"] for item in sesiones)
    total_intentos = sum(item["total_intentos"] for item in sesiones)
    actividades_total = len(actividades_rows)
    cumplidas = sum(
        1
        for row in actividades_rows
        if int(row["repeticiones"] or 0) > 0
        and int(row["aciertos"] or 0) / int(row["repeticiones"] or 1) >= 0.8
    )
    promedio_tiempo = (
        sum(_safe_float(row["tiempo_respuesta"]) for row in actividades_rows) / actividades_total
        if actividades_total else 0.0
    )
    promedio_ayuda = (
        sum(_safe_float(row["nivel_ayuda_requerido"]) for row in actividades_rows) / actividades_total
        if actividades_total else 0.0
    )

    habilidad_acc = {}
    for row in actividades_rows:
        habilidad = row["habilidad"]
        data = habilidad_acc.setdefault(
            habilidad,
            {"habilidad": habilidad, "actividades": 0, "aciertos": 0, "intentos": 0, "tiempos": [], "ayudas": []},
        )
        data["actividades"] += 1
        data["aciertos"] += int(row["aciertos"] or 0)
        data["intentos"] += int(row["repeticiones"] or 0)
        data["tiempos"].append(_safe_float(row["tiempo_respuesta"]))
        data["ayudas"].append(_safe_float(row["nivel_ayuda_requerido"]))

    progreso_por_habilidad = []
    for data in habilidad_acc.values():
        intentos = data["intentos"]
        progreso_por_habilidad.append({
            "habilidad": data["habilidad"],
            "actividades": data["actividades"],
            "tasa_aciertos": round(data["aciertos"] / intentos, 4) if intentos else 0.0,
            "promedio_tiempo_segundos": sum(data["tiempos"]) / len(data["tiempos"]) if data["tiempos"] else 0.0,
            "promedio_ayuda": sum(data["ayudas"]) / len(data["ayudas"]) if data["ayudas"] else 0.0,
        })
    progreso_por_habilidad.sort(key=lambda item: item["habilidad"])

    observaciones = [
        {
            "fecha": (row["timestamp"] or row["fecha_inicio"]).isoformat(),
            "sesion_id": str(row["sesion_id"]),
            "actividad": row["actividad_nombre"],
            "habilidad": row["habilidad"],
            "observacion": row["observaciones"],
        }
        for row in actividades_rows
        if str(row["observaciones"] or "").strip()
    ]

    actividades_detalle = [
        {
            "fecha": row["fecha_inicio"].isoformat() if row["fecha_inicio"] else None,
            "sesion_id": str(row["sesion_id"]),
            "actividad_id": str(row["actividad_id"]),
            "actividad": row["actividad_nombre"],
            "habilidad": row["habilidad"],
            "aciertos": int(row["aciertos"] or 0),
            "intentos": int(row["repeticiones"] or 0),
            "tasa_aciertos": (
                round(int(row["aciertos"] or 0) / int(row["repeticiones"] or 1), 4)
                if int(row["repeticiones"] or 0) > 0 else 0.0
            ),
            "tiempo_segundos": _safe_float(row["tiempo_respuesta"]),
            "nivel_ayuda_requerido": int(row["nivel_ayuda_requerido"] or 0),
            "nivel_dificultad_usado": row["nivel_dificultad_usado"],
        }
        for row in actividades_rows
    ]

    reporte = {
        "formato": formato,
        "generado_at": datetime.utcnow().isoformat(),
        "nino": {
            "id": str(nino["id"]),
            "nombre": nino["nombre"],
            "edad": _calc_edad(nino["fecha_nacimiento"]),
            "nivel_cognitivo": nino["nivel_cognitivo"],
            "diagnostico": nino["diagnostico"],
            "nivel_tea_validado": nino["nivel_tea_validado"],
        },
        "periodo": {
            "inicio": periodo_inicio.isoformat(),
            "fin": periodo_fin.isoformat(),
        },
        "resumen": {
            "sesiones_completadas": len(sesiones),
            "actividades_registradas": actividades_total,
            "tasa_aciertos_global": round(total_aciertos / total_intentos, 4) if total_intentos else 0.0,
            "cumplimiento_global": round(cumplidas / actividades_total, 4) if actividades_total else 0.0,
            "promedio_tiempo_segundos": promedio_tiempo,
            "promedio_ayuda": promedio_ayuda,
        },
        "tendencias": _build_tendencia(sesiones),
        "progreso_por_habilidad": progreso_por_habilidad,
        "sesiones": sesiones,
        "actividades": actividades_detalle,
        "observaciones": observaciones,
    }

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            _registrar_auditoria(
                cur,
                usuario_id=current_user["id"],
                rol_usuario=current_user["role"],
                accion="REPORTE_TERAPEUTICO_GENERADO",
                entidad_afectada="reportes_terapeuticos",
                entidad_id=f"{nino_id}:{formato}:{periodo_inicio.isoformat()}:{periodo_fin.isoformat()}",
                nino_id=nino_id,
                payload_nuevo={
                    "formato": formato,
                    "periodo_inicio": periodo_inicio.isoformat(),
                    "periodo_fin": periodo_fin.isoformat(),
                    "sesiones_incluidas": len(sesiones),
                    "actividades_incluidas": actividades_total,
                },
            )

    if formato == "pdf":
        filename = f"reporte-terapeutico-{nino_id}.pdf"
        return Response(
            content=_build_reporte_pdf(reporte),
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename}"},
        )
    return reporte


@router.get("/api/dashboard/terapeuta/ninos/{nino_id}/auditoria")
def listar_auditoria_nino(
    nino_id: str,
    limite: int = 100,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("terapeuta", "admin"):
        raise HTTPException(status_code=403, detail="Solo terapeutas o administradores pueden consultar auditoria")

    limite = max(1, min(int(limite or 100), 500))
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if current_user["role"] == "terapeuta":
                cur.execute(
                    """
                    SELECT 1
                    FROM ninos n
                    JOIN terapeutas t ON t.id = n.terapeuta_id
                    WHERE n.id = %s
                      AND t.usuario_id = %s
                      AND n.activo = TRUE
                    """,
                    (nino_id, current_user["id"]),
                )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Nino no encontrado para este terapeuta")

            cur.execute(
                """
                SELECT
                    la.id,
                    la.fecha_evento,
                    la.timestamp_servidor,
                    la.usuario_id,
                    u.nombre AS actor_nombre,
                    u.email AS actor_email,
                    la.rol_usuario,
                    la.accion,
                    la.entidad_afectada,
                    la.entidad_id,
                    la.nino_id,
                    la.payload_anterior,
                    la.payload_nuevo
                FROM logs_auditoria la
                LEFT JOIN usuarios u ON u.id = la.usuario_id
                WHERE la.nino_id = %s
                ORDER BY COALESCE(la.fecha_evento, la.timestamp_servidor) DESC
                LIMIT %s
                """,
                (nino_id, limite),
            )
            rows = cur.fetchall()

    return {
        "nino_id": nino_id,
        "eventos": [
            {
                "id": str(row["id"]),
                "fecha": (row["fecha_evento"] or row["timestamp_servidor"]).isoformat(),
                "actor": {
                    "usuario_id": str(row["usuario_id"]) if row["usuario_id"] else None,
                    "nombre": row["actor_nombre"],
                    "email": row["actor_email"],
                    "rol": row["rol_usuario"],
                },
                "accion": row["accion"],
                "entidad_afectada": row["entidad_afectada"],
                "entidad_id": row["entidad_id"],
                "nino_id": str(row["nino_id"]) if row["nino_id"] else None,
                "payload_anterior": row["payload_anterior"] or {},
                "payload_nuevo": row["payload_nuevo"] or {},
            }
            for row in rows
        ],
    }


# ── GET /api/ia/asistente/{nino_id} ─────────────────────────────────────────────
# Datos para el Asistente IA (usado por IAAssistantScreen)

@router.get("/api/dashboard/cumplimiento/proteccion-datos")
def obtener_cumplimiento_proteccion_datos(
    nino_id: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    if current_user["role"] not in ("terapeuta", "admin", "padre_tutor", "tutor"):
        raise HTTPException(status_code=403, detail="Acceso denegado al modulo de cumplimiento")
    if nino_id:
        _autorizar_acceso_nino(nino_id, current_user)

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT control, descripcion, estado, referencia, updated_at
                FROM evidencias_cumplimiento
                ORDER BY control
                """
            )
            controles = cur.fetchall()

            consentimiento = None
            if nino_id:
                cur.execute(
                    """
                    SELECT id, version, finalidad, datos_sensibles, aceptado, accepted_at, revoked_at
                    FROM consentimientos_informados
                    WHERE nino_id = %s
                    ORDER BY accepted_at DESC
                    LIMIT 1
                    """,
                    (nino_id,),
                )
                row = cur.fetchone()
                if row:
                    consentimiento = {
                        "id": str(row["id"]),
                        "version": row["version"],
                        "finalidad": row["finalidad"],
                        "datos_sensibles": row["datos_sensibles"],
                        "aceptado": row["aceptado"] and row["revoked_at"] is None,
                        "accepted_at": row["accepted_at"].isoformat() if row["accepted_at"] else None,
                        "revoked_at": row["revoked_at"].isoformat() if row["revoked_at"] else None,
                    }

    return {
        "marco_normativo": {
            "pais": "Peru",
            "ley": "Ley N. 29733 - Ley de Proteccion de Datos Personales",
            "alcance": "Tratamiento de datos personales y datos sensibles del nino en RimAI.",
        },
        "rol_usuario": current_user["role"],
        "nino_id": nino_id,
        "consentimiento": consentimiento,
        "controles": [
            {
                "control": row["control"],
                "descripcion": row["descripcion"],
                "estado": row["estado"],
                "referencia": row["referencia"],
                "updated_at": row["updated_at"].isoformat() if row["updated_at"] else None,
            }
            for row in controles
        ],
        "minima_recoleccion": {
            "datos_obligatorios_registro_familiar": ["nombre", "fecha_nacimiento", "nivel_cognitivo"],
            "datos_sensibles_opcionales": ["diagnostico", "documentos_clinicos", "medicacion_actual", "perfil_sensorial"],
            "confirmacion_requerida_para_sensibles": True,
        },
        "advertencia_clinica": (
            "RimAI opera como herramienta de apoyo clinico y seguimiento terapeutico; "
            "no sustituye evaluacion profesional ni emite diagnostico clinico."
        ),
        "control_acceso": {
            "terapeuta": "Solo accede a ninos vinculados a su perfil profesional.",
            "familia": "Solo accede a ninos asociados a su cuenta de tutor.",
            "admin": "Acceso administrativo trazable.",
        },
    }


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
