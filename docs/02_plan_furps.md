# Plan de Mejora FURPS+ — RimAI

**Fecha:** 11 de junio de 2026  
**Fuente:** [`docs/01_auditoria_furps.md`](01_auditoria_furps.md) (auditoría estática del 11/06/2026)  
**Objetivo:** Corregir debilidades identificadas sin romper flujos productivos actuales (`/api/dashboard/*`, `/api/ninos/*`, `/api/sesiones`, auth JWT, offline sync).

---

## Principios anti-regresión (aplican a todo el plan)

1. **Contrato primero:** antes de cambiar un endpoint, documentar request/response actual y añadir test de contrato o snapshot.
2. **Cambios incrementales:** mantener rutas legacy activas durante un ciclo de deprecación; usar alias en lugar de eliminar URLs consumidas por el cliente.
3. **Suite de regresión mínima:** ejecutar `pytest backend/tests` y `flutter test` en cada PR; smoke manual de login → dashboard → registro sesión offline → sync.
4. **Feature flags / toggles:** para cambios de comportamiento (p. ej. quitar evaluación de alertas del GET resumen), activar vía variable de entorno hasta validar en staging.
5. **Rollback:** despliegues atómicos; cambios de esquema DB solo con migraciones reversibles.

---

## Resumen por criticidad

| Prioridad | Ítems | Esfuerzo acumulado estimado |
|-----------|-------|----------------------------|
| **Alta** | 12 | ~6–8 semanas-persona |
| **Media** | 18 | ~8–10 semanas-persona |
| **Baja** | 11 | ~3–4 semanas-persona |

---

## Fase 1 — Prioridad Alta

Ordenados de mayor a menor criticidad dentro de la fase.

---

### MEJ-001 — Corregir URL de reportes en cliente Flutter

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-09 |
| **Descripción del cambio** | Actualizar `ApiSyncRepository.fetchReporte` para llamar a `/api/v1/reportes/{patient_id}` con los query params `inicio` y `fin` que ya envía el cliente. Opcionalmente añadir en backend un alias `GET /api/v1/seguimiento/reportes/{patient_id}` que delegue al mismo handler (sin eliminar la ruta existente) para compatibilidad con builds antiguos. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/adapters/output/api_sync_repository.dart`; opcional: `backend/app/adapters/inbound/api/reportes_controller.py`, `backend/app/main.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (4–8 h) |
| **Anti-regresión** | No modificar la firma de `fetchReporte` ni el modelo `ReporteAnalitico`; solo cambiar la URL. Mantener alias legacy si se añade en backend. |
| **Criterio de verificación** | (1) Petición HTTP del cliente responde 200 contra backend desplegado. (2) Test de integración o widget test mockeando respuesta JSON válida. (3) Flujo terapeuta → reporte analítico muestra datos sin excepción. (4) Builds anteriores siguen funcionando si se implementa alias. |

---

### MEJ-002 — Eliminar secretos JWT hardcodeados

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-08 |
| **Descripción del cambio** | Leer `JWT_SECRET` exclusivamente desde variable de entorno. Si falta al arrancar, lanzar error fatal con mensaje claro. Unificar lectura en un módulo `config.py` consumido por `auth_usecases.py` y `dependencies.py` (eliminar duplicación de constantes). |
| **Archivo(s) afectado(s)** | `backend/app/application/usecases/auth_usecases.py`; `backend/app/adapters/inbound/api/dependencies.py`; nuevo `backend/app/infrastructure/config.py` (o equivalente); `.env.example`; `docker-compose.yml` (ya define `JWT_SECRET`) |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (4–6 h) |
| **Anti-regresión** | Tokens emitidos con el mismo secret configurado en `.env` siguen siendo válidos; no cambiar algoritmo ni claims del JWT. Documentar en README la variable obligatoria. |
| **Criterio de verificación** | (1) API no arranca sin `JWT_SECRET`. (2) Login existente devuelve token decodable. (3) `/api/v1/auth/me` responde 200 con token válido. (4) Tests de auth pasan con secret inyectado en fixture. |

---

### MEJ-003 — Eliminar credenciales DB por defecto en código

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-10 |
| **Descripción del cambio** | Centralizar `DATABASE_URL` en módulo de configuración; eliminar strings fallback `postgresql://rimai_user:rimai_secure_2026@...` de controladores y repositorios. Fallar al arrancar si la variable no está definida (excepto en tests con override explícito). |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/dashboard_controller.py`; `backend/app/adapters/inbound/api/scq_controller.py`; `backend/app/adapters/inbound/api/admin_controller.py`; `backend/app/adapters/outbound/database/postgres_user_repository.py`; módulo config compartido |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (4–8 h) |
| **Anti-regresión** | `docker-compose.yml` ya inyecta `DATABASE_URL`; no cambiar esquema ni queries. Tests usan mock o `DATABASE_URL` de test en CI. |
| **Criterio de verificación** | (1) Grep del repo no encuentra credenciales embebidas. (2) `docker compose up` sigue levantando API conectada a PostgreSQL. (3) Endpoints dashboard responden igual que antes en entorno dev. |

---

### MEJ-004 — Restringir CORS a orígenes conocidos

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-09 |
| **Descripción del cambio** | Reemplazar `allow_origins=["*"]` por lista configurable vía env `CORS_ORIGINS` (comma-separated): dominio Railway de producción, `http://localhost:*` para dev, origen de emulador si aplica. Mantener métodos y headers actuales. |
| **Archivo(s) afectado(s)** | `backend/app/main.py`; `.env.example`; `docker-compose.yml` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (2–4 h) |
| **Anti-regresión** | Incluir explícitamente `https://rimai-production.up.railway.app` y URLs de desarrollo documentadas en `api_constants.dart`. No deshabilitar preflight en rutas existentes. |
| **Criterio de verificación** | (1) App Flutter en dispositivo/emulador puede consumir API. (2) Origen no autorizado recibe error CORS. (3) Login y dashboard funcionan en staging. |

---

### MEJ-005 — Unificar vía de sincronización offline (eliminar divergencia mock)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-10, R-15 (parcial) |
| **Descripción del cambio** | **Opción recomendada (sin romper cliente):** mantener `POST /api/sesiones` como ruta canónica (ya usada por Flutter). Marcar `POST /api/v1/seguimiento/sincronizar` como deprecated: implementar delegación interna que traduzca payload a la misma lógica/SQL de `crear_sesion`, o responder 410 con header `Deprecation` y documentar migración. No eliminar la ruta hasta confirmar que ningún cliente la usa. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/seguimiento_controller.py`; `backend/app/adapters/inbound/api/dashboard_controller.py` (extraer lógica compartida); `rimai_app/lib/adapters/output/api_sync_repository.dart` (verificar — ya usa `/api/sesiones`) |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **M** (2–3 días) |
| **Anti-regresión** | No cambiar payload de `ActividadLocal.toSesionPayload()`. Ejecutar sync offline manual: registrar actividad sin red → reconectar → verificar fila en PostgreSQL `sesiones`/`resultados_actividad`. |
| **Criterio de verificación** | (1) Sync Flutter sigue eliminando registros locales tras 2xx. (2) Datos aparecen en BD real. (3) Llamada a `/api/v1/seguimiento/sincronizar` produce mismo resultado que `/api/sesiones` o respuesta deprecated documentada. |

---

### MEJ-006 — Implementar repositorios PostgreSQL reales (sustituir mocks)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-07, R-15, S-10 |
| **Descripción del cambio** | Implementar persistencia PostgreSQL en adaptadores que hoy son in-memory, **priorizando los expuestos por rutas `/api/v1/*`**: (1) `PostgresSCQRepository`, (2) `PostgresSeguimientoRepository`, (3) `PostgresReportesRepository`, (4) `PostgresPatientRepository`, (5) `PostgresPlanRepository`, (6) `PostgresAuditoriaRepository`. Reutilizar SQL existente en `dashboard_controller.py` como referencia de esquema. Mantener interfaces de puertos sin cambios. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/outbound/database/postgres_*.py` (6 archivos); posibles nuevos tests en `backend/tests/`; migraciones SQL si faltan tablas |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **XL** (2–3 semanas) — implementar por repositorio en PRs separados |
| **Anti-regresión** | Un repositorio por PR. Mantener implementación in-memory renombrada como `InMemory*Repository` solo para tests unitarios. No tocar flujos de `dashboard_controller` hasta validar repos aisladamente. |
| **Criterio de verificación** | Por cada repo: (1) test de integración con PostgreSQL efímero (testcontainers o docker). (2) Reinicio de API no pierde datos escritos vía `/api/v1/*`. (3) Puertos/domain entities sin cambios breaking. (4) `pytest backend/tests` verde. |

**Sub-entregables recomendados (orden interno):**

| Sub-ID | Repositorio | Esfuerzo |
|--------|-------------|----------|
| MEJ-006a | `PostgresSCQRepository` | M |
| MEJ-006b | `PostgresSeguimientoRepository` | M |
| MEJ-006c | `PostgresReportesRepository` | M |
| MEJ-006d | `PostgresPatientRepository` | L |
| MEJ-006e | `PostgresPlanRepository` | L |
| MEJ-006f | `PostgresAuditoriaRepository` | S |

---

### MEJ-007 — Refactorizar SCQ: delegar en caso de uso y eliminar duplicación

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-08, S-11 |
| **Descripción del cambio** | Eliminar `_score_scq` duplicado en `scq_controller.py`. El controlador debe: validar rol → invocar `EvaluarCuestionarioSCQUseCase.execute()` → persistir vía `PostgresSCQRepository` (MEJ-006a) actualizando `perfil_sensorial` en `ninos` como hoy. Extraer persistencia del perfil a método del repositorio si conviene. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/scq_controller.py`; `backend/app/application/usecases/evaluar_cuestionario_scq_usecase.py`; `backend/app/adapters/inbound/api/dependencies.py`; `backend/app/adapters/outbound/database/postgres_scq_repository.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **M** (2 días) — depende de MEJ-006a |
| **Anti-regresión** | Mantener rutas `POST /api/v1/admision/`, `/scq`, `/{patient_id}/enviar-terapeuta` con mismos códigos HTTP y shape JSON. `backend/tests/test_scq_scoring.py` debe seguir pasando sin modificar aserciones de puntaje. |
| **Criterio de verificación** | (1) 6 tests SCQ en verde. (2) Envío SCQ desde app familia produce mismo puntaje/nivel que antes en casos de prueba manual. (3) Grep no encuentra `_score_scq` en controller. |

---

### MEJ-008 — Manejador global de excepciones FastAPI

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-11 |
| **Descripción del cambio** | Registrar handlers para: `HTTPException` (passthrough), `psycopg2.Error` → 503 con mensaje genérico, `ValidationError` → 422, `Exception` no capturada → 500 sin stack trace en body. Formato JSON uniforme: `{ "detail": "...", "code": "..." }`. |
| **Archivo(s) afectado(s)** | `backend/app/main.py`; nuevo `backend/app/adapters/inbound/api/exception_handlers.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (1 día) |
| **Anti-regresión** | No alterar status codes ya usados por el cliente (401, 403, 404, 422). Tests existentes de endpoints deben seguir esperando mismos códigos en casos nominales y de error de negocio. |
| **Criterio de verificación** | (1) Error DB simulado retorna JSON sin traceback. (2) Errores 403/404 de dashboard unchanged. (3) Log server-side sí registra excepción completa. |

---

### MEJ-009 — Dejar de evaluar alertas clínicas en cada GET `/api/dashboard/resumen`

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-05 |
| **Descripción del cambio** | Remover llamada a `_evaluar_alertas_clinicas(cur, ter["terapeuta_id"])` dentro de `resumen_terapeuta` (L1530). La evaluación debe ocurrir solo vía `POST /api/dashboard/terapeuta/alertas/evaluar` (existente L1728), trigger programado, o post-evento (fin de sesión). Añadir flag env `EVALUAR_ALERTAS_EN_RESUMEN=false` para rollback temporal. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/dashboard_controller.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (4–6 h) |
| **Anti-regresión** | El JSON de respuesta de `/api/dashboard/resumen` mantiene campos de alertas/riesgo ya calculados en BD; solo cambia cuándo se generan nuevas alertas. Documentar que el terapeuta debe invocar evaluación explícita o cron. |
| **Criterio de verificación** | (1) Tiempo de respuesta de resumen disminuye mediblemente (>30% en entorno con N pacientes). (2) POST `/alertas/evaluar` sigue creando alertas. (3) Dashboard Flutter carga sin cambios visuales en contador de alertas existentes. |

---

### MEJ-010 — Pool de conexiones PostgreSQL

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-09 |
| **Descripción del cambio** | Crear módulo `database.py` con `ThreadedConnectionPool` (min 2, max 10 configurable). Reemplazar `_conn()` en `dashboard_controller.py`, `scq_controller.py`, `admin_controller.py` y repos por `get_connection()` / context manager con `putconn`. |
| **Archivo(s) afectado(s)** | Nuevo `backend/app/infrastructure/database.py`; `dashboard_controller.py`; `scq_controller.py`; `admin_controller.py`; `postgres_user_repository.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **M** (2–3 días) |
| **Anti-regresión** | Misma semántica transaccional: commit/rollback por request. Prueba de carga ligera (50 req/s resumen) sin agotar conexiones PostgreSQL (`max_connections`). |
| **Criterio de verificación** | (1) Logs confirman reutilización de conexiones. (2) Todos los endpoints dashboard responden correctamente. (3) Sin fugas bajo prueba de concurrencia moderada. |

---

### MEJ-011 — Sanear exposición de excepciones en controladores hexagonales

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-12, R-13 |
| **Descripción del cambio** | En `seguimiento_controller.py` y `reportes_controller.py`, reemplazar `raise HTTPException(500, detail=str(e))` por log interno + respuesta genérica; dejar que MEJ-008 capture el resto. Preservar excepciones de negocio (`ValueError`) como 400/404 explícitos. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/seguimiento_controller.py`; `backend/app/adapters/inbound/api/reportes_controller.py` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **S** (2–4 h) |
| **Anti-regresión** | Status 500 sigue siendo 500; solo cambia el cuerpo del mensaje (sin filtrar internals). |
| **Criterio de verificación** | (1) Error forzado no expone nombre de tabla/SQL en response body. (2) Flujos nominales de reportes y sync sin cambios. |

---

### MEJ-012 — Añadir tests a CI antes del build APK

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-15 |
| **Descripción del cambio** | Extender `.github/workflows/build-apk.yml` con jobs paralelos: `pytest backend/tests -v` (con PostgreSQL service container o mocks) y `flutter test` en `rimai_app`. Fallar pipeline si tests fallan; build APK solo si ambos pasan. |
| **Archivo(s) afectado(s)** | `.github/workflows/build-apk.yml`; opcional: nuevo `.github/workflows/backend-tests.yml` |
| **Prioridad** | **Alta** |
| **Esfuerzo estimado** | **M** (1–2 días) |
| **Anti-regresión** | No modificar tests existentes salvo estabilización de fixtures; objetivo es detectar regresiones, no reescribir suite. |
| **Criterio de verificación** | (1) PR con test roto bloquea merge. (2) Pipeline verde en rama `develop` actual. (3) Artefacto APK sigue generándose. |

---

## Fase 2 — Prioridad Media

---

### MEJ-013 — Optimizar query resumen terapeuta (eliminar N+1)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-06, P-07, P-08 |
| **Descripción del cambio** | Reescribir consulta de pacientes en `resumen_terapeuta`: usar `LATERAL` o window functions para última sesión; precalcular riesgo de abandono en una query agregada o materialized view; eliminar bucle L1598–1614 que llama `_predecir_riesgo_abandono` por niño. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/dashboard_controller.py` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (3–4 días) |
| **Anti-regresión** | Test de snapshot JSON del resumen antes/después con dataset fijo en seed SQL; campos del response idénticos en estructura. |
| **Criterio de verificación** | (1) ≤3 queries por request de resumen (medido en log). (2) Snapshot JSON equivalente. (3) Dashboard Flutter sin cambios funcionales. |

---

### MEJ-014 — Registrar fallos de sync en SQLite

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-14 |
| **Descripción del cambio** | En `ApiSyncRepository.syncActividades`, ante error HTTP o excepción: incrementar `sync_attempts`, persistir `last_error` vía nuevo método en `ILocalDbPort`/`SqliteDbRepository`. Mostrar estado en `sync_status_widget.dart`. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/adapters/output/api_sync_repository.dart`; `rimai_app/lib/adapters/output/sqlite_db_repository.dart`; `rimai_app/lib/application/ports/local_db_port.dart`; `rimai_app/lib/adapters/input/screens/familia/sync_status_widget.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2 días) |
| **Anti-regresión** | Sync exitoso sigue eliminando registros; comportamiento feliz path unchanged. |
| **Criterio de verificación** | (1) Simular 503 → registro local permanece con `sync_attempts=1`. (2) Tras recuperar red, sync exitoso limpia registro. (3) Widget muestra estado pendiente/error. |

---

### MEJ-015 — Try/except con rollback en operaciones DB del dashboard

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-11 (complemento) |
| **Descripción del cambio** | Envolver bloques `with _conn()` mutantes en try/except con `conn.rollback()` en error; re-lanzar como HTTPException o dejar propagar a MEJ-008. Aplicar incrementalmente empezando por `crear_sesion`, `registrar_nino`, mutaciones de plan. |
| **Archivo(s) afectado(s)** | `backend/app/adapters/inbound/api/dashboard_controller.py` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **L** (1 semana, incremental) |
| **Anti-regresión** | Un endpoint por PR; verificar transacción atomicidad con test que fuerza fallo a mitad de operación. |
| **Criterio de verificación** | (1) Fallo mid-transaction no deja filas huérfanas. (2) Response codes unchanged en casos de validación. |

---

### MEJ-016 — Ocultar controles UI no implementados

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-10, F-12 |
| **Descripción del cambio** | Eliminar o comentar con flag `_kShowSocialLogin = false`: botones Google/Apple, enlace “¿Olvidaste tu contraseña?”, divisor “O CONTINÚA CON”. Preferir ocultar sobre mostrar SnackBar “próximamente”. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (2–3 h) |
| **Anti-regresión** | Flujo login email/password intacto; mismos campos y botón “Iniciar Sesión”. |
| **Criterio de verificación** | (1) Login manual funciona. (2) UI no muestra elementos ocultos. (3) `flutter test` pasa. |

---

### MEJ-017 — Centralizar design tokens PMV2 en pantallas

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-07, U-08 |
| **Descripción del cambio** | Reemplazar constantes `_kPrimary`, `_kBg`, etc. en `DashboardScreen`, `FamilyPlanScreen` y login por `Theme.of(context).colorScheme` y clases `PMV2Colors`. Unificar tipografía en `PMV2Theme` (decidir Inter vs Plus Jakarta Sans — documentar en theme). |
| **Archivo(s) afectado(s)** | `rimai_app/lib/adapters/input/screens/dashboard/dashboard_screen.dart`; `rimai_app/lib/adapters/input/screens/familia/family_plan_screen.dart`; `rimai_app/lib/adapters/input/screens/auth/login_screen.dart`; `rimai_app/lib/core/theme/app_theme.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2–3 días) |
| **Anti-regresión** | Cambio solo visual; capturas de pantalla antes/después en PR. No alterar layout ni navegación. |
| **Criterio de verificación** | (1) No quedan colores hardcodeados duplicados en pantallas migradas. (2) Contraste WCAG AA en textos principales. (3) Smoke test visual login + dashboard. |

---

### MEJ-018 — Capa de mensajes de error amigables

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-11 |
| **Descripción del cambio** | Crear `ErrorMessageMapper` (o extensión en providers) que traduzca códigos HTTP, `DioException` y `SessionExpiredException` a textos clínicos en español. Usar en `dashboard_screen.dart` y `family_plan_screen.dart` en lugar de `err.toString()`. |
| **Archivo(s) afectado(s)** | Nuevo `rimai_app/lib/core/utils/error_message_mapper.dart`; `dashboard_screen.dart`; `family_plan_screen.dart`; opcionalmente `dashboard_providers.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (1 día) |
| **Anti-regresión** | Errores conocidos (401, 403, 404, sin conexión) mapeados; desconocidos muestran mensaje genérico sin perder log en debug. |
| **Criterio de verificación** | (1) Simular 401 → mensaje de sesión expirada, no stack trace. (2) Modo avión → mensaje de conectividad. (3) Tests unitarios del mapper. |

---

### MEJ-019 — Batch sync offline (múltiples sesiones por request)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-11 |
| **Descripción del cambio** | Añadir `POST /api/sesiones/batch` que acepte lista de sesiones en una transacción DB. Actualizar `ApiSyncRepository.syncActividades` para enviar lote (fallback a envío individual si batch falla). Mantener `POST /api/sesiones` unitario. |
| **Archivo(s) afectado(s)** | `dashboard_controller.py`; `api_sync_repository.dart`; `sync_offline_usecase.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2–3 días) |
| **Anti-regresión** | Endpoint unitario sigue operativo; cliente intenta batch primero, degrada a individual. |
| **Criterio de verificación** | (1) 10 actividades pendientes sync en 1 request. (2) Atomicidad: fallo en item 5 rollback completo. (3) Offline → online sync igual que antes. |

---

### MEJ-020 — Extraer lógica de dashboard_controller (incremental)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-08, P-12, S-09 |
| **Descripción del cambio** | Dividir monolito en controladores por bounded context: `notificaciones_controller.py`, `planes_controller.py`, `sesiones_controller.py`, `reportes_dashboard_controller.py`. Extraer funciones helper SQL a repositorios. **No cambiar paths HTTP** — re-exportar routers en `main.py`. Objetivo: archivos <300 líneas. |
| **Archivo(s) afectado(s)** | `dashboard_controller.py` → múltiples módulos en `backend/app/adapters/inbound/api/`; `main.py` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **XL** (3–4 semanas, incremental) |
| **Anti-regresión** | Un dominio por PR; tests de contrato HTTP por endpoint movido; grep confirma paths idénticos. |
| **Criterio de verificación** | (1) OpenAPI paths unchanged. (2) `test_difficulty_adjustment.py` y tests dashboard siguen pasando. (3) Ningún archivo nuevo >500 líneas al cierre de fase. |

---

### MEJ-021 — Renombrar mocks a InMemory*Repository

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-10 |
| **Descripción del cambio** | Tras MEJ-006, renombrar implementaciones in-memory usadas solo en tests a `InMemoryPatientRepository`, etc. Reservar prefijo `Postgres*` para adaptadores reales. Actualizar `dependencies.py` para inyectar Postgres en prod y InMemory en tests. |
| **Archivo(s) afectado(s)** | Repositorios en `backend/app/adapters/outbound/database/`; `dependencies.py`; tests |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (4–6 h) — post MEJ-006 |
| **Anti-regresión** | DI explícita por entorno; prod nunca recibe InMemory. |
| **Criterio de verificación** | (1) Grep `Postgres*` → solo clases con SQL real. (2) Tests usan InMemory sin PostgreSQL. |

---

### MEJ-022 — Unificar convención `usecases/` en Flutter

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-12 |
| **Descripción del cambio** | Migrar contenido de `application/use_cases/` a `application/usecases/` (p. ej. `iniciar_sesion_use_case.dart` → `login_usecase.dart` o alias export). Actualizar imports en providers y pantallas. Eliminar carpeta duplicada. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/application/use_cases/*`; `rimai_app/lib/application/usecases/*`; `auth_providers.dart` y consumidores |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (4–8 h) |
| **Anti-regresión** | Refactor puro de paths; sin cambio de lógica. `flutter analyze` limpio. |
| **Criterio de verificación** | (1) Una sola carpeta `usecases/`. (2) App compila y login funciona. |

---

### MEJ-023 — Fortalecer tests Flutter con assertions

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-13, S-14 |
| **Descripción del cambio** | Reescribir `auth_shell_test.dart` y `local_render_test.dart` con `expect` explícitos. Añadir tests de `ErrorMessageMapper`, `SyncOfflineUsecase` (mock ports), y widget test de login con validación de campos. |
| **Archivo(s) afectado(s)** | `rimai_app/test/auth_shell_test.dart`; `local_render_test.dart`; nuevos archivos en `rimai_app/test/` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2–3 días) |
| **Anti-regresión** | Tests no dependen de red ni backend real. |
| **Criterio de verificación** | (1) `flutter test` ≥8 tests con assertions. (2) CI MEJ-012 los ejecuta. (3) Ningún test traga excepciones sin fallar. |

---

### MEJ-024 — Validación de email RFC en login

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-09 |
| **Descripción del cambio** | Sustituir check `contains('@')` por regex RFC 5322 simplificada o paquete `email_validator` si ya está en dependencias transitivas; mensaje de error unchanged en tono. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart`; opcional `register_screen.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (2–4 h) |
| **Anti-regresión** | Emails válidos actuales en entorno de prueba siguen pasando. |
| **Criterio de verificación** | (1) `a@b.co` válido; `a@` inválido; `@b.com` inválido. (2) Widget test de validación. |

---

### MEJ-025 — Completar o redirigir rutas placeholder

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-11 |
| **Descripción del cambio** | **Opción conservadora:** ocultar enlaces de navegación hacia `/terapeuta/calendario` y `/home` hasta implementación. Mantener `_PlaceholderScreen` para deep links pero añadir redirect a dashboard en bottom nav. Documento clínico: mejorar mensaje y botón volver. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/core/router/app_router.dart`; pantallas que enlazan a calendario (grep `calendario`) |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (4–6 h) |
| **Anti-regresión** | Rutas existentes no se eliminan; solo se quita acceso desde UI principal. |
| **Criterio de verificación** | (1) Usuario no llega a placeholder desde flujo normal. (2) Deep link `/terapeuta/calendario` sigue mostrando pantalla informativa. |

---

### MEJ-026 — Alinear GenerarPlanSugeridoUseCase con flujo real o deprecar ruta

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-15 |
| **Descripción del cambio** | **Opción A:** `POST /api/v1/planes/personalizar` delega internamente al SQL de `POST /api/dashboard/paciente/{nino_id}/plan/generar`. **Opción B:** marcar ruta `/api/v1/planes/*` deprecated si Flutter no la usa (verificar grep). No mantener dos fuentes de verdad. |
| **Archivo(s) afectado(s)** | `plan_controller.py`; `generar_plan_sugerido_usecase.py`; `dashboard_controller.py` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2 días) |
| **Anti-regresión** | Flujo terapeuta plan builder en Flutter (vía dashboard API) unchanged. |
| **Criterio de verificación** | (1) Grep confirma qué rutas usa el cliente. (2) Generar plan produce filas en `planes_terapeuticos` en BD. |

---

### MEJ-027 — Logging en carga de modelos IA

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | R-16 |
| **Descripción del cambio** | Reemplazar `except Exception: pass` en `AISupportUseCases._load_model` por `logger.warning/error` con tipo de excepción. Mismo patrón en `motor.py` si aplica. |
| **Archivo(s) afectado(s)** | `backend/app/application/usecases/ai_support_usecases.py`; `backend/app/ai/motor.py` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (1–2 h) |
| **Anti-regresión** | Fallback heurístico sigue activo si falta `.pkl`; respuestas API unchanged. |
| **Criterio de verificación** | (1) Sin modelo, log warning y respuesta heurística. (2) Con modelo, log info de carga exitosa. |

---

### MEJ-028 — Mejorar errorBuilder del router

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-13 |
| **Descripción del cambio** | Reemplazar `Text('Ruta no encontrada...')` por Scaffold con mensaje amigable, botón “Ir al inicio” que lee rol de `AuthStorageService` y navega al dashboard correspondiente. |
| **Archivo(s) afectado(s)** | `rimai_app/lib/core/router/app_router.dart` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (3–4 h) |
| **Anti-regresión** | Rutas válidas no afectadas; solo dispara en 404 de routing. |
| **Criterio de verificación** | (1) Navegar a `/ruta/inexistente` muestra recovery UI. (2) Botón lleva al dashboard correcto por rol. |

---

### MEJ-029 — Accesibilidad: Semantics en formularios y acciones

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | U-12 |
| **Descripción del cambio** | Añadir `Semantics` a `RimAITextField`, botones de login, tarjetas `BentoCard` con label derivado del título. Verificar con TalkBack/VoiceOver en smoke manual. |
| **Archivo(s) afectado(s)** | `rimai_text_field.dart`; `login_screen.dart`; `bento_card.dart`; pantallas clínicas prioritarias |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **M** (2 días) |
| **Anti-regresión** | Cambios solo en árbol de semántica; layout visual idéntico. |
| **Criterio de verificación** | (1) Lector de pantalla anuncia labels de campos login. (2) `flutter test` pasa. |

---

### MEJ-030 — Completar README y documentación de arquitectura

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-16 |
| **Descripción del cambio** | Completar sección “Estructura del proyecto” en `README.md`: diagrama capas hexagonal, tabla de roles, mapa endpoints (dashboard vs v1), variables de entorno obligatorias. Reemplazar boilerplate de `rimai_app/README.md` con enlace al README raíz. |
| **Archivo(s) afectado(s)** | `README.md`; `rimai_app/README.md`; opcional `docs/03_arquitectura.md` |
| **Prioridad** | **Media** |
| **Esfuerzo estimado** | **S** (1 día) |
| **Anti-regresión** | Solo documentación; sin cambios de código. |
| **Criterio de verificación** | (1) README describe estructura real verificada en repo. (2) Lista MEJ-002/003 vars de entorno. |

---

## Fase 3 — Prioridad Baja

---

### MEJ-031 — Eliminar pantalla login legacy

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-14 |
| **Descripción del cambio** | Eliminar `rimai_app/lib/adapters/input/screens/login_screen.dart` (stub no referenciado). Confirmar con grep que ningún import apunta al archivo. |
| **Archivo(s) afectado(s)** | `screens/login_screen.dart` (eliminar) |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **S** (<1 h) |
| **Anti-regresión** | Router usa `auth/login_screen.dart`; verificar grep antes de borrar. |
| **Criterio de verificación** | (1) `flutter analyze` sin imports rotos. (2) Login funciona. |

---

### MEJ-032 — Resolver dependencias Firebase no usadas

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-13 |
| **Descripción del cambio** | **Opción A:** eliminar `firebase_core` y `firebase_messaging` de `pubspec.yaml`. **Opción B:** implementar FCM mínimo (registro token, handler foreground). Elegir una; no dejar dependencias huérfanas. |
| **Archivo(s) afectado(s)** | `rimai_app/pubspec.yaml`; opcional nuevos archivos FCM |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **S** (eliminar) / **L** (implementar FCM) |
| **Anti-regresión** | Eliminar solo si confirmado cero referencias; rebuild APK verifica tamaño. |
| **Criterio de verificación** | (1) `flutter pub get` sin warnings críticos. (2) Build APK exitoso. (3) Si FCM: token registrado en log. |

---

### MEJ-033 — Limpiar dependencias Python no usadas

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-10 |
| **Descripción del cambio** | Evaluar eliminación de `sqlalchemy` y `asyncpg` de `requirements.txt` si MEJ-010 usa solo psycopg2 pool; o planificar adopción real documentada. No mantener dependencias fantasma. |
| **Archivo(s) afectado(s)** | `backend/requirements.txt` |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **S** (1–2 h) |
| **Anti-regresión** | `pip install -r requirements.txt` y arranque API OK. |
| **Criterio de verificación** | (1) API arranca en Docker. (2) Tests pasan. |

---

### MEJ-034 — Estandarizar prefijos API bajo `/api/v1`

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-17 |
| **Descripción del cambio** | Plan de migración documentada: añadir aliases `/api/v1/dashboard/*` → handlers actuales; deprecar paths legacy con header `Sunset`. **No eliminar paths viejos** hasta migración completa del cliente Flutter (`dashboard_providers.dart`, repos). |
| **Archivo(s) afectado(s)** | `main.py`; controladores; `rimai_app/lib/core/constants/` y providers |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **L** (1–2 semanas) |
| **Anti-regresión** | Dual-route period: ambos paths responden idéntico durante 2 releases. |
| **Criterio de verificación** | (1) Matriz de equivalencia path legacy ↔ v1. (2) Cliente migrado usa solo v1. (3) Tests contrato dual-route. |

---

### MEJ-035 — Publicar contrato OpenAPI versionado

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-17 (complemento) |
| **Descripción del cambio** | Exportar `openapi.json` en CI; almacenar en `docs/openapi/` con versionado semver; diff en PR si cambian schemas de endpoints consumidos por Flutter. |
| **Archivo(s) afectado(s)** | `.github/workflows/`; `docs/openapi/` |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **S** (1 día) |
| **Anti-regresión** | Generación automática desde FastAPI; no editar JSON a mano. |
| **Criterio de verificación** | (1) Artefacto OpenAPI en CI. (2) Swagger `/docs` accesible. |

---

### MEJ-036 — Registrar deuda técnica explícita en mocks temporales

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | S-18 |
| **Descripción del cambio** | Reemplazar comentarios “PMV2/PMV3 mock” por referencia a ticket/issue (p. ej. `TODO(RIM-xxx)` vinculado a MEJ-006). Aplica mientras convivan mocks. |
| **Archivo(s) afectado(s)** | `postgres_scq_repository.py`; `postgres_seguimiento_repository.py`; `generar_plan_sugerido_usecase.py` |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **S** (<1 h) |
| **Anti-regresión** | Solo comentarios. |
| **Criterio de verificación** | (1) Cada mock referencia MEJ-006 o issue tracker. |

---

### MEJ-037 — Implementar recuperación de contraseña (cuando exista backend)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-12, U-10 |
| **Descripción del cambio** | Backend: endpoints `POST /api/v1/auth/forgot-password` y `reset-password` con token temporal. Frontend: flujo UI sustituye SnackBar. **Ejecutar solo tras MEJ-016** (reactivar control). |
| **Archivo(s) afectado(s)** | Nuevo auth endpoints; pantallas Flutter auth |
| **Prioridad** | **Baja** (feature nueva) |
| **Esfuerzo estimado** | **L** (1 semana) |
| **Anti-regresión** | Login/registro existentes untouched; feature opt-in. |
| **Criterio de verificación** | (1) E2E reset password en staging. (2) Token expira. (3) Login previo funciona. |

---

### MEJ-038 — Implementar login social o mantener oculto

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-12 |
| **Descripción del cambio** | Integrar OAuth Google/Apple con Firebase Auth o proveedor elegido; vincular a `usuarios`. Alternativa: decisión explícita de no implementar documentada en README (mantener MEJ-016). |
| **Archivo(s) afectado(s)** | Auth backend/frontend; `pubspec.yaml` si Firebase |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **XL** (2+ semanas) |
| **Anti-regresión** | Login email/password permanece como método principal. |
| **Criterio de verificación** | (1) OAuth login crea/recupera usuario. (2) JWT emitido igual que login clásico. |

---

### MEJ-039 — Implementar pantalla calendario terapeuta

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-11 |
| **Descripción del cambio** | Sustituir `_PlaceholderScreen` en `/terapeuta/calendario` por vista de sesiones programadas/completadas consumiendo API existente de sesiones. Requiere endpoint o reutilizar `/api/ninos/{id}/sesiones-revision`. |
| **Archivo(s) afectado(s)** | `app_router.dart`; nueva pantalla; posible extensión dashboard API |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **L** (1 semana) |
| **Anti-regresión** | Placeholder reemplazado solo cuando API estable; hasta entonces MEJ-025 oculta acceso. |
| **Criterio de verificación** | (1) Calendario muestra sesiones reales. (2) Resto de nav terapeuta intacto. |

---

### MEJ-040 — Implementar FCM push notifications

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | F-13 (opción B de MEJ-032) |
| **Descripción del cambio** | Integrar Firebase Messaging alineado con tabla `notificaciones` del backend; registrar device token; handler para notificaciones clínicas. |
| **Archivo(s) afectado(s)** | `main.dart`; `pubspec.yaml`; backend endpoint registro token |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **L** (1–2 semanas) |
| **Anti-regresión** | Notificaciones in-app existentes siguen funcionando sin FCM. |
| **Criterio de verificación** | (1) Push recibido en dispositivo físico. (2) App sin FCM configurado no crashea. |

---

### MEJ-041 — Adoptar SQLAlchemy de forma incremental (opcional)

| Campo | Detalle |
|-------|---------|
| **Hallazgo origen** | P-10 |
| **Descripción del cambio** | Si se decide no eliminar SQLAlchemy (MEJ-033), migrar repos nuevos (MEJ-006) a SQLAlchemy ORM usando `sqlalchemy_models.py` existente. Alternativa: eliminar dependencias (MEJ-033). |
| **Archivo(s) afectado(s)** | `sqlalchemy_models.py`; repos PostgreSQL |
| **Prioridad** | **Baja** |
| **Esfuerzo estimado** | **XL** (decisión arquitectónica) |
| **Anti-regresión** | Coexistencia psycopg2 raw en dashboard hasta migración completa. |
| **Criterio de verificación** | (1) Paridad de datos ORM vs raw en tests integración. |

---

## Cronograma sugerido (sin paralelismo de equipo)

```
Semana 1–2:  MEJ-001, 002, 003, 004, 008, 011, 012, 016
Semana 3–4:  MEJ-005, 007, 009, 010, 006a, 006b
Semana 5–8:  MEJ-006c–f, 013, 014, 017, 018, 020 (inicio)
Semana 9–12: MEJ-020 (cont.), 019, 021–030
Backlog:     MEJ-031–041
```

---

## Checklist de regresión por release

Ejecutar antes de cada release a staging/producción:

- [ ] `pytest backend/tests -v` — verde
- [ ] `flutter test` — verde
- [ ] Login terapeuta → dashboard carga pacientes
- [ ] Login familia → dashboard → plan publicado visible
- [ ] Login admin → estadísticas
- [ ] SCQ 40 preguntas → puntaje coherente con tests
- [ ] Sesión offline → reconexión → sync → dato en PostgreSQL
- [ ] Token expirado → redirect login (Flutter)
- [ ] Variables `JWT_SECRET`, `DATABASE_URL`, `CORS_ORIGINS` configuradas (sin defaults en código)

---

## Trazabilidad auditoría → plan

| ID auditoría | ID mejora |
|--------------|-----------|
| F-07, R-15, S-10 | MEJ-006, MEJ-021 |
| F-08, S-11 | MEJ-007 |
| F-09 | MEJ-001 |
| F-10 | MEJ-005 |
| F-11 | MEJ-025, MEJ-039 |
| F-12 | MEJ-016, MEJ-037, MEJ-038 |
| F-13 | MEJ-032, MEJ-040 |
| F-14 | MEJ-031 |
| F-15 | MEJ-026 |
| U-07, U-08 | MEJ-017 |
| U-09 | MEJ-024 |
| U-10 | MEJ-016 |
| U-11 | MEJ-018 |
| U-12 | MEJ-029 |
| U-13 | MEJ-028 |
| R-08 | MEJ-002 |
| R-09 | MEJ-004 |
| R-10 | MEJ-003 |
| R-11 | MEJ-008, MEJ-015 |
| R-12, R-13 | MEJ-011 |
| R-14 | MEJ-014 |
| R-16 | MEJ-027 |
| P-05 | MEJ-009 |
| P-06, P-07, P-08 | MEJ-013 |
| P-09 | MEJ-010 |
| P-10 | MEJ-033, MEJ-041 |
| P-11 | MEJ-019 |
| P-12, S-08, S-09 | MEJ-020 |
| S-12 | MEJ-022 |
| S-13, S-14 | MEJ-023 |
| S-15 | MEJ-012 |
| S-16 | MEJ-030 |
| S-17 | MEJ-034, MEJ-035 |
| S-18 | MEJ-036 |

---

*Plan derivado exclusivamente de `docs/01_auditoria_furps.md`. Esfuerzos estimados para un desarrollador familiarizado con el codebase; ajustar según capacidad del equipo.*
