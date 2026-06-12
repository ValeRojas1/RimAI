"""Configuración centralizada desde variables de entorno."""
import os

_TEST_DEFAULTS_ALLOWED = (
    os.getenv("PYTEST_CURRENT_TEST") is not None
    or os.getenv("RIMAI_ALLOW_TEST_DEFAULTS") == "1"
)

_DEV_CORS_ORIGINS = (
    "http://localhost:3000,"
    "http://localhost:8000,"
    "http://127.0.0.1:8000,"
    "http://10.0.2.2:8000,"
    "https://rimai-production.up.railway.app"
)


def test_defaults_allowed() -> bool:
    return _TEST_DEFAULTS_ALLOWED


def _require(name: str, value: str | None) -> str:
    if value:
        return value
    if _TEST_DEFAULTS_ALLOWED:
        if name == "JWT_SECRET":
            return os.getenv("JWT_SECRET") or "test-jwt-secret-rimai-pytest-only"
        if name == "DATABASE_URL":
            return (
                os.getenv("DATABASE_URL")
                or "postgresql://rimai_user:rimai_secure_2026@localhost:5432/rimai_db"
            )
    raise RuntimeError(
        f"Variable de entorno obligatoria no definida: {name}. "
        "Configure .env o consulte .env.example."
    )


def get_jwt_secret() -> str:
    return _require("JWT_SECRET", os.getenv("JWT_SECRET"))


def get_jwt_algorithm() -> str:
    return "HS256"


def get_database_url() -> str:
    return _require("DATABASE_URL", os.getenv("DATABASE_URL"))


def _infer_railway_cors_origins() -> list[str] | None:
    """Orígenes inferidos de variables que Railway inyecta en cada despliegue."""
    origins: list[str] = []
    domain = (os.getenv("RAILWAY_PUBLIC_DOMAIN") or "").strip()
    static_url = (os.getenv("RAILWAY_STATIC_URL") or "").strip().rstrip("/")
    if domain:
        origins.append(f"https://{domain}")
    if static_url and static_url not in origins:
        origins.append(static_url)
    return origins or None


def get_cors_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS")
    if raw:
        return [origin.strip() for origin in raw.split(",") if origin.strip()]
    if _TEST_DEFAULTS_ALLOWED:
        raw = _DEV_CORS_ORIGINS
        return [origin.strip() for origin in raw.split(",") if origin.strip()]
    railway_origins = _infer_railway_cors_origins()
    if railway_origins:
        return railway_origins
    raise RuntimeError(
        "Variable de entorno obligatoria no definida: CORS_ORIGINS. "
        "Configure orígenes permitidos separados por coma."
    )


def evaluar_alertas_en_resumen() -> bool:
    return os.getenv("EVALUAR_ALERTAS_EN_RESUMEN", "false").lower() in ("1", "true", "yes")


def allow_public_register() -> bool:
    default = "true" if _TEST_DEFAULTS_ALLOWED else "false"
    return os.getenv("ALLOW_PUBLIC_REGISTER", default).lower() in ("1", "true", "yes")


def get_db_pool_min() -> int:
    return int(os.getenv("DB_POOL_MIN", "2"))


def get_db_pool_max() -> int:
    return int(os.getenv("DB_POOL_MAX", "10"))
