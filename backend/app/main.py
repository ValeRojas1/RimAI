from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Nuevos routers (Hexagonal)
from app.adapters.inbound.api.auth_controller import router as auth_router
from app.adapters.inbound.api.admin_controller import router as admin_router
from app.adapters.inbound.api.patient_controller import router as patient_router
from app.adapters.inbound.api.ai_controller import router as ai_router
from app.adapters.inbound.api.scq_controller import router as scq_router
from app.adapters.inbound.api.plan_controller import router as plan_router
from app.adapters.inbound.api.seguimiento_controller import router as seguimiento_router
from app.adapters.inbound.api.reportes_controller import router as reportes_router
from app.adapters.inbound.api.dashboard_controller import router as dashboard_router

app = FastAPI(
    title="RimAI API (Hexagonal)",
    description="Plataforma terapéutica adaptativa IA para niños con TEA",
    version="1.0.0",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(dashboard_router)   # /api/dashboard/* y /api/ninos/*
app.include_router(patient_router) # /api/v1/perfiles
app.include_router(scq_router)     # /api/v1/admision
app.include_router(plan_router)    # /api/v1/planes
app.include_router(seguimiento_router) # /api/v1/seguimiento
app.include_router(reportes_router)    # /api/v1/reportes
app.include_router(ai_router)
app.include_router(admin_router)

@app.get("/")
def root():
    return {"status": "ok", "api": "RimAI", "version": "1.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}
