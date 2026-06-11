# Implementación — Mejoras Alta Prioridad (FURPS+)

**Fecha:** 11 de junio de 2026  
**Referencia:** [`docs/02_plan_furps.md`](02_plan_furps.md) — Fase 1 (MEJ-001 a MEJ-012)

---

## Resumen

Se implementaron las 12 mejoras de prioridad **Alta** de forma incremental, sin modificar el esquema de base de datos ni reestructurar la arquitectura hexagonal (capas `domain/`, `application/`, `adapters/` intactas).

**Verificación:** `pytest backend/tests` → **28/28 passed** (11/06/2026).

---

## Cambios por ítem

### MEJ-001 — URL de reportes Flutter + alias legacy

| Qué | Por qué |
|-----|---------|
| `api_sync_repository.dart`: URL corregida a `/api/v1/reportes/{id}` | El cliente apuntaba a una ruta inexistente |
| `seguimiento_controller.py`: `GET /reportes/{patient_id}` delega al mismo handler | Compatibilidad con builds antiguos |

### MEJ-002 — Secretos JWT centralizados

| Qué | Por qué |
|-----|---------|
| Nuevo `app/infrastructure/config.py` con `get_jwt_secret()` | Eliminar fallback hardcodeado en código |
| `auth_usecases.py`, `dependencies.py` usan config | Una sola fuente de verdad |
| `.env.example` documenta `JWT_SECRET` obligatorio | Falla al arrancar en prod sin variable |

### MEJ-003 — DATABASE_URL centralizada

| Qué | Por qué |
|-----|---------|
| `get_database_url()` en config | Eliminar credenciales embebidas |
| `dashboard_controller.py`, `admin_controller.py`, `postgres_user_repository.py` migrados al pool | Mismo criterio en todos los accesos DB |

### MEJ-004 — CORS restringido

| Qué | Por qué |
|-----|---------|
| `main.py`: `allow_origins=get_cors_origins()` | Sustituir `["*"]` |
| Variable `CORS_ORIGINS` (comma-separated) en `.env.example` y `docker-compose.yml` | Configurable por entorno |

### MEJ-005 — Unificación sync offline

| Qué | Por qué |
|-----|---------|
| `POST /api/sesiones` sigue siendo la ruta canónica (sin cambios Flutter) | Flujo productivo intacto |
| `/api/v1/seguimiento/sincronizar` persiste vía repos PostgreSQL + headers `Deprecation` | Elimina divergencia mock; avisa migración |

### MEJ-006 — Repositorios PostgreSQL reales

| Repositorio | Persistencia |
|-------------|--------------|
| `PostgresSCQRepository` | `ninos.perfil_sensorial` (JSONB existente) |
| `PostgresSeguimientoRepository` | `sesiones` + `resultados_actividad` |
| `PostgresAuditoriaRepository` | `logs_auditoria` |
| `PostgresReportesRepository` | `alertas_clinicas` (tipo `adherencia`) |
| `PostgresPatientRepository` | `ninos` + perfiles en JSONB |
| `PostgresPlanRepository` | `planes_terapeuticos.criterios_progresion` |

**Nota:** Sin migraciones nuevas; reutiliza tablas y columnas JSONB ya presentes.

### MEJ-007 — SCQ delegado al caso de uso

| Qué | Por qué |
|-----|---------|
| Eliminado `_score_scq` duplicado de `scq_controller.py` | DRY; scoring único en `EvaluarCuestionarioSCQUseCase` |
| Controlador usa DI (`get_scq_use_cases`, `get_scq_repository`) | Respeta hexagonal |
| Puerto `ISCQRepository` extendido con `verify_tutor_owns_patient` y `authorize_send_to_therapist` | Operaciones de persistencia/autorización en adaptador |

### MEJ-008 — Manejadores globales de excepciones

| Qué | Por qué |
|-----|---------|
| Nuevo `exception_handlers.py` | Respuestas JSON uniformes `{detail, code}` |
| Handlers para `HTTPException`, `ValidationError`, `psycopg2.Error`, `Exception` | Sin stack traces al cliente |

### MEJ-009 — Alertas clínicas fuera del GET resumen

| Qué | Por qué |
|-----|---------|
| `_evaluar_alertas_clinicas` solo si `EVALUAR_ALERTAS_EN_RESUMEN=true` | Reduce carga en cada carga de dashboard |
| Default: `false` | Evaluación explícita vía `POST /api/dashboard/terapeuta/alertas/evaluar` |

### MEJ-010 — Pool de conexiones PostgreSQL

| Qué | Por qué |
|-----|---------|
| Nuevo `app/infrastructure/database.py` con `ThreadedConnectionPool` | Reutilizar conexiones (~43 usos en dashboard) |
| `init_db_pool()` / `close_db_pool()` en startup/shutdown de FastAPI | Ciclo de vida controlado |
| Variables `DB_POOL_MIN`, `DB_POOL_MAX` | Tunable por entorno |

### MEJ-011 — Exposición de excepciones saneada

| Qué | Por qué |
|-----|---------|
| `seguimiento_controller.py`, `reportes_controller.py`: log interno + mensaje genérico 500 | No filtrar detalles SQL/internos al cliente |

### MEJ-012 — Tests en CI

| Qué | Por qué |
|-----|---------|
| `.github/workflows/build-apk.yml`: jobs `backend-tests` y `flutter-tests` antes del build APK | Regresión automática |
| `backend/tests/conftest.py`: `RIMAI_ALLOW_TEST_DEFAULTS=1` para pytest local/CI | Tests sin .env de producción |

---

## Archivos nuevos

- `backend/app/infrastructure/config.py`
- `backend/app/infrastructure/database.py`
- `backend/app/adapters/inbound/api/exception_handlers.py`
- `backend/tests/conftest.py`
- `docs/03_mejoras_alta_prioridad.md`

## Archivos principales modificados

- Backend: `main.py`, `dependencies.py`, `auth_usecases.py`, controladores (`dashboard`, `scq`, `seguimiento`, `reportes`, `admin`), 6 repos `postgres_*.py`, entidades de dominio (IDs `Union[int, str]`)
- Frontend: `api_sync_repository.dart`
- DevOps: `.env.example`, `docker-compose.yml`, `.github/workflows/build-apk.yml`

---

## Variables de entorno nuevas / relevantes

```env
JWT_SECRET=...              # Obligatorio en producción
DATABASE_URL=...            # Obligatorio en producción
CORS_ORIGINS=...            # Lista separada por comas
DB_POOL_MIN=2
DB_POOL_MAX=10
EVALUAR_ALERTAS_EN_RESUMEN=false
RIMAI_ALLOW_TEST_DEFAULTS=1 # Solo tests
```

---

## Anti-regresión verificada

- Rutas HTTP existentes sin cambio de path (`/api/dashboard/*`, `/api/sesiones`, `/api/v1/auth/*`)
- Payload de sync offline Flutter sin cambios
- Tests unitarios backend: **28 passed**
- Scoring SCQ: mismos umbrales y tests sin modificar aserciones de puntaje
- Alias legacy `/api/v1/seguimiento/reportes/{id}` activo para clientes antiguos

---

## Pendiente / Fase 2

Las mejoras **Media** y **Baja** del plan (`docs/02_plan_furps.md`) no forman parte de este entregable.
