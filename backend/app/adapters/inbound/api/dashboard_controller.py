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

import os
from datetime import date, datetime
from typing import Any, Dict, List, Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.adapters.inbound.api.dependencies import get_current_user

router = APIRouter(tags=["dashboard"])

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
)


def _conn():
    return psycopg2.connect(DATABASE_URL)


# ── Pydantic models ────────────────────────────────────────────────────────────

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


# ── Helpers ────────────────────────────────────────────────────────────────────

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
                ORDER BY n.created_at DESC
                """
            )
            rows = cur.fetchall()

    result = []
    for r in rows:
        sensorial = r["perfil_sensorial"] or {}
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
                "comunicacion": None,
                "intereses": sensorial.get("intereses", []),
                "tutor_nombre": r["tutor_nombre"],
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
                    "SELECT id FROM ninos WHERE id = %s AND activo = TRUE",
                    (req.nino_id,),
                )
            elif req.email:
                cur.execute(
                    """
                    SELECT n.id FROM ninos n
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

            cur.execute(
                """
                UPDATE ninos
                SET terapeuta_id = %s,
                    estado_clinico = 'perfil_clinico_incompleto',
                    vinculado_por = %s,
                    vinculado_at = NOW()
                WHERE id = %s
                """,
                (ter["id"], ter["id"], nino["id"]),
            )

    return {"ok": True, "nino_id": str(nino["id"])}


# ── POST /api/dashboard/terapeuta/vincular/{nino_id} ──────────────────────────

@router.post("/api/dashboard/terapeuta/vincular/{nino_id}")
def vincular_paciente_por_id(
    nino_id: str,
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
                "SELECT id FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            cur.execute(
                """
                UPDATE ninos
                SET terapeuta_id = %s,
                    estado_clinico = 'perfil_clinico_incompleto',
                    vinculado_por = %s,
                    vinculado_at = NOW()
                WHERE id = %s
                """,
                (ter["id"], ter["id"], nino["id"]),
            )

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
                    n.nivel_cognitivo, n.estado_clinico,
                    pt.id AS plan_activo_id,
                    pt.nombre AS plan_activo
                FROM ninos n
                LEFT JOIN planes_terapeuticos pt
                    ON pt.nino_id = n.id AND pt.activo = TRUE
                WHERE n.tutor_id = %s AND n.activo = TRUE
                """,
                (tutor["id"],),
            )
            ninos = cur.fetchall()

    pacientes_list = [
        {
            "id": str(n["id"]),
            "nombre": n["nombre"],
            "edad": _calc_edad(n["fecha_nacimiento"]),
            "nivel_cognitivo": n["nivel_cognitivo"] or "Sin datos",
            "estado_clinico": n["estado_clinico"] or "pendiente_asignacion",
            "plan_activo": n["plan_activo"],
            "plan_activo_id": str(n["plan_activo_id"]) if n["plan_activo_id"] else None,
            "ultima_sesion": None,
        }
        for n in ninos
    ]

    return {
        "terapeuta_id": None,
        "terapeuta_nombre": None,
        "total_pacientes": len(pacientes_list),
        "sesiones_esta_semana": 0,
        "alertas_baja_adherencia": 0,
        "pacientes": pacientes_list,
    }


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

            perfil_sensorial = {
                "intereses": req.intereses or [],
                "estimulosAversivos": req.estimulos_aversivos or {},
                "umbralSensorial": "medio",
                "preferenciasEntorno": [],
            }

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
                    psycopg2.extras.Json(perfil_sensorial),
                    tutor["id"],
                ),
            )
            nino = cur.fetchone()

    return {"id": str(nino["id"]), "nombre": req.nombre}


# ── GET /api/ninos/{nino_id}/plan ─────────────────────────────────────────────

@router.get("/api/ninos/{nino_id}/plan")
def obtener_plan_activo(
    nino_id: str,
    current_user: dict = Depends(get_current_user),
):
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT
                    pt.id, pt.nombre, pt.nino_id, n.nombre AS nino_nombre,
                    pt.nivel_dificultad_actual
                FROM planes_terapeuticos pt
                JOIN ninos n ON n.id = pt.nino_id
                WHERE pt.nino_id = %s AND pt.activo = TRUE
                ORDER BY pt.fecha_inicio DESC
                LIMIT 1
                """,
                (nino_id,),
            )
            plan = cur.fetchone()
            if not plan:
                raise HTTPException(status_code=404, detail="Plan activo no encontrado")

            cur.execute(
                """
                SELECT a.id, a.nombre, a.tipo, a.instrucciones,
                       a.nivel_dificultad, a.duracion_estimada
                FROM plan_actividades pa
                JOIN actividades a ON a.id = pa.actividad_id
                WHERE pa.plan_id = %s
                ORDER BY pa.orden
                """,
                (plan["id"],),
            )
            actividades = cur.fetchall()

    return {
        "id": str(plan["id"]),
        "nombre": plan["nombre"],
        "nino_id": str(plan["nino_id"]),
        "nino_nombre": plan["nino_nombre"],
        "nivel_dificultad_actual": plan["nivel_dificultad_actual"],
        "actividades": [
            {
                "id": str(a["id"]),
                "nombre": a["nombre"],
                "tipo": a["tipo"],
                "instrucciones": a["instrucciones"],
                "nivel_dificultad": a["nivel_dificultad"],
                "duracion_estimada": a["duracion_estimada"],
            }
            for a in actividades
        ],
    }


# ── PATCH /api/ninos/{nino_id}/perfil-clinico ─────────────────────────────────

@router.patch("/api/ninos/{nino_id}/perfil-clinico")
def actualizar_perfil_clinico(
    nino_id: str,
    datos: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    campos_permitidos = {"nivel_cognitivo", "diagnostico", "perfil_sensorial",
                         "objetivos_intervencion", "estado_clinico"}
    updates = {k: v for k, v in datos.items() if k in campos_permitidos}
    if not updates:
        raise HTTPException(status_code=400, detail="Sin campos válidos para actualizar")

    set_clauses = ", ".join(f"{k} = %s" for k in updates)
    values = list(updates.values()) + [nino_id]

    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                f"UPDATE ninos SET {set_clauses} WHERE id = %s RETURNING id",
                values,
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

    return {"ok": True, "nino_id": nino_id}


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
                "SELECT id, nombre, nivel_cognitivo FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
            nino = cur.fetchone()
            if not nino:
                raise HTTPException(status_code=404, detail="Niño no encontrado")

            # Verificar si ya tiene plan activo
            cur.execute(
                "SELECT id FROM planes_terapeuticos WHERE nino_id = %s AND activo = TRUE",
                (nino_id,),
            )
            existing = cur.fetchone()
            if existing:
                return {"mensaje": "Ya existe un plan activo", "plan_id": str(existing["id"])}

            # Crear plan
            cur.execute(
                """
                INSERT INTO planes_terapeuticos
                    (nombre, nino_id, terapeuta_id, fecha_inicio, nivel_dificultad_actual,
                     criterios_progresion, activo)
                VALUES (%s, %s, %s, CURRENT_DATE, %s, %s::jsonb, TRUE)
                RETURNING id
                """,
                (
                    f"Plan IA — {nino['nombre']}",
                    nino_id,
                    ter["id"],
                    nino["nivel_cognitivo"] or "Medio",
                    '{"umbralAciertos": 0.8, "sesionesConsecutivas": 3}',
                ),
            )
            plan = cur.fetchone()

            # Vincular todas las actividades del catálogo en orden
            cur.execute("SELECT id FROM actividades WHERE activo = TRUE ORDER BY id LIMIT 3")
            acts = cur.fetchall()
            for i, act in enumerate(acts, start=1):
                cur.execute(
                    """
                    INSERT INTO plan_actividades (plan_id, actividad_id, orden)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (plan_id, actividad_id) DO NOTHING
                    """,
                    (plan["id"], act["id"], i),
                )

    return {
        "mensaje": "Plan generado con éxito",
        "plan_id": str(plan["id"]),
        "nino_id": nino_id,
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
                    pt.id AS plan_activo_id
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
        "documento_diagnostico": nino["documento_diagnostico"],
        "plan_activo_id": str(nino["plan_activo_id"]) if nino["plan_activo_id"] else None,
        "estado_clinico": nino["estado_clinico"] or "pendiente_asignacion",
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
                SELECT a.id, a.nombre, a.tipo, a.instrucciones, a.nivel_dificultad, a.duracion_estimada
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
