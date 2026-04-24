from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import router as auth_router
from app.routes.pacientes import router as dashboard_router

app = FastAPI(
    title="RimAI API",
    description="Plataforma terapéutica adaptativa IA para niños con TEA",
    version="1.0.0",
)

# CORS — permitir peticiones desde Flutter web y emuladores Android
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(dashboard_router)


@app.get("/")
def root():
    return {"status": "ok", "api": "RimAI", "version": "1.0.0"}


@app.get("/health")
def health():
    return {"status": "healthy"}
