"""Fixtures globales: variables de entorno para tests sin secretos en código de producción."""
import os

os.environ.setdefault("RIMAI_ALLOW_TEST_DEFAULTS", "1")
os.environ.setdefault("JWT_SECRET", "test-jwt-secret-rimai-pytest-only")
os.environ.setdefault("DATABASE_URL", "postgresql://rimai_user:rimai_secure_2026@localhost:5432/rimai_db")
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")
os.environ.setdefault("ALLOW_PUBLIC_REGISTER", "true")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
