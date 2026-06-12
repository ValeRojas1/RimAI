"""Tests de remediaciones OWASP críticas/altas (REM-001 a REM-015)."""
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.application.usecases.sincronizar_datos_usecase import SincronizarDatosUseCase
from app.domain.entities.actividad_ejecutada import ActividadEjecutada
from app.domain.entities.user import RoleEnum
from app.infrastructure.authorization import (
    autorizar_descarga_documento_clinico,
    campos_perfil_editables_por_rol,
    resolve_nino_id_for_clinical_file,
    verify_tutor_owns_patient,
)
from app.infrastructure.config import allow_public_register, get_jwt_algorithm


def test_campos_perfil_tutor_solo_perfil_sensorial():
    campos = campos_perfil_editables_por_rol("padre_tutor")
    assert campos == {"perfil_sensorial"}
    assert "diagnostico" not in campos


def test_campos_perfil_terapeuta_completos():
    campos = campos_perfil_editables_por_rol("terapeuta")
    assert "diagnostico" in campos
    assert "objetivos_intervencion" in campos


def test_jwt_algorithm_fijado_hs256():
    assert get_jwt_algorithm() == "HS256"


def test_allow_public_register_true_en_tests():
    assert allow_public_register() is True


@patch("app.infrastructure.authorization.get_connection")
def test_autorizar_acceso_nino_terapeuta_no_asignado(mock_conn):
    from app.infrastructure.authorization import autorizar_acceso_nino

    cur = MagicMock()
    cur.fetchone.side_effect = [
        {"terapeuta_id": "t-other", "tutor_id": "tu-1"},
        {"id": "t-self"},
    ]
    conn = MagicMock()
    conn.cursor.return_value.__enter__ = MagicMock(return_value=cur)
    conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.return_value.__enter__ = MagicMock(return_value=conn)
    mock_conn.return_value.__exit__ = MagicMock(return_value=False)

    with pytest.raises(HTTPException) as exc:
        autorizar_acceso_nino("nino-1", {"id": "u1", "role": "terapeuta"})
    assert exc.value.status_code == 403


@patch("app.application.usecases.sincronizar_datos_usecase.verify_tutor_owns_patient")
def test_sync_rechaza_paciente_ajeno(mock_verify):
    mock_verify.side_effect = lambda pid, tid: pid == "owned"
    uc = SincronizarDatosUseCase(MagicMock(), MagicMock())
    ts = datetime(2026, 1, 1, 12, 0, 0)
    base = dict(
        tiempo_empleado_segundos=10,
        nivel_apoyo_requerido=0,
        observaciones="",
        detonantes_presentados=[],
        completada=True,
        timestamp_local=ts,
    )
    actividades = [
        ActividadEjecutada(patient_id="owned", actividad_id="a1", plan_id="p1", **base),
        ActividadEjecutada(patient_id="foreign", actividad_id="a2", plan_id="p1", **base),
    ]
    with pytest.raises(ValueError, match="foreign"):
        uc.execute("tutor-u1", actividades)


@patch("app.infrastructure.authorization.get_connection")
def test_descarga_documento_terapeuta_paciente_pendiente(mock_conn):
    cur = MagicMock()
    cur.fetchone.side_effect = [
        {"terapeuta_id": None, "tutor_id": "tu-1"},
        {"id": "t-self"},
    ]
    conn = MagicMock()
    conn.cursor.return_value.__enter__ = MagicMock(return_value=cur)
    conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.return_value.__enter__ = MagicMock(return_value=conn)
    mock_conn.return_value.__exit__ = MagicMock(return_value=False)

    autorizar_descarga_documento_clinico(
        "nino-pendiente", {"id": "u1", "role": "terapeuta"}
    )


@patch("app.infrastructure.authorization.get_connection")
def test_descarga_documento_terapeuta_no_asignado_bloqueado(mock_conn):
    cur = MagicMock()
    cur.fetchone.side_effect = [
        {"terapeuta_id": "t-other", "tutor_id": "tu-1"},
        {"id": "t-self"},
    ]
    conn = MagicMock()
    conn.cursor.return_value.__enter__ = MagicMock(return_value=cur)
    conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.return_value.__enter__ = MagicMock(return_value=conn)
    mock_conn.return_value.__exit__ = MagicMock(return_value=False)

    with pytest.raises(HTTPException) as exc:
        autorizar_descarga_documento_clinico(
            "nino-ajeno", {"id": "u1", "role": "terapeuta"}
        )
    assert exc.value.status_code == 403


@patch("app.infrastructure.authorization.get_connection")
def test_resolve_nino_id_from_documentos_clinicos(mock_conn):
    cur = MagicMock()
    cur.fetchall.return_value = [
        {
            "id": "55555555-5555-5555-5555-555555555555",
            "perfil_sensorial": {
                "documentos_clinicos": {
                    "informe": {
                        "url": "/api/files/evaluations/abc123_informe.pdf",
                    }
                }
            },
        }
    ]
    conn = MagicMock()
    conn.cursor.return_value.__enter__ = MagicMock(return_value=cur)
    conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.return_value.__enter__ = MagicMock(return_value=conn)
    mock_conn.return_value.__exit__ = MagicMock(return_value=False)

    nino_id = resolve_nino_id_for_clinical_file("abc123_informe.pdf")
    assert nino_id == "55555555-5555-5555-5555-555555555555"


def test_role_enum_rechaza_valores_invalidos():
    from app.adapters.inbound.api.admin_controller import UsuarioCreateRequest
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        UsuarioCreateRequest(
            nombre="Test",
            email="t@test.com",
            password="secret",
            rol="superuser",
        )

    req = UsuarioCreateRequest(
        nombre="Test",
        email="t@test.com",
        password="secret",
        rol=RoleEnum.TERAPEUTA,
    )
    assert req.rol == RoleEnum.TERAPEUTA
