import os
from typing import Optional

import psycopg2
from psycopg2.extras import RealDictCursor

from app.application.ports.user_repository import IUserRepository
from app.domain.entities.user import RoleEnum, Therapist, User


class PostgresUserRepository(IUserRepository):
    def __init__(self):
        self.database_url = os.getenv(
            "DATABASE_URL",
            "postgresql://rimai_user:rimai_secure_2026@db:5432/rimai_db",
        )

    def _connect(self):
        return psycopg2.connect(self.database_url)

    def get_by_email(self, email: str) -> Optional[User]:
        with self._connect() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, nombre, email, password_hash, rol, created_at
                    FROM usuarios
                    WHERE lower(email) = lower(%s) AND activo = TRUE
                    """,
                    (email,),
                )
                row = cur.fetchone()

        if not row:
            return None

        role = RoleEnum(row["rol"])
        data = {
            "id": str(row["id"]),
            "email": row["email"],
            "hashed_password": row["password_hash"],
            "role": role,
            "nombre_completo": row["nombre"],
            "created_at": row["created_at"],
        }
        if role == RoleEnum.TERAPEUTA:
            return Therapist(**data)
        return User(**data)

    def create_family_user(self, user: User) -> User:
        with self._connect() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO usuarios (nombre, email, password_hash, rol, activo)
                    VALUES (%s, %s, %s, 'padre_tutor', TRUE)
                    RETURNING id, nombre, email, password_hash, rol, created_at
                    """,
                    (user.nombre_completo, user.email, user.hashed_password),
                )
                row = cur.fetchone()
                cur.execute(
                    """
                    INSERT INTO padres_tutores (usuario_id)
                    VALUES (%s)
                    ON CONFLICT (usuario_id) DO NOTHING
                    """,
                    (row["id"],),
                )

        return User(
            id=str(row["id"]),
            email=row["email"],
            hashed_password=row["password_hash"],
            role=RoleEnum(row["rol"]),
            nombre_completo=row["nombre"],
            created_at=row["created_at"],
        )

    def create_therapist(self, therapist: Therapist) -> Therapist:
        with self._connect() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    INSERT INTO usuarios (nombre, email, password_hash, rol, activo)
                    VALUES (%s, %s, %s, 'terapeuta', TRUE)
                    RETURNING id, nombre, email, password_hash, rol, created_at
                    """,
                    (
                        therapist.nombre_completo,
                        therapist.email,
                        therapist.hashed_password,
                    ),
                )
                row = cur.fetchone()
                cur.execute(
                    """
                    INSERT INTO terapeutas (usuario_id, especialidad, colegiatura)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (usuario_id) DO UPDATE SET
                        especialidad = EXCLUDED.especialidad,
                        colegiatura = EXCLUDED.colegiatura
                    """,
                    (
                        row["id"],
                        therapist.especialidad,
                        therapist.numero_colegiatura,
                    ),
                )

        return Therapist(
            id=str(row["id"]),
            email=row["email"],
            hashed_password=row["password_hash"],
            role=RoleEnum(row["rol"]),
            nombre_completo=row["nombre"],
            created_at=row["created_at"],
            especialidad=therapist.especialidad,
            numero_colegiatura=therapist.numero_colegiatura,
        )

    def get_by_id(self, user_id: str) -> Optional[User]:
        with self._connect() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id, nombre, email, password_hash, rol, created_at
                    FROM usuarios
                    WHERE id = %s AND activo = TRUE
                    """,
                    (user_id,),
                )
                row = cur.fetchone()

        if not row:
            return None

        return User(
            id=str(row["id"]),
            email=row["email"],
            hashed_password=row["password_hash"],
            role=RoleEnum(row["rol"]),
            nombre_completo=row["nombre"],
            created_at=row["created_at"],
        )
