import os
import psycopg2
from psycopg2.extras import RealDictCursor
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from passlib.context import CryptContext

from app.application.usecases.therapist_usecases import TherapistUseCases
from .dependencies import get_therapist_use_cases, get_current_user

router = APIRouter(prefix="/api/admin", tags=["admin"])

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
)

def _conn():
    return psycopg2.connect(DATABASE_URL)

class TherapistCreateRequest(BaseModel):
    nombre_completo: str
    email: str
    password: str
    especialidad: str
    numero_colegiatura: str

class UsuarioCreateRequest(BaseModel):
    nombre: str
    email: str
    password: str
    rol: str
    especialidad: Optional[str] = None
    colegiatura: Optional[str] = None

class ActualizarEstadoUsuarioRequest(BaseModel):
    activo: bool

# Backwards compatibility /api/admin/terapeutas
@router.post("/terapeutas")
def create_therapist(request: TherapistCreateRequest, current_user: dict = Depends(get_current_user), uc: TherapistUseCases = Depends(get_therapist_use_cases)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
    
    try:
        therapist = uc.register_therapist(
            email=request.email,
            password=request.password,
            nombre_completo=request.nombre_completo,
            especialidad=request.especialidad,
            numero_colegiatura=request.numero_colegiatura
        )
        return {"id": therapist.id, "email": therapist.email, "status": "created"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/estadisticas")
def obtener_estadisticas(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
    
    try:
        with _conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # 1. Total terapeutas
                cur.execute("SELECT COUNT(*) AS cnt FROM terapeutas")
                total_terapeutas = cur.fetchone()["cnt"] or 0
                
                # 2. Total familias
                cur.execute("SELECT COUNT(*) AS cnt FROM padres_tutores")
                total_familias = cur.fetchone()["cnt"] or 0
                
                # 3. Total ninos
                cur.execute("SELECT COUNT(*) AS cnt FROM ninos WHERE activo = TRUE")
                total_ninos = cur.fetchone()["cnt"] or 0
                
                # 4. Total sesiones completadas
                cur.execute("SELECT COUNT(*) AS cnt FROM sesiones WHERE estado = 'completada'")
                total_sesiones = cur.fetchone()["cnt"] or 0
                
                return {
                    "total_terapeutas": total_terapeutas,
                    "total_familias": total_familias,
                    "total_ninos": total_ninos,
                    "total_sesiones": total_sesiones
                }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno del servidor: {str(e)}")

@router.get("/usuarios")
def listar_usuarios(current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
    
    try:
        with _conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, nombre, email, rol, activo, created_at
                    FROM usuarios
                    ORDER BY created_at DESC
                    """
                )
                rows = cur.fetchall()
                
                result = []
                for r in rows:
                    result.append({
                        "id": str(r["id"]),
                        "nombre": r["nombre"],
                        "email": r["email"],
                        "rol": str(r["rol"]),
                        "activo": bool(r["activo"]),
                        "created_at": r["created_at"].isoformat() if r["created_at"] else None
                    })
                return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno al listar usuarios: {str(e)}")

@router.post("/usuarios")
def crear_usuario(request: UsuarioCreateRequest, current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
        
    try:
        hashed_password = pwd_context.hash(request.password)
        with _conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Verificar si el correo ya existe
                cur.execute("SELECT id FROM usuarios WHERE lower(email) = lower(%s)", (request.email,))
                if cur.fetchone():
                    raise HTTPException(status_code=400, detail="El correo ya está registrado")
                
                # Insertar usuario principal
                cur.execute(
                    """
                    INSERT INTO usuarios (nombre, email, password_hash, rol, activo)
                    VALUES (%s, %s, %s, %s, TRUE)
                    RETURNING id, nombre, email, rol, activo, created_at
                    """,
                    (request.nombre, request.email, hashed_password, request.rol)
                )
                row = cur.fetchone()
                usuario_id = row["id"]
                
                # Crear perfiles secundarios correspondientes
                if request.rol == "terapeuta":
                    cur.execute(
                        """
                        INSERT INTO terapeutas (usuario_id, especialidad, colegiatura)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (usuario_id) DO NOTHING
                        """,
                        (usuario_id, request.especialidad or "General", request.colegiatura)
                    )
                elif request.rol in ["padre_tutor", "tutor"]:
                    cur.execute(
                        """
                        INSERT INTO padres_tutores (usuario_id)
                        VALUES (%s)
                        ON CONFLICT (usuario_id) DO NOTHING
                        """,
                        (usuario_id,)
                    )
                
                conn.commit()
                
                return {
                    "id": str(row["id"]),
                    "nombre": row["nombre"],
                    "email": row["email"],
                    "rol": str(row["rol"]),
                    "activo": bool(row["activo"]),
                    "created_at": row["created_at"].isoformat() if row["created_at"] else None
                }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno al crear usuario: {str(e)}")

@router.patch("/usuarios/{usuario_id}/status")
def actualizar_estado_usuario(usuario_id: str, request: ActualizarEstadoUsuarioRequest, current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
        
    if str(current_user.get("id")) == usuario_id:
        raise HTTPException(status_code=400, detail="No puedes desactivar tu propia cuenta")
        
    try:
        with _conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id FROM usuarios WHERE id = %s", (usuario_id,))
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Usuario no encontrado")
                    
                cur.execute(
                    """
                    UPDATE usuarios
                    SET activo = %s, updated_at = NOW()
                    WHERE id = %s
                    RETURNING id, nombre, email, rol, activo, created_at
                    """,
                    (request.activo, usuario_id)
                )
                row = cur.fetchone()
                conn.commit()
                
                return {
                    "id": str(row["id"]),
                    "nombre": row["nombre"],
                    "email": row["email"],
                    "rol": str(row["rol"]),
                    "activo": bool(row["activo"]),
                    "created_at": row["created_at"].isoformat() if row["created_at"] else None
                }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al actualizar estado: {str(e)}")

@router.delete("/usuarios/{usuario_id}")
def eliminar_usuario(usuario_id: str, current_user: dict = Depends(get_current_user)):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")
        
    if str(current_user.get("id")) == usuario_id:
        raise HTTPException(status_code=400, detail="No puedes eliminar tu propia cuenta de administrador")
        
    try:
        with _conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id, rol FROM usuarios WHERE id = %s", (usuario_id,))
                user = cur.fetchone()
                if not user:
                    raise HTTPException(status_code=404, detail="Usuario no encontrado")
                    
                rol = str(user["rol"])
                
                # Validaciones de Seguridad Clínica
                if rol == "terapeuta":
                    cur.execute("SELECT id FROM terapeutas WHERE usuario_id = %s", (usuario_id,))
                    terap = cur.fetchone()
                    if terap:
                        terapeuta_id = terap["id"]
                        cur.execute("SELECT COUNT(*) AS cnt FROM ninos WHERE terapeuta_id = %s", (terapeuta_id,))
                        pacientes_count = cur.fetchone()["cnt"] or 0
                        if pacientes_count > 0:
                            raise HTTPException(
                                status_code=409,
                                detail=f"No se puede eliminar: El terapeuta tiene {pacientes_count} paciente(s) asignado(s). En su lugar, desactiva la cuenta."
                            )
                elif rol in ["padre_tutor", "tutor"]:
                    cur.execute("SELECT id FROM padres_tutores WHERE usuario_id = %s", (usuario_id,))
                    tut = cur.fetchone()
                    if tut:
                        tutor_id = tut["id"]
                        cur.execute("SELECT COUNT(*) AS cnt FROM ninos WHERE tutor_id = %s", (tutor_id,))
                        ninos_count = cur.fetchone()["cnt"] or 0
                        if ninos_count > 0:
                            raise HTTPException(
                                status_code=409,
                                detail=f"No se puede eliminar: El tutor tiene {ninos_count} niño(s) registrado(s). En su lugar, desactiva la cuenta."
                            )
                
                cur.execute("DELETE FROM usuarios WHERE id = %s", (usuario_id,))
                conn.commit()
                
                return {"status": "ok", "message": "Usuario eliminado exitosamente"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno al eliminar usuario: {str(e)}")
