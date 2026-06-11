"""Pool de conexiones PostgreSQL compartido (MEJ-010)."""
from contextlib import contextmanager
from typing import Iterator

import psycopg2
from psycopg2.extensions import connection as PgConnection
from psycopg2.pool import ThreadedConnectionPool

from app.infrastructure.config import get_database_url, get_db_pool_max, get_db_pool_min

_pool: ThreadedConnectionPool | None = None


def init_db_pool() -> None:
    global _pool
    if _pool is not None:
        return
    _pool = ThreadedConnectionPool(
        minconn=get_db_pool_min(),
        maxconn=get_db_pool_max(),
        dsn=get_database_url(),
    )


def close_db_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None


@contextmanager
def get_connection() -> Iterator[PgConnection]:
    """Context manager: commit al éxito, rollback ante error, devuelve conexión al pool."""
    if _pool is None:
        init_db_pool()
    assert _pool is not None
    conn = _pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _pool.putconn(conn)
