"""Manejadores globales de excepciones (MEJ-008)."""
import logging

import psycopg2
from fastapi import HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


def _error_body(detail: str, code: str, status_code: int) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={"detail": detail, "code": code},
    )


async def http_exception_handler(_request: Request, exc: HTTPException) -> JSONResponse:
    code = f"HTTP_{exc.status_code}"
    detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
    return _error_body(detail, code, exc.status_code)


async def validation_exception_handler(
    _request: Request, exc: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Datos de entrada inválidos.",
            "code": "VALIDATION_ERROR",
            "errors": exc.errors(),
        },
    )


async def psycopg2_exception_handler(_request: Request, exc: psycopg2.Error) -> JSONResponse:
    logger.exception("Error de base de datos: %s", exc)
    return _error_body(
        "Servicio de base de datos temporalmente no disponible.",
        "DATABASE_ERROR",
        503,
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    if isinstance(exc, HTTPException):
        return await http_exception_handler(request, exc)
    if isinstance(exc, RuntimeError) and "Variable de entorno obligatoria" in str(exc):
        logger.error("Configuración incompleta: %s", exc)
        return _error_body(
            "Servicio mal configurado. Contacte al administrador.",
            "CONFIG_ERROR",
            503,
        )
    logger.exception("Error interno no controlado: %s", exc)
    return _error_body(
        "Error interno del servidor.",
        "INTERNAL_ERROR",
        500,
    )
