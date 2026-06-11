# Remediación OWASP — Crítica y Alta (implementada)

**Fecha:** 11 de junio de 2026  
**Plan fuente:** [`docs/05_plan_owasp.md`](05_plan_owasp.md)  
**Validación:** `pytest backend/tests` → **36/36** · `flutter test` → **3/3**

---

## Resumen

| REM | Prioridad | Estado | Descripción breve |
|-----|-----------|--------|-------------------|
| REM-001 | Crítica | ✅ | Autorización en reportes `/api/v1/reportes` |
| REM-002 | Crítica | ✅ | Descarga de archivos clínicos con ownership |
| REM-003 | Crítica | ✅ | PATCH perfil clínico con auth + campos por rol |
| REM-004 | Crítica | ✅ | JWT obligatorio en Docker (sin fallback) |
| REM-005 | Crítica | ✅ | Seeds demo solo con perfil `dev` |
| REM-006 | Alta | ✅ | Ownership en perfiles v1 |
| REM-007 | Alta | ✅ | Validación patient_id en sync offline |
| REM-008 | Alta | ✅ | Plan personalizado solo terapeuta asignado |
| REM-009 | Alta | ✅ | `RoleEnum` en creación de usuarios admin |
| REM-010 | Alta | ✅ | Secretos fuera de `config.py` en producción |
| REM-011 | Alta | ✅ | Rate limiting login/registro (`slowapi`) |
| REM-012 | Alta | ✅ | CORS obligatorio fuera de tests |
| REM-013 | Alta | ✅ | Errores admin sanitizados + logging |
| REM-014 | Alta | ✅ | `ALLOW_PUBLIC_REGISTER` configurable |
| REM-015 | Alta | ✅ | `docker-compose.prod.yml` sin puertos DB |

---

## Cambios por REM

### REM-001 — IDOR reportes
- **Archivo nuevo:** `backend/app/infrastructure/authorization.py` — `autorizar_acceso_nino()`.
- **Modificado:** `reportes_controller.py` — verifica acceso antes de `execute()`.
- **Compatibilidad:** Mismo JSON de respuesta; accesos no autorizados → 403/404.

### REM-002 — IDOR descarga documentos
- **Modificado:** `dashboard_controller.py` — `resolve_nino_id_for_clinical_file()` + autorización.
- **Compatibilidad:** URLs `/api/files/evaluations/{uuid}_...` sin cambio.

### REM-003 — PATCH perfil clínico
- **Modificado:** `dashboard_controller.py` — `autorizar_acceso_nino()` + `campos_perfil_editables_por_rol()`.
- **Tutores:** solo `perfil_sensorial`. **Terapeutas/admin:** campos clínicos completos.

### REM-004 — JWT Docker
- **Modificado:** `docker-compose.yml` — `JWT_SECRET: ${JWT_SECRET:?...}`.
- **Modificado:** `.env.example` — instrucción `openssl rand -hex 32`.

### REM-005 — Seeds demo
- **Modificado:** `docker-compose.yml` — sin montar `02_seed.sql` / `05_seed_test.sql`.
- **Nuevo:** `docker-compose.dev.yml` — monta seeds con `docker compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev up`.
- **Modificado:** `02_seed.sql` — eliminado password en claro del `RAISE NOTICE`.

### REM-006 — Perfiles v1
- **Modificado:** `patient_controller.py` — autorización en historial, upload y perfil clínico.

### REM-007 — Sync offline
- **Modificado:** `sincronizar_datos_usecase.py` — rechaza lote si algún `patient_id` no es del tutor.

### REM-008 — Planes
- **Modificado:** `plan_controller.py` — rol terapeuta + `verify_terapeuta_assigned_to_patient()`.

### REM-009 — Rol admin
- **Modificado:** `admin_controller.py` — `UsuarioCreateRequest.rol: RoleEnum`.

### REM-010 — Secretos en config
- **Modificado:** `config.py` — defaults solo con `RIMAI_ALLOW_TEST_DEFAULTS`; sin strings en módulo app para prod.
- **Modificado:** `conftest.py` — variables de test centralizadas.

### REM-011 — Rate limiting
- **Nuevo:** `rate_limit.py`, dependencia `slowapi==0.1.9`.
- **Modificado:** `auth_controller.py` — 5/min login, 3/h registro; deshabilitado en tests.
- **Modificado:** `main.py` — `SlowAPIMiddleware`.

### REM-012 — CORS
- **Modificado:** `config.py` — `RuntimeError` si `CORS_ORIGINS` vacío fuera de tests.

### REM-013 — Errores admin
- **Modificado:** `admin_controller.py` — `logger.exception` + mensajes genéricos 500.

### REM-014 — Registro público
- **Modificado:** `config.py` — `allow_public_register()`; default `false` en prod, `true` en tests/dev.
- **Modificado:** `auth_controller.py` — 403 si registro deshabilitado.

### REM-015 — Docker prod
- **Nuevo:** `docker-compose.prod.yml` — sin puertos DB, sin bind mount API, `ALLOW_PUBLIC_REGISTER=false`.

---

## Uso Docker post-remediación

```bash
# Desarrollo con datos demo
docker compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev up

# Producción local (sin seeds, sin puertos DB)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up
```

Requiere `.env` con `JWT_SECRET`, `CORS_ORIGINS`, credenciales PostgreSQL.

---

## Tests añadidos

`backend/tests/test_security_remediation.py` — 8 casos: campos por rol, JWT HS256, autorización, sync, resolución de archivos, `RoleEnum`.

---

## Flujos validados (sin regresión)

| Flujo | Resultado |
|-------|-----------|
| Login / JWT / `/me` | ✅ Tests + auth intacto |
| Endpoints REST dashboard | ✅ 28 tests previos + dashboard imports OK |
| Control de roles (SCQ, admin, terapeuta) | ✅ SCQ tests 7/7 |
| Formularios Pydantic (admin rol, sync) | ✅ ValidationError en rol inválido |
| Integración DB (repos, pool) | ✅ Tests unitarios sin regresión |

---

*Siguiente fase sugerida: remediaciones **Media** del plan OWASP (REM-016 en adelante).*
