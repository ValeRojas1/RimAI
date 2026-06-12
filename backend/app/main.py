from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
import psycopg2

from app.adapters.inbound.api.auth_controller import router as auth_router
from app.adapters.inbound.api.admin_controller import router as admin_router
from app.adapters.inbound.api.patient_controller import router as patient_router
from app.adapters.inbound.api.ai_controller import router as ai_router
from app.adapters.inbound.api.scq_controller import router as scq_router
from app.adapters.inbound.api.plan_controller import router as plan_router
from app.adapters.inbound.api.seguimiento_controller import router as seguimiento_router
from app.adapters.inbound.api.reportes_controller import router as reportes_router
from app.adapters.inbound.api.dashboard_controller import router as dashboard_router
from app.adapters.inbound.api.exception_handlers import (
    http_exception_handler,
    psycopg2_exception_handler,
    unhandled_exception_handler,
    validation_exception_handler,
)
from app.infrastructure.config import get_cors_origins, validate_startup_config
from app.infrastructure.database import close_db_pool, init_db_pool
from app.infrastructure.rate_limit import limiter

app = FastAPI(
    title="RimAI API (Hexagonal)",
    description="Plataforma terapéutica adaptativa IA para niños con TEA",
    version="1.0.0",
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(psycopg2.Error, psycopg2_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)


@app.on_event("startup")
def on_startup():
    validate_startup_config()
    init_db_pool()


@app.on_event("shutdown")
def on_shutdown():
    close_db_pool()


app.include_router(auth_router)
app.include_router(dashboard_router)
app.include_router(patient_router)
app.include_router(scq_router)
app.include_router(plan_router)
app.include_router(seguimiento_router)
app.include_router(reportes_router)
app.include_router(ai_router)
app.include_router(admin_router)


@app.get("/")
def root():
    return {"status": "ok", "api": "RimAI", "version": "1.0.0"}


@app.get("/health")
def health():
    return {"status": "healthy"}
