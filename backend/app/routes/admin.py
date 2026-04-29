from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import bcrypt

from app.database import get_db
from app.models import Usuario, RolUsuario, Terapeuta, PadreTutor, Nino, Sesion
from app.auth import get_current_admin
from app.schemas import UsuarioOut, CrearUsuarioAdminRequest, ActualizarEstadoUsuarioRequest, AdminEstadisticasOut

router = APIRouter(prefix="/api/admin", tags=["admin"])

@router.get("/estadisticas", response_model=AdminEstadisticasOut)
def obtener_estadisticas(
    db: Session = Depends(get_db),
    current_admin: Usuario = Depends(get_current_admin)
):
    """Retorna los contadores globales para el dashboard del admin."""
    total_terapeutas = db.query(Terapeuta).count()
    total_familias = db.query(PadreTutor).count()
    total_ninos = db.query(Nino).count()
    total_sesiones = db.query(Sesion).filter(Sesion.estado == 'completada').count()
    
    return AdminEstadisticasOut(
        total_terapeutas=total_terapeutas,
        total_familias=total_familias,
        total_ninos=total_ninos,
        total_sesiones=total_sesiones
    )

@router.get("/usuarios", response_model=List[UsuarioOut])
def listar_usuarios(
    db: Session = Depends(get_db),
    current_admin: Usuario = Depends(get_current_admin)
):
    """Lista todos los usuarios del sistema (solo admin)."""
    usuarios = db.query(Usuario).order_by(Usuario.created_at.desc()).all()
    
    # Mapear Enum a string para el output
    result = []
    for u in usuarios:
        result.append(UsuarioOut(
            id=str(u.id),
            nombre=u.nombre,
            email=u.email,
            rol=u.rol.value,
            activo=u.activo,
            created_at=u.created_at
        ))
    return result

@router.post("/usuarios", response_model=UsuarioOut)
def crear_usuario(
    request: CrearUsuarioAdminRequest,
    db: Session = Depends(get_db),
    current_admin: Usuario = Depends(get_current_admin)
):
    """Crea un usuario desde el panel admin."""
    user_exists = db.query(Usuario).filter(Usuario.email == request.email).first()
    if user_exists:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El correo ya está registrado",
        )
    
    salt = bcrypt.gensalt()
    hashed_password = bcrypt.hashpw(request.password.encode('utf-8'), salt).decode('utf-8')
    
    nuevo_usuario = Usuario(
        nombre=request.nombre,
        email=request.email,
        password_hash=hashed_password,
        rol=request.rol,
        activo=True
    )
    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)
    
    # Crear perfiles secundarios
    if request.rol == "terapeuta":
        from app.models import Terapeuta
        nuevo_terapeuta = Terapeuta(
            usuario_id=nuevo_usuario.id, 
            especialidad=request.especialidad or "General",
            colegiatura=request.colegiatura
        )
        db.add(nuevo_terapeuta)
        db.commit()
    elif request.rol in ["padre_tutor", "tutor"]:
        from app.models import PadreTutor
        nuevo_tutor = PadreTutor(usuario_id=nuevo_usuario.id)
        db.add(nuevo_tutor)
        db.commit()

    return UsuarioOut(
        id=str(nuevo_usuario.id),
        nombre=nuevo_usuario.nombre,
        email=nuevo_usuario.email,
        rol=nuevo_usuario.rol.value,
        activo=nuevo_usuario.activo,
        created_at=nuevo_usuario.created_at
    )

@router.patch("/usuarios/{usuario_id}/status", response_model=UsuarioOut)
def actualizar_estado_usuario(
    usuario_id: str,
    request: ActualizarEstadoUsuarioRequest,
    db: Session = Depends(get_db),
    current_admin: Usuario = Depends(get_current_admin)
):
    """Activa o desactiva un usuario existente."""
    if str(current_admin.id) == usuario_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No puedes desactivar tu propia cuenta"
        )
        
    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
        
    usuario.activo = request.activo
    db.commit()
    db.refresh(usuario)
    
    return UsuarioOut(
        id=str(usuario.id),
        nombre=usuario.nombre,
        email=usuario.email,
        rol=usuario.rol.value,
        activo=usuario.activo,
        created_at=usuario.created_at
    )

@router.delete("/usuarios/{usuario_id}")
def eliminar_usuario(
    usuario_id: str,
    db: Session = Depends(get_db),
    current_admin: Usuario = Depends(get_current_admin)
):
    """Elimina permanentemente un usuario si no tiene historial clínico dependiente."""
    if str(current_admin.id) == usuario_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No puedes eliminar tu propia cuenta de administrador"
        )
        
    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
        
    # Validaciones de Seguridad Clínica (Opción A)
    if usuario.rol.value == "terapeuta":
        terapeuta = db.query(Terapeuta).filter(Terapeuta.usuario_id == usuario.id).first()
        if terapeuta:
            pacientes_count = db.query(Nino).filter(Nino.terapeuta_id == terapeuta.id).count()
            if pacientes_count > 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"No se puede eliminar: El terapeuta tiene {pacientes_count} paciente(s) asignado(s). En su lugar, desactiva la cuenta."
                )
    
    elif usuario.rol.value in ["padre_tutor", "tutor"]:
        tutor = db.query(PadreTutor).filter(PadreTutor.usuario_id == usuario.id).first()
        if tutor:
            ninos_count = db.query(Nino).filter(Nino.tutor_id == tutor.id).count()
            if ninos_count > 0:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"No se puede eliminar: El tutor tiene {ninos_count} niño(s) registrado(s). En su lugar, desactiva la cuenta."
                )

    # Si pasa las validaciones o es admin, se puede borrar (Cascada borrará los perfiles)
    db.delete(usuario)
    db.commit()
    
    return {"status": "ok", "message": "Usuario eliminado exitosamente"}
