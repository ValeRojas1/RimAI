"""Rate limiting para endpoints de autenticación (REM-011)."""
import os

from slowapi import Limiter
from slowapi.util import get_remote_address


def is_rate_limit_enabled() -> bool:
    if os.getenv("RIMAI_ALLOW_TEST_DEFAULTS") == "1":
        return False
    if os.getenv("PYTEST_CURRENT_TEST") is not None:
        return False
    return os.getenv("RATE_LIMIT_ENABLED", "true").lower() not in ("0", "false", "no")


limiter = Limiter(key_func=get_remote_address, enabled=is_rate_limit_enabled())
