# Auditoría de Implementación FURPS+ — RimAI

**Fecha:** 11 de junio de 2026  
**Referencia del plan:** [`docs/02_plan_furps.md`](02_plan_furps.md)  
**Metodología:** Contraste estático del código actual contra los 41 ítems planificados (MEJ-001 a MEJ-041). Verificación complementaria: `pytest backend/tests` (28 passed) y `flutter test` (3 passed) según ejecución del 11/06/2026.

---

## Resumen ejecutivo

| Fase | Total ítems | Sí | Parcial | No |
|------|-------------|-----|---------|-----|
| **Alta** | 12 | 4 | 8 | 0 |
| **Media** | 18 | 0 | 0 | 18 |
| **Baja** | 11 | 0 | 0 | 11 |
| **Total** | **41** | **4** | **8** | **29** |

**Cobertura del plan:** ~29 % implementado de forma completa o parcial (12/41 ítems con avance). **Fase Alta:** 100 % abordada, pero solo 4 ítems cumplen todos los criterios de verificación del plan; 8 quedan parciales. **Fases Media y Baja:** sin implementación detectada.

---

## Fase 1 — Prioridad Alta

### MEJ-001 — Corregir URL de reportes en cliente Flutter

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `rimai_app/lib/adapters/output/api_sync_repository.dart` L62: `$baseUrl/api/v1/reportes/$patientId`. Alias legacy en `backend/app/adapters/inbound/api/seguimiento_controller.py` L66–79: `GET /api/v1/seguimiento/reportes/{patient_id}` delega a `_get_reporte_impl`. |
| **Pendiente** | No hay test de integración/widget que valide la URL contra backend real. El plan pedía test mockeando JSON válido — no implementado. |

---

### MEJ-002 — Eliminar secretos JWT hardcodeados

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `backend/app/infrastructure/config.py` L31–32: `get_jwt_secret()` centralizado. Consumido en `auth_usecases.py` L32 y `dependencies.py` L33. `.env.example` documenta `JWT_SECRET`. |
| **Pendiente** | (1) El plan exige fallo **al arrancar** sin `JWT_SECRET`; hoy falla en `_require()` solo cuando se usa JWT (login/decode), no en `startup`. (2) Persisten defaults en `config.py` L9 (`_DEFAULT_JWT_SECRET`) activables con `RIMAI_ALLOW_TEST_DEFAULTS`. (3) `docker-compose.yml` L31 mantiene `${JWT_SECRET:-rimai-super-secret-key-2026}`. (4) `README.md` no documenta la variable como obligatoria. |

---

### MEJ-003 — Eliminar credenciales DB por defecto en código

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | Eliminadas de controladores: `dashboard_controller.py` L38–45 usa `get_connection()`; `admin_controller.py` L10–17; `scq_controller.py` sin `DATABASE_URL` local. `postgres_user_repository.py` usa pool centralizado. |
| **Pendiente** | (1) `config.py` L10 aún contiene `_DEFAULT_DATABASE_URL` con credenciales embebidas (solo tests). (2) `backend/tests/conftest.py` L6 repite URL con credenciales. (3) Criterio del plan «grep no encuentra credenciales embebidas» **no se cumple** en repo completo. (4) Fallo al arrancar sin `DATABASE_URL` ocurre en `init_db_pool()` (`main.py` L46), no de forma explícita documentada. |

---

### MEJ-004 — Restringir CORS a orígenes conocidos

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `main.py` L30–35: `allow_origins=get_cors_origins()`. `config.py` L43–50 lista Railway + localhost. `.env.example` y `docker-compose.yml` definen `CORS_ORIGINS`. |
| **Pendiente** | Si `CORS_ORIGINS` está vacío en producción, `get_cors_origins()` usa igualmente `_DEFAULT_CORS_ORIGINS` (L48–49), no falla ni alerta — comportamiento permisivo por omisión. No hay test automatizado de rechazo CORS. |

---

### MEJ-005 — Unificar vía de sincronización offline

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | Flutter sigue en `POST /api/sesiones` (`api_sync_repository.dart` L43–46). `seguimiento_controller.py` L34–55: headers `Deprecation`, mensaje y endpoint canónico documentado. Sync v1 usa `SincronizarDatosUseCase` con repos PostgreSQL (MEJ-006b). |
| **Pendiente** | (1) **No delega** a la lógica/SQL de `crear_sesion` en `dashboard_controller.py` — el plan recomendaba unificar flujo. (2) Payload `ActividadEjecutada` ≠ `CrearSesionRequest`; semántica distinta (p. ej. `PostgresSeguimientoRepository` inserta 1 acierto/repetición fijos). (3) Sin prueba E2E offline → PostgreSQL. |

---

### MEJ-006 — Repositorios PostgreSQL reales (6 adaptadores)

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | Los 6 archivos usan `get_connection()` y SQL sobre tablas existentes: `postgres_scq_repository.py`, `postgres_seguimiento_repository.py`, `postgres_reportes_repository.py`, `postgres_patient_repository.py`, `postgres_plan_repository.py`, `postgres_auditoria_repository.py`. Sin migraciones nuevas. |
| **Pendiente** | (1) **Sin tests de integración** con PostgreSQL (testcontainers/docker); solo mocks en `backend/tests/`. (2) MEJ-021 no aplicado: no existen clases `InMemory*Repository`. (3) `PostgresPatientRepository` / `PostgresPlanRepository` persisten en JSONB/`criterios_progresion` — funcional pero no equivalente al flujo productivo del dashboard. (4) Desalineación UUID (BD) vs `int` en rutas `/api/v1/reportes/{patient_id}` puede limitar reportes reales. (5) `dashboard_controller.py` (~3 843 líneas) sigue siendo la vía productiva principal, no los repos hexagonales. |

| Sub-ID | Estado | Nota |
|--------|--------|------|
| 006a SCQ | Parcial | Persistencia en `perfil_sensorial`; sin test integración |
| 006b Seguimiento | Parcial | SQL propio; no paridad con `crear_sesion` |
| 006c Reportes | Parcial | Alertas en `alertas_clinicas`; `get_reporte_by_patient` retorna `None` |
| 006d Patient | Parcial | Perfiles en JSONB anidado |
| 006e Plan | Parcial | Sugerencias en `criterios_progresion` |
| 006f Auditoria | Parcial | Insert en `logs_auditoria`; sin test integración |

---

### MEJ-007 — Refactorizar SCQ (caso de uso, sin duplicación)

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `scq_controller.py` invoca `EvaluarCuestionarioSCQUseCase` vía DI (L60–71). Grep confirma **ausencia** de `_score_scq` en controlador. `backend/tests/test_scq_scoring.py`: 7 tests SCQ passed. Puerto `ISCQRepository` extendido con `verify_tutor_owns_patient` y `authorize_send_to_therapist`. |
| **Pendiente** | Puerto ampliado (no previsto explícitamente en plan original de «sin cambiar interfaces»). Validación manual desde app familia no automatizada. |

---

### MEJ-008 — Manejador global de excepciones FastAPI

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `exception_handlers.py`: handlers para `HTTPException`, `RequestValidationError`, `psycopg2.Error`, `Exception`. Registrados en `main.py` L38–41. Formato `{detail, code}`. Logs en errores DB/internos (L37–38, L48). |
| **Pendiente** | `dashboard_controller.py` no envuelve operaciones DB localmente (complemento planificado en MEJ-015); depende del handler global. Sin test automatizado que simule error psycopg2. |

---

### MEJ-009 — Alertas clínicas fuera del GET resumen

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `dashboard_controller.py` L1527–1528: `if evaluar_alertas_en_resumen(): _evaluar_alertas_clinicas(...)`. `config.py` L53–54: default `false`. `.env.example` documenta variable. `POST /api/dashboard/terapeuta/alertas/evaluar` intacto (L1728+). |
| **Pendiente** | Sin medición de performance (>30 % mejora) documentada. Sin cron/post-evento automático alternativo. |

---

### MEJ-010 — Pool de conexiones PostgreSQL

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `database.py`: `ThreadedConnectionPool`, `get_connection()` con commit/rollback. `init_db_pool()` / `close_db_pool()` en `main.py` L45–53. Usado en dashboard, admin, user repo y 6 repos PostgreSQL. |
| **Pendiente** | (1) `scq_controller.py` ya no abre conexiones directas (OK). (2) Sin logs de reutilización de pool ni prueba de carga (50 req/s). (3) Plan listaba `scq_controller.py` — no aplica tras MEJ-007. |

---

### MEJ-011 — Sanear exposición de excepciones (controladores hexagonales)

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `seguimiento_controller.py` L58–63 y `reportes_controller.py`: `logger.exception` + mensaje genérico 500, sin `str(e)` al cliente. `ValueError` → 400 explícito. |
| **Pendiente** | `admin_controller.py` L90–91 aún expone `str(e)` en algunos endpoints (`obtener_estadisticas`). Fuera del alcance literal del ítem pero hallazgo relacionado. |

---

### MEJ-012 — Tests en CI antes del build APK

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `.github/workflows/build-apk.yml`: jobs `backend-tests` (L19–39) y `flutter-tests` (L41–56); job `build` depende de ambos (L63–65). `backend/tests/conftest.py` configura entorno de test. |
| **Pendiente** | (1) CI backend **sin** contenedor PostgreSQL — tests unitarios con mocks, no integración. (2) Flutter: 3 tests, `auth_shell_test.dart` sin `expect` (solo `print`). (3) Plan pedía ≥ validación de PR roto — configuración presente, cobertura insuficiente. |

---

## Fase 2 — Prioridad Media (MEJ-013 a MEJ-030)

| ID | Mejora | Estado | Evidencia / Pendiente |
|----|--------|--------|------------------------|
| **MEJ-013** | Optimizar query resumen (N+1) | **No** | Bucle `_predecir_riesgo_abandono` persiste en `dashboard_controller.py` L1598–1614. |
| **MEJ-014** | Registrar fallos sync SQLite | **No** | `api_sync_repository.dart` L52: `catch (_) {}` sin actualizar `sync_attempts`/`last_error`. |
| **MEJ-015** | Try/except rollback dashboard | **No** | Endpoints mutantes sin try/except local; solo handler global MEJ-008. |
| **MEJ-016** | Ocultar UI no implementada | **No** | `login_screen.dart` L155–159, L269–272: SnackBar «próximamente» para recuperar contraseña y login social. |
| **MEJ-017** | Centralizar design tokens PMV2 | **No** | `_kPrimary` hardcodeado en ≥10 pantallas (p. ej. `dashboard_screen.dart` L13, `family_plan_screen.dart` L9). |
| **MEJ-018** | Mensajes de error amigables | **No** | No existe `error_message_mapper.dart`. `dashboard_screen.dart` L110: `err.toString()`. |
| **MEJ-019** | Batch sync offline | **No** | Sin `POST /api/sesiones/batch`. Sync secuencial en `api_sync_repository.dart` L41–56. |
| **MEJ-020** | Dividir dashboard_controller | **No** | Monolito ~3 843 líneas; sin controladores satélite. |
| **MEJ-021** | Renombrar InMemory*Repository | **No** | No hay clases `InMemory*`; tests usan mocks inline (`MockSCQRepo` en `test_scq_scoring.py`). |
| **MEJ-022** | Unificar `usecases/` Flutter | **No** | Coexisten `application/use_cases/` (2 archivos) y `application/usecases/`. |
| **MEJ-023** | Fortalecer tests Flutter | **No** | 3 tests; sin `expect` en `auth_shell_test.dart` / `local_render_test.dart`. |
| **MEJ-024** | Validación email RFC | **No** | `login_screen.dart` L37–39: solo `contains('@')`. |
| **MEJ-025** | Rutas placeholder | **No** | `_PlaceholderScreen` activo en `app_router.dart` L251–253, L382–436. |
| **MEJ-026** | Alinear plan v1 con dashboard | **No** | `generar_plan_sugerido_usecase.py` L12–13: heurística mock PMV2; sin delegación a dashboard. |
| **MEJ-027** | Logging modelos IA | **No** | `ai_support_usecases.py` L16–17: `except Exception: pass`. |
| **MEJ-028** | errorBuilder router | **No** | `app_router.dart` L386–388: solo `Text('Ruta no encontrada...')`. |
| **MEJ-029** | Accesibilidad Semantics | **No** | Solo `rimai_bottom_nav.dart` (auditoría original); sin ampliación a formularios. |
| **MEJ-030** | Completar README | **No** | `README.md` L41–42: sección «Estructura del proyecto» vacía. `rimai_app/README.md`: boilerplate Flutter. |

---

## Fase 3 — Prioridad Baja (MEJ-031 a MEJ-041)

| ID | Mejora | Estado | Evidencia / Pendiente |
|----|--------|--------|------------------------|
| **MEJ-031** | Eliminar login legacy | **No** | Existe `screens/login_screen.dart` (stub, no referenciado por router). |
| **MEJ-032** | Firebase no usadas | **No** | `pubspec.yaml` L31–32: `firebase_core`, `firebase_messaging`; cero imports Dart. |
| **MEJ-033** | Limpiar deps Python | **No** | `requirements.txt` L3–4: `sqlalchemy`, `asyncpg` sin uso en `backend/app/`. |
| **MEJ-034** | Estandarizar `/api/v1` | **No** | Conviven `/api/dashboard`, `/api/ninos`, `/api/sesiones`, `/api/v1/*`. |
| **MEJ-035** | OpenAPI versionado | **No** | Sin `docs/openapi/` ni export en CI. |
| **MEJ-036** | Deuda técnica en comentarios mock | **No** | Comentario «mock PMV2» persiste en `generar_plan_sugerido_usecase.py` L13. |
| **MEJ-037** | Recuperación contraseña | **No** | Sin endpoints auth forgot/reset. |
| **MEJ-038** | Login social | **No** | UI placeholder únicamente. |
| **MEJ-039** | Pantalla calendario | **No** | Ruta `/terapeuta/calendario` → `_PlaceholderScreen`. |
| **MEJ-040** | FCM push | **No** | Dependencias declaradas; sin implementación. |
| **MEJ-041** | SQLAlchemy incremental | **No** | Sin adopción ORM; psycopg2 raw + pool. |

---

## Hallazgos transversales pendientes

| # | Hallazgo | Severidad | Relación plan |
|---|----------|-----------|---------------|
| H-01 | `dashboard_controller.py` sigue concentrando lógica productiva (~3 843 líneas, 41 endpoints) | Alta | MEJ-020, auditoría S-08 |
| H-02 | Doble paradigma: tráfico Flutter → `/api/dashboard/*`; capa `/api/v1/*` parcialmente alineada | Media | MEJ-006, MEJ-026, MEJ-034 |
| H-03 | Tests de integración backend inexistentes; CI no levanta PostgreSQL | Media | MEJ-006, MEJ-012 |
| H-04 | Secretos/credenciales aún presentes como defaults en config, compose y conftest | Media | MEJ-002, MEJ-003 |
| H-05 | UX: login social, recuperar contraseña, placeholders visibles | Baja | MEJ-016, MEJ-025 |
| H-06 | `admin_controller.py` expone `str(e)` en errores 500 (L90+) | Baja | MEJ-011 (alcance extendido) |

---

## Matriz de cumplimiento global

```
Implementación del plan docs/02_plan_furps.md (41 ítems)

  Sí      ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  4  (10 %)
  Parcial ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  8  (20 %)
  No      █████████████████████████████░░░░░░░░░  29  (70 %)
```

| Dimensión FURPS | Antes (auditoría 01) | Tras implementación Alta | Comentario |
|-----------------|----------------------|---------------------------|------------|
| **Functionality** | Medio | **Medio+** | Repos PostgreSQL hexagonales, SCQ unificado, URL reportes corregida; divergencia sync y monolito dashboard persisten. |
| **Usability** | Medio | **Medio** | Sin cambios en fase Media (tokens, errores amigables, UI oculta). |
| **Reliability** | Medio | **Medio+** | Handlers globales, CORS configurable, pool DB; defaults secretos y sync silencioso Flutter pendientes. |
| **Performance** | Medio | **Medio+** | Alertas fuera de GET resumen; N+1 en resumen sin optimizar (MEJ-013). |
| **Supportability** | Medio | **Medio+** | CI con tests, infra `config/` + `database/`; monolito, README vacío, tests Flutter débiles. |

---

## Dictamen final

### Calificación global: **MEDIO** (tendencia positiva, implementación incompleta)

La ejecución de la **Fase Alta** del plan FURPS+ fue **real y verificable**: se introdujo infraestructura de configuración y pool, se corrigieron contratos críticos (reportes, SCQ), se reemplazaron mocks por adaptadores PostgreSQL en la capa hexagonal, y se reforzaron seguridad operacional (CORS, manejo de errores) y CI. Los tests existentes (**28 backend + 3 Flutter**) pasan, lo que indica **ausencia de regresiones detectables** en la suite actual — aunque esa suite es **estrecha** y no cubre integración ni E2E.

Sin embargo, **ningún ítem Alta cumple el 100 % de los criterios de verificación del plan** excepto MEJ-007, MEJ-008, MEJ-009 y MEJ-011 (4/12). Los restantes son **Parciales** por: defaults de secretos aún en código/compose, sync v1 no unificado con `crear_sesion`, repos sin tests de integración, CI sin PostgreSQL, y cobertura Flutter insuficiente.

**Las Fases Media (18 ítems) y Baja (11 ítems) no han comenzado.** Permanecen los riesgos estructurales identificados en [`docs/01_auditoria_furps.md`](01_auditoria_furps.md): monolito `dashboard_controller`, design tokens duplicados, UX «próximamente», dependencias huérfanas (Firebase, SQLAlchemy), y documentación incompleta.

### Recomendación priorizada (post-auditoría)

1. **Cerrar parcialidades Alta:** validación JWT/DB en startup, eliminar defaults de compose, test integración PostgreSQL mínimo para SCQ + sesiones.
2. **Iniciar Fase Media crítica:** MEJ-013 (N+1), MEJ-014 (sync errors), MEJ-016/018 (UX errores), MEJ-020 incremental (extraer sesiones/planes del monolito).
3. **Ampliar suite de tests** antes de declarar Fase Alta cerrada formalmente.

---

*Auditoría de implementación basada en el código del repositorio al 11/06/2026. Documento complementario: [`docs/03_mejoras_alta_prioridad.md`](03_mejoras_alta_prioridad.md) (registro de cambios aplicados).*
