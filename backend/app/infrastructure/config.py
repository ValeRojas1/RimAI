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

_JWT_SECRET_ENV_NAMES = (
    "JWT_SECRET",
    "JWT_SECRET_KEY",
    "SECRET_KEY",
    "jwt_secret",  # error comun al pegar en Railway
)
_DATABASE_URL_ENV_NAMES = ("DATABASE_URL", "DATABASE_PRIVATE_URL")


def test_defaults_allowed() -> bool:
    return _TEST_DEFAULTS_ALLOWED


def _first_env_value(names: tuple[str, ...]) -> str | None:
    for name in names:
        value = (os.getenv(name) or "").strip()
        if value:
            return value
    return None


def _is_railway_runtime() -> bool:
    return bool(
        os.getenv("RAILWAY_ENVIRONMENT")
        or os.getenv("RAILWAY_PUBLIC_DOMAIN")
        or os.getenv("RAILWAY_SERVICE_ID")
    )


def _railway_setup_hint(missing: list[str]) -> str:
    if not _is_railway_runtime():
        return " Configure .env o consulte .env.example."
    hints = []
    if "JWT_SECRET" in missing:
        hints.append(
            "En Railway → Variables del servicio API, agregue JWT_SECRET "
            "(ej.: openssl rand -hex 32)."
        )
    if "DATABASE_URL" in missing:
        hints.append(
            "En Railway, vincule el servicio PostgreSQL al backend para inyectar DATABASE_URL."
        )
    return " " + " ".join(hints)


def _require(name: str, value: str | None) -> str:
    if value:
        return value
    if _TEST_DEFAULTS_ALLOWED:
        if name == "JWT_SECRET":
            return _first_env_value(_JWT_SECRET_ENV_NAMES) or "test-jwt-secret-rimai-pytest-only"
        if name == "DATABASE_URL":
            return (
                _resolve_database_url()
                or "postgresql://rimai_user:rimai_secure_2026@localhost:5432/rimai_db"
            )
    raise RuntimeError(
        f"Variable de entorno obligatoria no definida: {name}."
        f"{_railway_setup_hint([name])}"
    )


def _resolve_database_url() -> str | None:
    url = _first_env_value(_DATABASE_URL_ENV_NAMES)
    if url:
        return url
    user = (os.getenv("PGUSER") or os.getenv("POSTGRES_USER") or "").strip()
    password = (os.getenv("PGPASSWORD") or os.getenv("POSTGRES_PASSWORD") or "").strip()
    host = (os.getenv("PGHOST") or os.getenv("POSTGRES_HOST") or "").strip()
    port = (os.getenv("PGPORT") or os.getenv("POSTGRES_PORT") or "5432").strip()
    database = (os.getenv("PGDATABASE") or os.getenv("POSTGRES_DB") or "").strip()
    if user and password and host and database:
        return f"postgresql://{user}:{password}@{host}:{port}/{database}"
    return None


def _resolve_jwt_secret() -> str | None:
    return _first_env_value(_JWT_SECRET_ENV_NAMES)


def _jwt_secret_diagnostic() -> str:
    details: list[str] = []
    for name in _JWT_SECRET_ENV_NAMES:
        raw = os.getenv(name)
        if raw is None:
            details.append(f"{name}=ausente")
        elif not raw.strip():
            details.append(f"{name}=vacia")
        else:
            details.append(f"{name}=ok({len(raw.strip())} chars)")
    similar = sorted(
        key for key in os.environ if "jwt" in key.lower() or key.lower() == "secret_key"
    )
    if similar:
        details.append(f"claves_similares={','.join(similar)}")
    return " Diagnostico JWT: " + "; ".join(details) + "."


def validate_startup_config() -> None:
    """Falla al arranque si faltan variables críticas (evita 500 en login)."""
    missing: list[str] = []
    if not _resolve_jwt_secret():
        missing.append("JWT_SECRET")
    if not _resolve_database_url():
        missing.append("DATABASE_URL")
    if missing:
        extra = _jwt_secret_diagnostic() if "JWT_SECRET" in missing else ""
        raise RuntimeError(
            f"Variables obligatorias no definidas: {', '.join(missing)}."
            f"{extra}"
            f"{_railway_setup_hint(missing)}"
        )


def get_jwt_secret() -> str:
    return _require("JWT_SECRET", _resolve_jwt_secret())


def get_jwt_algorithm() -> str:
    return "HS256"


def get_database_url() -> str:
    return _require("DATABASE_URL", _resolve_database_url())


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
    return os.getenv("ALLOW_PUBLIC_REGISTER", "true").lower() in ("1", "true", "yes")


def get_db_pool_min() -> int:
    return int(os.getenv("DB_POOL_MIN", "2"))


def get_db_pool_max() -> int:
    return int(os.getenv("DB_POOL_MAX", "10"))
