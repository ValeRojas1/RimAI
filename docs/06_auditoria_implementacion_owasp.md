# Auditoría de Implementación OWASP — RimAI

**Fecha:** 11 de junio de 2026  
**Referencia del plan:** [`docs/05_plan_owasp.md`](05_plan_owasp.md)  
**Referencia auditoría original:** [`docs/04_auditoria_owasp.md`](04_auditoria_owasp.md)  
**Registro de cambios:** [`docs/06_remediacion_owasp_critica_alta.md`](06_remediacion_owasp_critica_alta.md)  
**Metodología:** Contraste estático del código actual contra los 42 ítems REM del plan. Verificación complementaria: `pytest backend/tests` → **36/36 passed** (11/06/2026).

---

## Resumen ejecutivo

| Fase plan | Total | Sí | Parcial | No |
|-----------|-------|-----|---------|-----|
| **Crítica** | 5 | 3 | 2 | 0 |
| **Alta** | 10 | 4 | 6 | 0 |
| **Media** | 18 | 2 | 0 | 16 |
| **Baja** | 8 | 0 | 0 | 8 |
| **Preventiva** | 1 | 0 | 0 | 1 |
| **Total** | **42** | **9** | **8** | **25** |

**Cobertura del plan OWASP:** ~40 % cerrado (17/42 ítems con avance Sí o Parcial). **Fases Crítica y Alta:** 100 % abordadas; 7 ítems cumplen todos los criterios de verificación; 8 quedan parciales. **Fases Media, Baja y Preventiva:** sin avance sustancial (salvo REM-018 y REM-026 adelantados).

---

## Dictamen final

### Nivel de seguridad: **MEDIO-ALTO** (mejora desde **Alto** pre-remediación)

La remediación Crítica/Alta redujo de forma **verificable** la superficie de IDOR en reportes, descarga de documentos y perfil clínico; endureció secretos Docker, CORS, registro público y rate limiting en auth. El módulo `authorization.py` centraliza controles reutilizables.

**No está listo para certificación “producción clínica”** sin cerrar parcialidades (seeds dev, puertos DB en compose por defecto, tests E2E IDOR, fase Media pendiente: JWT 7 días, uploads, auditoría de lecturas, CVE scan).

**Condición de despliegue seguro:** usar `docker compose -f docker-compose.yml -f docker-compose.prod.yml up` con `.env` completo; no montar seeds; `ALLOW_PUBLIC_REGISTER=false`.

---

## Fase 0 — Crítica

### REM-001 — H-A01-01: IDOR reportes analíticos

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `reportes_controller.py` L28: `autorizar_acceso_nino(str(patient_id), current_user)` antes de `execute()`. Alias legacy en `seguimiento_controller.py` delega a `_get_reporte_impl` (misma ruta). Módulo `backend/app/infrastructure/authorization.py` L23–51. |
| **Riesgo residual** | Sin test de integración HTTP tutor A → paciente B. UUID vs `int` en ruta puede fallar en casos límite no cubiertos por tests. |

---

### REM-002 — H-A01-02: IDOR descarga documentos clínicos

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `dashboard_controller.py` L190–193: `resolve_nino_id_for_clinical_file()` + `autorizar_acceso_nino()`. `authorization.py` L95–124 busca en `documentos_clinicos` y `evaluaciones_externas`. `basename` en L189. |
| **Riesgo residual** | (1) Resolución por scan de **todos** los niños activos — costoso y frágil si hay muchos registros. (2) Archivos en disco **sin** metadatos en JSONB (subidas antiguas o fuera de flujo dashboard) → 404 aunque exista el fichero. (3) Sin prueba E2E descarga cruzada. |

---

### REM-003 — H-A01-03: PATCH perfil clínico sin autorización

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `dashboard_controller.py` L4496–4500: `autorizar_acceso_nino()` + `campos_perfil_editables_por_rol()`. Tutores: solo `perfil_sensorial` (`authorization.py` L19–20). |
| **Riesgo residual** | SQL dinámico con f-string persiste (REM-041 pendiente); whitelist mitiga inyección. |

---

### REM-004 — H-A02-01: JWT secret predecible en Docker

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `docker-compose.yml` L81: `JWT_SECRET: ${JWT_SECRET:?JWT_SECRET es obligatorio...}`. `.env.example` L9–10 documenta generación. Sin fallback `rimai-super-secret-key-2026`. |
| **Riesgo residual** | Railway/prod fuera de Docker debe definir `JWT_SECRET` manualmente; no hay validación de entropía mínima en código. |

---

### REM-005 — H-A02-03: Seeds demo con contraseñas conocidas

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `docker-compose.yml` ya **no** monta `02_seed.sql` / `05_seed_test.sql`. `docker-compose.dev.yml` los monta solo con perfil dev. `02_seed.sql` L196: notice sin password en claro. |
| **Riesgo residual** | (1) `05_seed_test.sql` L7–10 y L25 aún documentan `Rimai2024!` en comentarios. (2) Credenciales demo siguen en repo (hashes bcrypt). (3) README no centraliza credenciales demo como exige el plan. (4) `docker compose up` sin `-f docker-compose.dev.yml` sigue exponiendo puerto **5432** (ver REM-015). |

---

## Fase 1 — Alta

### REM-006 — H-A01-04: Historial y evaluaciones v1 sin ownership

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `patient_controller.py` L17, L29, L36: `autorizar_acceso_nino()` en perfil clínico, upload e historial. |
| **Riesgo residual** | `POST /api/v1/perfiles/` (`create_patient` L10–12) **no** restringe rol ni valida payload; asigna `tutor_id` del token pero cualquier usuario autenticado puede invocarlo. Sin tests HTTP de historial cruzado. |

---

### REM-007 — H-A01-05: Sync offline sin validar patient_id

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `sincronizar_datos_usecase.py` L15–23: `verify_tutor_owns_patient()` por actividad; rechaza lote con `ValueError`. Test unitario en `test_security_remediation.py` L59–77. |
| **Riesgo residual** | Flujo productivo Flutter usa `POST /api/sesiones` (`dashboard_controller.py` L3830–3846) que **sí** valida tutor-plan-niño; el endpoint deprecado `/api/v1/seguimiento/sincronizar` queda protegido. Criterio plan “alinear ambos flujos”: cumplido en espíritu, no unificados en un solo caso de uso. |

---

### REM-008 — H-A01-06: Plan personalizado sin rol ni asignación

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `plan_controller.py` L25–28: rol `terapeuta` + `verify_terapeuta_assigned_to_patient()`. |
| **Riesgo residual** | `validar_plan` no verifica asignación terapeuta–plan (solo rol). |

---

### REM-009 — H-A01-07: Rol arbitrario al crear usuarios (admin)

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `admin_controller.py` L35: `rol: RoleEnum`. L131–140: inserta `request.rol.value`. Test `test_role_enum_rechaza_valores_invalidos`. |
| **Riesgo residual** | Admin puede crear otro `RoleEnum.ADMIN` sin confirmación ni log de auditoría (opcional en plan no implementado). |

---

### REM-010 — H-A02-02: Credenciales embebidas en config.py

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `config.py` L22–36: `_require()` sin defaults en producción. Defaults solo si `_TEST_DEFAULTS_ALLOWED`. `conftest.py` centraliza env de test. |
| **Riesgo residual** | L27–31: strings `test-jwt-secret...` y URL con `rimai_secure_2026` **permanecen** en `backend/app/infrastructure/config.py` (activables con flag test). Criterio plan “grep en backend/app/ sin credenciales”: **no cumplido** estrictamente. |

---

### REM-011 — H-A04-02 / H-A07-01: Rate limiting login/registro

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `rate_limit.py`, `auth_controller.py` L19–20 (`5/minute`), L35–36 (`3/hour`), `main.py` SlowAPIMiddleware. Deshabilitado con `RIMAI_ALLOW_TEST_DEFAULTS` / `RATE_LIMIT_ENABLED=false` en conftest. |
| **Riesgo residual** | (1) Límites **no** configurables por env como sugiere el plan. (2) Sin test automatizado de respuesta **429**. (3) Rate limit en memoria (slowapi default) — no distribuido en multi-instancia. |

---

### REM-012 — H-A05-01: CORS sin fallback permisivo

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `config.py` L51–60: `RuntimeError` si `CORS_ORIGINS` vacío fuera de tests. `docker-compose.yml` L83: CORS obligatorio. |
| **Riesgo residual** | `main.py` L42–43: `allow_methods=["*"]`, `allow_headers=["*"]` (REM-022 pendiente). |

---

### REM-013 — H-A05-07: Fuga de excepciones en admin

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `admin_controller.py`: bloques `except Exception` usan `logger.exception` + mensaje genérico (L91, L123, L187, L228, L282). |
| **Riesgo residual** | `create_therapist` L58 expone `str(e)` en **400** por `ValueError` (aceptable para validación de negocio). |

---

### REM-014 — H-A04-01: Registro público sin verificación

| Campo | Valor |
|-------|-------|
| **Estado** | **Sí** |
| **Evidencia** | `config.py` L68–70: `allow_public_register()`. `auth_controller.py` L42–46: **403** si deshabilitado. `docker-compose.prod.yml` L22: `ALLOW_PUBLIC_REGISTER=false`. |
| **Riesgo residual** | Flujo de invitación por terapeuta (fase 2 del plan) no implementado. |

---

### REM-015 — H-A05-04: PostgreSQL y pgAdmin expuestos (Docker)

| Campo | Valor |
|-------|-------|
| **Estado** | **Parcial** |
| **Evidencia** | `docker-compose.prod.yml` L4: `ports: !reset []`. pgAdmin deshabilitado en prod (`profiles: ["disabled"]`). pgAdmin dev: `PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "True"`, imagen pinneada `8.14` (REM-026 adelantado). |
| **Riesgo residual** | `docker-compose.yml` **por defecto** sigue publicando **5432** (L19–21) y **5050** con `--profile dev`. Despliegue inseguro si se usa solo el compose base sin `-f docker-compose.prod.yml`. |

---

## Fase 2 — Media (REM-016 a REM-033)

| REM | Hallazgo | Estado | Evidencia / Residual |
|-----|----------|--------|----------------------|
| **REM-016** | JWT 7 días | **No** | `auth_usecases.py` L10: `ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7` sin cambio. |
| **REM-017** | Revocación server-side tokens | **No** | Sin `/logout`, blacklist ni `jti`. |
| **REM-018** | Algoritmo JWT sin whitelist | **Sí** | `config.py` L43–44: `return "HS256"` fijo. *Implementado adelantado.* |
| **REM-019** | Upload sin MIME/tamaño | **No** | `cloud_storage_adapter.py` sin whitelist ni límite. |
| **REM-020** | Política de contraseña | **No** | `RegisterRequest.password: str` sin validador. |
| **REM-021** | Endpoint IA sin rol | **No** | `ai_controller.py` L15: cualquier usuario autenticado. |
| **REM-022** | CORS métodos/headers | **No** | `main.py` L42–43: `["*"]`. |
| **REM-023** | Escaneo CVE en CI | **No** | Sin `pip-audit` ni Dependabot en repo. |
| **REM-024** | pytest en runtime deps | **No** | `requirements.txt` L17: `pytest==8.3.4`. |
| **REM-025** | Migrar python-jose | **No** | `auth_usecases.py` L3: `from jose import jwt`. |
| **REM-026** | pgAdmin `:latest` | **Sí** | `docker-compose.yml` L113: `dpage/pgadmin4:8.14`. *Adelantado en fase Alta.* |
| **REM-027** | Deps no usadas | **No** | `sqlalchemy`, `asyncpg` en `requirements.txt` L3–4. |
| **REM-028** | joblib.load sin hash | **No** | `ai_support_usecases.py` L15: `joblib.load` sin verificación. |
| **REM-029** | EmailStr en auth | **No** | `auth_controller.py` L11–12: `email: str`. |
| **REM-030** | Log login fallido | **No** | Sin logging de intentos fallidos. |
| **REM-031** | Auditoría parcial | **No** | Reportes no registran `REPORTE_LEIDO` / `ACCESO_DENEGADO`. |
| **REM-032** | Bind mount API en prod | **Parcial** | `docker-compose.prod.yml` L20: `volumes: !reset []`; compose base L95 aún monta `./backend:/app`. |
| **REM-033** | requirements lockfile | **No** | Sin `requirements.lock`. |

---

## Fase 3 — Baja (REM-034 a REM-041)

| REM | Hallazgo | Estado | Evidencia |
|-----|----------|--------|-----------|
| **REM-034** | OpenAPI expuesto | **No** | `main.py` L27–31: FastAPI defaults `/docs` activos. |
| **REM-035** | Security headers HTTP | **No** | Sin middleware HSTS/X-Frame-Options. |
| **REM-036** | APM/SIEM | **No** | Sin Sentry/Prometheus integrado. |
| **REM-037** | Validación expone errors | **No** | `exception_handlers.py` L33: `exc.errors()` completo. |
| **REM-038** | Token válido offline Flutter | **No** | `auth_storage_service.dart` L114–115: asume válido sin red. |
| **REM-039** | Certificate pinning | **No** | Sin `SecurityContext` en Dart. |
| **REM-040** | CI APK firma documentada | **No** | `build-apk.yml` sin doc keystore. |
| **REM-041** | SQL dinámico f-string | **No** | `dashboard_controller.py` L4548–4550: `f"UPDATE ninos SET..."`. |

---

## Fase 4 — Preventiva

### REM-042 — H-A10: Guía SSRF

| Campo | Valor |
|-------|-------|
| **Estado** | **No** |
| **Evidencia** | No existe `docs/security/ssrf-guidelines.md`. Backend sigue sin clientes HTTP salientes (sin superficie SSRF actual). |

---

## Hallazgos transversales post-remediación

| # | Hallazgo | Severidad | Relación REM |
|---|----------|-----------|--------------|
| T-01 | `dashboard_controller.py` (~5 600 líneas): muchos endpoints con chequeo de rol local; cobertura de `autorizar_acceso_nino` no auditada en todos | Media | REM-001/003 |
| T-02 | JWT 7 días + sin revocación | Media | REM-016/017 |
| T-03 | `ai_controller` y `create_patient` v1 sin restricción de rol | Media | REM-006/021 |
| T-04 | Compose dev por defecto expone PostgreSQL | Alta (si se confunde con prod) | REM-015 |
| T-05 | Secretos test en `config.py` fuente | Baja | REM-010 |
| T-06 | Sin pip-audit / Dependabot | Media | REM-023 |
| T-07 | Uploads sin validación MIME/tamaño | Media | REM-019 |

---

## Matriz de cumplimiento global

```
Plan docs/05_plan_owasp.md (42 REM)

  Sí       ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  9  (21 %)
  Parcial  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  8  (19 %)
  No       ████████████████████░░░░░░░░░░░░░░░░░  25  (60 %)
```

| Dimensión OWASP (04) | Antes | Tras remediación Crítica/Alta | Comentario |
|----------------------|-------|-------------------------------|------------|
| **A01 Broken Access Control** | Alto | **Medio** | IDOR críticos cerrados en reportes/archivos/perfil; gaps en create_patient, validar_plan. |
| **A02 Cryptographic Failures** | Alto | **Medio** | Docker JWT/CORS OK; JWT 7 días y defaults test en config pendientes. |
| **A03 Injection** | Bajo | **Bajo** | Sin cambio; whitelist SQL intacta. |
| **A04 Insecure Design** | Alto | **Medio-Alto** | Rate limit + registro flag; uploads y política password pendientes. |
| **A05 Misconfiguration** | Alto | **Medio** | CORS/admin OK; compose base expone DB; Swagger abierto. |
| **A06 Vulnerable Components** | Medio | **Medio** | pgAdmin pinneado; sin CVE scan. |
| **A07 Auth Failures** | Medio | **Medio** | Rate limit parcial; sin lockout ni revocación. |
| **A08 Integrity** | Medio | **Medio** | Sin cambio sustancial. |
| **A09 Logging/Monitoring** | Medio | **Medio** | Admin logging OK; sin SIEM ni audit de lecturas. |
| **A10 SSRF** | Sin evidencia | **Sin evidencia** | — |

---

## Criterios globales del plan — estado

| Criterio | Umbral plan | Estado actual |
|----------|-------------|---------------|
| Regresión tests backend | 100 % | ✅ **36/36** |
| Regresión tests Flutter | 100 % | ✅ **3/3** (sin ampliación) |
| IDOR críticos REM-001–003 | 0 accesos cruzados en pruebas multi-usuario | ⚠️ **Parcial** — tests unitarios con mocks; sin E2E HTTP |
| Secretos en `backend/app/` y compose prod | 0 defaults peligrosos | ⚠️ **Parcial** — compose prod OK; defaults test en `config.py` |
| Login/registro demo dev | Operativo con `.env` + profile dev | ✅ Con `docker-compose.dev.yml` |
| Dashboard sin cambio contrato JSON | Mantener | ✅ Sin cambios de payload detectados |

---

## Recomendación priorizada

1. **Cerrar parcialidades Alta:** tests E2E IDOR; eliminar defaults de `config.py` a `conftest` exclusivamente; documentar obligatoriedad de `docker-compose.prod.yml`.
2. **Fase Media inmediata:** REM-016 (TTL JWT), REM-019 (uploads), REM-030/031 (auditoría auth y lecturas), REM-023 (pip-audit CI).
3. **Verificación operativa:** pentest manual reportes + descarga archivos con dos cuentas tutor antes de datos clínicos reales.

---

*Auditoría basada en código del repositorio al 11/06/2026. Complementa la auditoría original [`docs/04_auditoria_owasp.md`](04_auditoria_owasp.md) y el registro de implementación [`docs/06_remediacion_owasp_critica_alta.md`](06_remediacion_owasp_critica_alta.md).*
