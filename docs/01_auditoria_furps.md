# Auditoría de Calidad FURPS+ — RimAI

**Fecha:** 11 de junio de 2026  
**Alcance:** Código fuente del repositorio RimAI (backend FastAPI + frontend Flutter, arquitectura hexagonal declarada)  
**Metodología:** Revisión estática del código; no se ejecutaron pruebas de integración ni despliegue en este informe.

---

## Resumen ejecutivo

| Dimensión FURPS | Nivel actual | Síntesis |
|-----------------|--------------|----------|
| **Functionality** | **Medio** | Flujos clínicos principales implementados (auth, dashboards, SCQ, planes, sesiones, offline), pero la arquitectura hexagonal está incompleta y coexisten rutas productivas con repositorios simulados en memoria. |
| **Usability** | **Medio** | UI coherente en flujos centrales con tema PMV2, validación de formularios y navegación por rol; hay inconsistencias visuales, funcionalidades “próximamente” y accesibilidad limitada. |
| **Reliability** | **Medio** | Validación de roles y errores HTTP en el controlador principal; carece de manejadores globales, expone defaults inseguros y tiene rutas de sincronización duplicadas/inconsistentes. |
| **Performance** | **Medio** | Consultas SQL razonables en endpoints individuales, pero el dashboard ejecuta evaluaciones clínicas en cada carga, patrones N+1 y conexiones DB sin pool. |
| **Supportability** | **Medio** | Estructura hexagonal reconocible y tests unitarios backend en dominio crítico; un monolito de ~5 665 líneas, repositorios mock con nombre “Postgres”, tests Flutter débiles y CI sin backend. |

---

## 1. Functionality (Funcionalidad)

**Nivel actual: Medio**

### Hallazgos

#### Fortalezas

| # | Hallazgo | Referencia |
|---|----------|------------|
| F-01 | La API expone un conjunto amplio de capacidades clínicas: autenticación JWT, dashboards de terapeuta/familia/admin, admisión SCQ, planes terapéuticos, sesiones, alertas, reportes, sincronización offline e IA adaptativa. | `backend/app/main.py` L15–38; `backend/app/adapters/inbound/api/dashboard_controller.py` L1–21 |
| F-02 | El flujo de autenticación (login, registro familiar, `/me`) está implementado con casos de uso y repositorio PostgreSQL real. | `backend/app/application/usecases/auth_usecases.py` L36–67; `backend/app/adapters/outbound/database/postgres_user_repository.py` L21–78 |
| F-03 | El scoring SCQ (40 preguntas, gateway Q1, umbrales Bajo/Moderado/Alto) está implementado y cubierto por tests unitarios. | `backend/app/application/usecases/evaluar_cuestionario_scq_usecase.py` L9–64; `backend/tests/test_scq_scoring.py` L29–67 |
| F-04 | El frontend implementa rutas por rol (terapeuta, familia, admin) con flujos de admisión, plan, sesión, progreso, SCQ y chatbot familiar. | `rimai_app/lib/core/router/app_router.dart` L46–385 |
| F-05 | Modo offline-first: SQLite local, sincronización al reconectar y registro de sesiones pendientes. | `rimai_app/lib/main.dart` L18–37; `rimai_app/lib/adapters/output/sqlite_db_repository.dart` L52–107 |
| F-06 | Motor de IA con Random Forest y fallback heurístico para dificultad adaptativa. | `backend/app/ai/motor.py` L21–85 |

#### Debilidades

| # | Hallazgo | Referencia |
|---|----------|------------|
| F-07 | **Arquitectura hexagonal incompleta:** varios adaptadores llamados `Postgres*` son mocks en memoria, no persisten en PostgreSQL. | `postgres_patient_repository.py` L6–13; `postgres_plan_repository.py` L6–8; `postgres_scq_repository.py` L6–9; `postgres_seguimiento_repository.py` L6–8; `postgres_reportes_repository.py` L6–10; `postgres_auditoria_repository.py` L5–7 |
| F-08 | El caso de uso `EvaluarCuestionarioSCQUseCase` está registrado en DI (`get_scq_use_cases`) pero **no es consumido por ningún controlador**; `scq_controller.py` duplica la lógica de scoring y escribe directamente con psycopg2. | `backend/app/adapters/inbound/api/dependencies.py` L76–77; `backend/app/adapters/inbound/api/scq_controller.py` L29–66, L69–134 |
| F-09 | **Desalineación de endpoints de reportes:** el cliente Flutter llama `/api/v1/seguimiento/reportes/{patientId}`, pero el backend expone `/api/v1/reportes/{patient_id}`. No existe ruta `seguimiento/reportes` en el backend revisado. | `rimai_app/lib/adapters/output/api_sync_repository.dart` L62–66; `backend/app/adapters/inbound/api/reportes_controller.py` L7–9 |
| F-10 | **Doble vía de sincronización:** Flutter sincroniza vía `POST /api/sesiones` (dashboard_controller, PostgreSQL real), mientras `/api/v1/seguimiento/sincronizar` usa repositorio mock en memoria. | `rimai_app/lib/adapters/output/api_sync_repository.dart` L43–46; `backend/app/adapters/inbound/api/seguimiento_controller.py` L15–27; `backend/app/adapters/inbound/api/dashboard_controller.py` L3813–3817 |
| F-11 | Rutas placeholder sin implementación funcional: calendario terapeuta, `/home`, documento no disponible. | `rimai_app/lib/core/router/app_router.dart` L251–253, L271–272, L382–384, L392–436 |
| F-12 | Funcionalidades anunciadas en UI pero no implementadas: recuperación de contraseña, login social (Google/Apple). | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L155–159, L269–272 |
| F-13 | Dependencias Firebase (`firebase_core`, `firebase_messaging`) declaradas en `pubspec.yaml` pero **sin uso** en el código Dart revisado. | `rimai_app/pubspec.yaml` L31–32 |
| F-14 | Pantalla de login legacy sin lógica (`_login()` vacío), no referenciada por el router activo. | `rimai_app/lib/adapters/input/screens/login_screen.dart` L13–17 |
| F-15 | `GenerarPlanSugeridoUseCase` genera sugerencias heurísticas mock; el plan real se gestiona en `dashboard_controller` contra PostgreSQL. | `backend/app/application/usecases/generar_plan_sugerido_usecase.py` L12–13, L42–49; `backend/app/adapters/inbound/api/plan_controller.py` L22–27 |

### Recomendaciones priorizadas

| Prioridad | Recomendación |
|-----------|---------------|
| **P1** | Unificar la capa de persistencia: implementar repositorios PostgreSQL reales para pacientes, planes, SCQ, seguimiento y reportes, o eliminar rutas `/api/v1/*` que apuntan a mocks. |
| **P1** | Corregir la URL de reportes en `ApiSyncRepository` para apuntar a `/api/v1/reportes/{patient_id}` (o crear alias en backend). |
| **P1** | Refactorizar `scq_controller.py` para delegar en `EvaluarCuestionarioSCQUseCase` y un repositorio PostgreSQL, eliminando duplicación de scoring. |
| **P2** | Deprecar `/api/v1/seguimiento/sincronizar` o redirigirlo al mismo flujo que `POST /api/sesiones`. |
| **P2** | Completar o ocultar rutas placeholder (`/terapeuta/calendario`, login social, recuperar contraseña). |
| **P3** | Eliminar código muerto (`screens/login_screen.dart`) y dependencias Firebase no usadas, o implementar FCM. |

---

## 2. Usability (Usabilidad)

**Nivel actual: Medio**

### Hallazgos

#### Fortalezas

| # | Hallazgo | Referencia |
|---|----------|------------|
| U-01 | Tema Material 3 centralizado (`PMV2Theme`) con paleta clínica coherente. | `rimai_app/lib/core/theme/app_theme.dart` L29–54 |
| U-02 | Formulario de login con validación inline, estados de carga y banner de error reutilizable. | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L32–49, L101, L173–213; `rimai_app/lib/adapters/input/widgets/error_banner.dart` L4–48 |
| U-03 | Navegación basada en rol con redirección automática post-login y protección de rutas por prefijo (`/admin`, `/terapeuta`, `/familia`). | `rimai_app/lib/core/router/app_router.dart` L48–88, L72–78 |
| U-04 | Dashboard terapeuta con skeleton loading, pull-to-refresh y manejo de sesión expirada con redirección al login. | `rimai_app/lib/adapters/input/screens/dashboard/dashboard_screen.dart` L85–111, L103–108 |
| U-05 | Bottom navigation con etiquetas semánticas (`Semantics`) para lectores de pantalla. | `rimai_app/lib/adapters/input/widgets/rimai_bottom_nav.dart` L56–59 |
| U-06 | Interfaz en español en pantallas revisadas (login, dashboard, plan familiar, placeholders). | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L106–107; `rimai_app/lib/adapters/input/screens/familia/family_plan_screen.dart` L47, L63–71 |

#### Debilidades

| # | Hallazgo | Referencia |
|---|----------|------------|
| U-07 | **Inconsistencia de design tokens:** `DashboardScreen` define colores locales PMV1 (`_kPrimary`, `_kBg`…) mientras `main.dart` aplica `PMV2Theme`. | `rimai_app/lib/adapters/input/screens/dashboard/dashboard_screen.dart` L12–19; `rimai_app/lib/main.dart` L57 |
| U-08 | Mezcla de tipografías: `PMV2Theme` usa Inter; login y error banner usan Plus Jakarta Sans con colores hardcodeados distintos al theme. | `rimai_app/lib/core/theme/app_theme.dart` L49; `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L163–167, L198–199 |
| U-09 | Validación de email mínima (solo verifica presencia de `@`), no formato RFC. | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L37–39 |
| U-10 | Botones de login social y “¿Olvidaste tu contraseña?” visibles pero muestran SnackBar “próximamente”, generando expectativa no cumplida. | `rimai_app/lib/adapters/input/screens/auth/login_screen.dart` L155–159, L269–272 |
| U-11 | Errores de API mostrados como texto crudo (`err.toString()`) al usuario en dashboard y plan familiar. | `rimai_app/lib/adapters/input/screens/dashboard/dashboard_screen.dart` L110–111; `rimai_app/lib/adapters/input/screens/familia/family_plan_screen.dart` L44–48 |
| U-12 | Accesibilidad limitada: solo `rimai_bottom_nav.dart` usa `Semantics` explícitamente en todo el frontend revisado. | Búsqueda en `rimai_app/lib/**/*.dart` |
| U-13 | Pantalla de error de ruta genérica sin navegación de recuperación. | `rimai_app/lib/core/router/app_router.dart` L386–388 |

### Recomendaciones priorizadas

| Prioridad | Recomendación |
|-----------|---------------|
| **P1** | Centralizar tokens de color/tipografía: migrar constantes PMV1 locales a `PMV2Theme` / `PMV2Colors`. |
| **P1** | Ocultar o deshabilitar controles no implementados (social login, recuperar contraseña) hasta que exista backend. |
| **P2** | Crear capa de mensajes de error amigables (mapeo HTTP → texto clínico) en providers/repositorios. |
| **P2** | Ampliar validación de email y añadir `Semantics` en campos de formulario, botones de acción y tarjetas clínicas. |
| **P3** | Mejorar `errorBuilder` del router con botón “Volver al inicio” según rol. |

---

## 3. Reliability (Confiabilidad)

**Nivel actual: Medio**

### Hallazgos

#### Fortalezas

| # | Hallazgo | Referencia |
|---|----------|------------|
| R-01 | Autenticación JWT con verificación de rol en endpoints sensibles del dashboard (403/404 explícitos). | `backend/app/adapters/inbound/api/dependencies.py` L34–43; `dashboard_controller.py` L395–416, L3818–3827 |
| R-02 | Validación de entrada en creación de sesiones (repeticiones > 0, aciertos ≤ repeticiones, actividades del plan). | `backend/app/adapters/inbound/api/dashboard_controller.py` L3828–3877 |
| R-03 | Health check disponible. | `backend/app/main.py` L44–46 |
| R-04 | Cliente Flutter detecta sesión expirada (`SessionExpiredException`) y limpia almacenamiento seguro. | `rimai_app/lib/core/providers/dashboard_providers.dart` L10–16; `dashboard_screen.dart` L103–108 |
| R-05 | Sincronización offline reintenta: errores de red no eliminan registros locales. | `rimai_app/lib/adapters/output/api_sync_repository.dart` L52–54; `rimai_app/lib/application/usecases/sync_offline_usecase.dart` L10–18 |
| R-06 | Almacenamiento de tokens en `flutter_secure_storage`. | `rimai_app/lib/main.dart` L23; `rimai_app/lib/infrastructure/config/auth_storage_service.dart` (referenciado en router L44) |
| R-07 | Contraseñas hasheadas con bcrypt en registro/login. | `backend/app/application/usecases/auth_usecases.py` L9, L22–23, L59 |

#### Debilidades

| # | Hallazgo | Referencia |
|---|----------|------------|
| R-08 | **Secret JWT con fallback hardcodeado** si falta variable de entorno. | `backend/app/adapters/inbound/api/dependencies.py` L29; `backend/app/application/usecases/auth_usecases.py` L10 |
| R-09 | **CORS abierto** (`allow_origins=["*"]`) con credenciales habilitadas. | `backend/app/main.py` L22–28 |
| R-10 | **Credenciales DB por defecto** embebidas en código fuente. | `backend/app/adapters/inbound/api/dashboard_controller.py` L41–44; `postgres_user_repository.py` L13–16; `scq_controller.py` L13–16 |
| R-11 | **Sin manejador global de excepciones** FastAPI; errores psycopg2 no capturados en `dashboard_controller` propagan stack traces. | Búsqueda: no hay `exception_handler` en `backend/**/*.py`; `dashboard_controller.py` usa `with _conn()` sin try/except en endpoints como L1513 |
| R-12 | `seguimiento_controller` captura `Exception` genérica y expone `str(e)` al cliente (500). | `backend/app/adapters/inbound/api/seguimiento_controller.py` L23–27 |
| R-13 | `reportes_controller` mismo patrón de exposición de excepciones internas. | `backend/app/adapters/inbound/api/reportes_controller.py` L18–30 |
| R-14 | Errores de sincronización **silenciados** (`catch (_) {}`) sin registro ni incremento de `sync_attempts` en SQLite. | `rimai_app/lib/adapters/output/api_sync_repository.dart` L52–54; columna `sync_attempts` definida en `sqlite_db_repository.dart` L66–67 pero no actualizada en fallos |
| R-15 | Datos de `/api/v1/perfiles` y `/api/v1/planes` se pierden al reiniciar el servidor (repos in-memory). | Ver F-07 |
| R-16 | `AISupportUseCases._load_model` traga excepciones con `pass` sin logging. | `backend/app/application/usecases/ai_support_usecases.py` L16–17 |

### Recomendaciones priorizadas

| Prioridad | Recomendación |
|-----------|---------------|
| **P1** | Eliminar defaults de `JWT_SECRET` y `DATABASE_URL` en código; fallar al arrancar si faltan variables de entorno. |
| **P1** | Restringir CORS a orígenes conocidos (dominio Railway, localhost dev). |
| **P1** | Añadir `@app.exception_handler` para errores DB/validación con respuestas JSON uniformes sin filtrar internals. |
| **P2** | Registrar fallos de sync en SQLite (`last_error`, `sync_attempts`) y exponer estado en UI (`sync_status_widget.dart`). |
| **P2** | Envolver operaciones DB del dashboard en try/except con rollback y códigos HTTP consistentes. |
| **P3** | Añadir logging estructurado en carga de modelos IA y operaciones críticas. |

---

## 4. Performance (Rendimiento)

**Nivel actual: Medio**

### Hallazgos

#### Fortalezas

| # | Hallazgo | Referencia |
|---|----------|------------|
| P-01 | Motor IA declara objetivo de inferencia rápida con fallback heurístico O(1). | `backend/app/application/usecases/ai_support_usecases.py` L19–43; `backend/app/ai/motor.py` L74–80 |
| P-02 | Subida de archivos clínicos por chunks de 1 MB. | `backend/app/adapters/outbound/storage/cloud_storage_adapter.py` L30–35 |
| P-03 | Esquema SQL con tipos indexables (UUID, JSONB) y migraciones incrementales. | `backend/sql/01_init.sql` L1–64 |
| P-04 | Providers Riverpod con invalidación selectiva en pull-to-refresh. | `rimai_app/lib/adapters/input/screens/dashboard/dashboard_screen.dart` L87–90 |

#### Debilidades

| # | Hallazgo | Referencia |
|---|----------|------------|
| P-05 | **`GET /api/dashboard/resumen` ejecuta evaluación clínica completa** (`_evaluar_alertas_clinicas`) en cada carga del dashboard terapeuta. | `backend/app/adapters/inbound/api/dashboard_controller.py` L1508–1530 |
| P-06 | **Patrón N+1:** bucle sobre cada niño llamando `_predecir_riesgo_abandono` con consultas adicionales. | `backend/app/adapters/inbound/api/dashboard_controller.py` L1598–1614 |
| P-07 | `_evaluar_alertas_clinicas` itera niños con múltiples queries por iteración (sesiones, resultados, alertas). | `backend/app/adapters/inbound/api/dashboard_controller.py` L1055–1095 |
| P-08 | Subconsulta correlacionada para última sesión por niño en query de resumen. | `backend/app/adapters/inbound/api/dashboard_controller.py` L1558–1564 |
| P-09 | **Sin pool de conexiones:** cada operación abre `psycopg2.connect()` via `_conn()` (~43 usos en dashboard_controller). | `dashboard_controller.py` L47–48; conteo de `_conn()` |
| P-10 | SQLAlchemy y asyncpg en `requirements.txt` **no utilizados**; toda persistencia productiva es psycopg2 síncrono. | `backend/requirements.txt` L3–5; ausencia de imports SQLAlchemy en `backend/app/` |
| P-11 | Sincronización offline secuencial (una petición HTTP por actividad). | `rimai_app/lib/adapters/output/api_sync_repository.dart` L41–56 |
| P-12 | Monolito de ~5 665 líneas y 41 endpoints HTTP en un solo archivo dificulta profiling y optimización focalizada. | `backend/app/adapters/inbound/api/dashboard_controller.py` L5568–5665 (fin de archivo); 41 decoradores `@router` |

### Recomendaciones priorizadas

| Prioridad | Recomendación |
|-----------|---------------|
| **P1** | Separar evaluación de alertas: ejecutar en background/cron o endpoint dedicado (`/alertas/evaluar` ya existe en L1728) en lugar de en cada GET resumen. |
| **P1** | Introducir pool de conexiones (`psycopg2.pool` o SQLAlchemy engine) compartido por request. |
| **P2** | Reescribir query de resumen terapeuta con JOINs/agregaciones en una sola consulta; eliminar N+1 en bucle de niños. |
| **P2** | Batch sync: endpoint que acepte lista de sesiones en una transacción. |
| **P3** | Dividir `dashboard_controller.py` en módulos por bounded context (notificaciones, planes, sesiones, reportes). |

---

## 5. Supportability (Mantenibilidad)

**Nivel actual: Medio**

### Hallazgos

#### Fortalezas

| # | Hallazgo | Referencia |
|---|----------|------------|
| S-01 | Separación de capas reconocible: `domain/`, `application/`, `adapters/inbound|outbound/`. | Estructura `backend/app/` |
| S-02 | Frontend sigue adaptadores hexagonales: `adapters/input|output`, `application/usecases`, `domain/entities`. | Estructura `rimai_app/lib/` |
| S-03 | Tests unitarios backend para lógica crítica: SCQ (6 tests), adherencia (3), priorización IA (4), ajuste dificultad (3), reportes (1), inferencia TEA (10). | `backend/tests/` (6 archivos) |
| S-04 | Docstring de módulo en `dashboard_controller.py` documenta rutas expuestas. | `dashboard_controller.py` L1–21 |
| S-05 | Docker Compose con healthcheck PostgreSQL y servicio API. | `docker-compose.yml` L17–40 |
| S-06 | Gestión de estado con Riverpod; routing declarativo con GoRouter. | `rimai_app/lib/core/providers/`; `app_router.dart` |
| S-07 | CI/CD para build APK Flutter en push a `main`/`develop`. | `.github/workflows/build-apk.yml` L1–47 |

#### Debilidades

| # | Hallazgo | Referencia |
|---|----------|------------|
| S-08 | **God object:** `dashboard_controller.py` concentra lógica de negocio, SQL, PDF, alertas, IA y auditoría (~5 665 líneas). | `dashboard_controller.py` |
| S-09 | **Doble paradigma arquitectónico:** capa hexagonal (`/api/v1/*`) convive con controlador monolítico SQL (`/api/dashboard/*`, `/api/ninos/*`, `/api/sesiones`). | `main.py` L30–36 vs estructura hexagonal |
| S-10 | Nomenclatura engañosa: clases `Postgres*` que no usan PostgreSQL. | Ver F-07 |
| S-11 | Duplicación de lógica SCQ en use case y controller. | Ver F-08 |
| S-12 | Flutter: convenciones duplicadas `application/usecases/` y `application/use_cases/`. | `rimai_app/lib/application/usecases/`; `rimai_app/lib/application/use_cases/` |
| S-13 | Tests Flutter débiles: `auth_shell_test.dart` captura excepciones sin `expect`; `local_render_test.dart` igual. | `rimai_app/test/auth_shell_test.dart` L34–36; `local_render_test.dart` L26–28 |
| S-14 | Solo 3 archivos de test Dart; `widget_test.dart` verifica únicamente que la app arranca. | `rimai_app/test/` |
| S-15 | CI **no ejecuta** tests backend ni `flutter test`. | `.github/workflows/build-apk.yml` (solo `flutter build apk`) |
| S-16 | Documentación mínima: `README.md` con sección “Estructura del proyecto” vacía; `rimai_app/README.md` es plantilla Flutter por defecto. | `README.md` L41–42; `rimai_app/README.md` L1–17 |
| S-17 | Prefijos API inconsistentes: `/api/v1/auth`, `/api/dashboard`, `/api/admin`, `/api/ninos`, `/api/sesiones`, `/api/ia`. | `main.py` L30–38; `dashboard_controller.py` |
| S-18 | Comentarios en código indican mocks temporales (“PMV2”, “PMV3”) sin ticket de deuda técnica. | `postgres_scq_repository.py` L7; `postgres_seguimiento_repository.py` L7; `generar_plan_sugerido_usecase.py` L13 |

### Recomendaciones priorizadas

| Prioridad | Recomendación |
|-----------|---------------|
| **P1** | Extraer lógica de `dashboard_controller.py` a casos de uso + repositorios PostgreSQL; objetivo: archivos < 300 líneas por módulo. |
| **P1** | Añadir job CI `pytest backend/tests` y `flutter test` antes del build APK. |
| **P2** | Renombrar mocks a `InMemory*Repository` o completar implementación PostgreSQL. |
| **P2** | Unificar convención Dart (`usecases/` únicamente) y eliminar código muerto. |
| **P2** | Completar README con diagrama de arquitectura, mapa de endpoints y guía de roles. |
| **P3** | Estandarizar prefijo API (`/api/v1/...`) y publicar contrato OpenAPI versionado. |
| **P3** | Fortalecer tests Flutter con `expect` en flujos auth, SCQ y sync offline usando mocks de repositorio. |

---

## Matriz de riesgo transversal

| Riesgo | Dimensiones afectadas | Severidad |
|--------|----------------------|-----------|
| Repositorios mock en producción hexagonal | Functionality, Reliability | Alta |
| URL reportes incorrecta en cliente | Functionality | Alta |
| Secretos/credenciales por defecto en código | Reliability | Alta |
| Evaluación clínica en cada GET dashboard | Performance | Media |
| Monolito dashboard_controller | Performance, Supportability | Media |
| UI “próximamente” visible | Usability | Baja |
| Tests Flutter sin assertions | Supportability | Media |

---

## Conclusión

RimAI es un producto **funcionalmente ambicioso** con flujos clínicos reales implementados principalmente en `dashboard_controller.py` contra PostgreSQL, complementados por un frontend Flutter maduro en navegación y experiencia visual. Sin embargo, la **arquitectura hexagonal declarada no está completada**: gran parte de la capa `/api/v1/*` opera sobre mocks en memoria mientras el tráfico productivo del cliente Flutter usa rutas monolíticas.

Las acciones de mayor impacto son: **(1)** alinear persistencia y contratos API entre backend y Flutter, **(2)** refactorizar el controlador monolítico hacia casos de uso con repositorios reales, y **(3)** cerrar brechas de seguridad operacional (secretos, CORS, manejo global de errores). Con esas correcciones, el proyecto podría ascender a nivel **Alto** en Functionality y Reliability; en el estado actual del código fuente, el nivel global consolidado se sitúa en **Medio** en las cinco dimensiones evaluadas.

---

*Documento generado por auditoría estática FURPS+. Referencias de línea corresponden al estado del repositorio al 11/06/2026.*
