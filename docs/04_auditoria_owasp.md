# Auditoría de Seguridad OWASP Top 10 — RimAI

**Fecha:** 11 de junio de 2026  
**Alcance:** Código fuente del repositorio RimAI (backend FastAPI + cliente Flutter + Docker/CI)  
**Metodología:** Revisión estática del código real. Hallazgos reportados **solo con evidencia verificable** en archivos concretos. No se incluyen vulnerabilidades inferidas sin soporte en el código.

**Referencias:** [OWASP Top 10:2021](https://owasp.org/Top10/)

---

## Resumen ejecutivo

| Categoría OWASP | Nivel de riesgo global |
|-----------------|------------------------|
| A01 Broken Access Control | **Alto** |
| A02 Cryptographic Failures | **Alto** |
| A03 Injection | **Bajo** |
| A04 Insecure Design | **Alto** |
| A05 Security Misconfiguration | **Alto** |
| A06 Vulnerable and Outdated Components | **Medio** |
| A07 Identification and Authentication Failures | **Medio** |
| A08 Software and Data Integrity Failures | **Medio** |
| A09 Security Logging and Monitoring Failures | **Medio** |
| A10 Server-Side Request Forgery (SSRF) | **Sin evidencia** |

**Dictamen:** La aplicación implementa controles sólidos en capas concretas (bcrypt, JWT Bearer, consultas SQL parametrizadas, autorización SCQ y muchos endpoints del dashboard con chequeo de rol). Sin embargo, persisten **fallos graves de control de acceso (IDOR)** en endpoints `/api/v1/*` y descarga de archivos clínicos, **secretos y credenciales por defecto** en configuración Docker/seeds, y **ausencia de rate limiting, escaneo de dependencias y monitoreo centralizado**. El riesgo agregado para un despliegue en producción con datos clínicos de menores se califica como **Alto**, condicionado a remediar A01 y A02 antes de exponer datos reales.

---

## A01 — Broken Access Control

**Nivel de riesgo: Alto**

### Hallazgos

#### H-A01-01 — IDOR en reportes analíticos (cualquier usuario autenticado)

Cualquier usuario con JWT válido puede solicitar el reporte de **cualquier** `patient_id`. El caso de uso no valida ownership; `current_user` solo se usa para adherencia del terapeuta.

```19:34:backend/app/adapters/inbound/api/reportes_controller.py
def _get_reporte_impl(
    patient_id: int,
    inicio: datetime,
    fin: datetime,
    reporte_uc: GenerarReporteAnaliticoUseCase,
    adherencia_uc: EvaluarAdherenciaUseCase,
    current_user: dict,
):
    reporte = reporte_uc.execute(patient_id, inicio, fin)

    if current_user.get("role") == "terapeuta":
        adherencia_uc.execute(
            patient_id, current_user.get("id"), reporte.tasa_adherencia_global, 0.7
        )

    return reporte
```

```10:11:backend/app/application/usecases/generar_reporte_analitico_usecase.py
    def execute(self, patient_id: int, inicio: datetime, fin: datetime) -> ReporteAnalitico:
        actividades = self.seguimiento_repo.get_by_patient_id(patient_id)
```

**Impacto:** Exposición de datos clínicos/terapéuticos de menores a cuentas no autorizadas.  
**Recomendación:** Antes de `execute`, invocar lógica equivalente a `_autorizar_acceso_nino` o verificar tutor/terapeuta asignado según rol.

---

#### H-A01-02 — IDOR en descarga de documentos clínicos

Solo exige autenticación y conocer el `filename`; no verifica que el archivo pertenezca al tutor/terapeuta del paciente.

```179:189:backend/app/adapters/inbound/api/dashboard_controller.py
@router.get("/api/files/evaluations/{filename}")
def descargar_documento_clinico(
    filename: str,
    current_user: dict = Depends(get_current_user),
):
    safe_name = os.path.basename(filename)
    storage = CloudStorageAdapter()
    path = os.path.join(storage.upload_dir, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="Documento no encontrado")
    return FileResponse(path, filename=safe_name)
```

**Impacto:** Un atacante autenticado que obtenga o adivine nombres UUID de archivos puede descargar evaluaciones clínicas ajenas.  
**Recomendación:** Persistir metadatos de ownership en BD; validar acceso antes de servir el archivo, o usar URLs firmadas con expiración.

---

#### H-A01-03 — Actualización de perfil clínico sin autorización por niño

`PATCH /api/ninos/{nino_id}/perfil-clinico` no llama `_autorizar_acceso_nino` ni verifica rol.

```4505:4536:backend/app/adapters/inbound/api/dashboard_controller.py
@router.patch("/api/ninos/{nino_id}/perfil-clinico")
def actualizar_perfil_clinico(
    nino_id: str,
    datos: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    campos_permitidos = {"nivel_cognitivo", "diagnostico", "perfil_sensorial",
                         "objetivos_intervencion", "estado_clinico"}
    updates = {k: v for k, v in datos.items() if k in campos_permitidos}
    ...
    with _conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT perfil_sensorial FROM ninos WHERE id = %s AND activo = TRUE",
                (nino_id,),
            )
```

**Impacto:** Cualquier usuario autenticado puede modificar perfiles clínicos de cualquier niño.  
**Recomendación:** Invocar `_autorizar_acceso_nino(nino_id, current_user)` y restringir campos editables por rol.

---

#### H-A01-04 — Historial y evaluaciones v1 sin verificación de ownership

```20:33:backend/app/adapters/inbound/api/patient_controller.py
@router.post("/{patient_id}/evaluaciones")
def upload_evaluation(
    patient_id: int, 
    file: UploadFile = File(...),
    ...
    current_user: dict = Depends(get_current_user)
):
    ...
    return uc.upload_evaluation(patient_id, source, file.file, file.filename, file.content_type)

@router.get("/{patient_id}/historial")
def get_patient_history(patient_id: int, ..., current_user: dict = Depends(get_current_user)):
    return uc.get_patient_history(patient_id)
```

```14:15:backend/app/application/usecases/patient_usecases.py
    def get_patient_history(self, patient_id: int) -> dict:
        return self.patient_repo.get_patient_history(patient_id)
```

**Impacto:** Lectura/escritura de historial clínico sin comprobar relación tutor/terapeuta-paciente.  
**Recomendación:** Validar ownership en controller o caso de uso antes de delegar al repositorio.

---

#### H-A01-05 — Sincronización offline sin validar ownership del paciente

El endpoint restringe rol a tutor, pero no valida que cada `ActividadEjecutada.patient_id` pertenezca al tutor autenticado.

```47:49:backend/app/adapters/inbound/api/seguimiento_controller.py
    tutor_id = current_user.get("id")
    try:
        synced = sync_uc.execute(tutor_id, request.actividades)
```

```15:17:backend/app/application/usecases/sincronizar_datos_usecase.py
        for actividad in actividades_pendientes:
            actividad.synced_at = datetime.utcnow()
            saved = self.seguimiento_repo.save_actividad_ejecutada(actividad)
```

**Impacto:** Un tutor podría insertar sesiones falsas asociadas a pacientes de otros tutores.  
**Recomendación:** Validar en el caso de uso que `patient_id` ∈ niños del tutor antes de persistir.

---

#### H-A01-06 — Plan personalizado sin restricción de rol ni paciente

```22:27:backend/app/adapters/inbound/api/plan_controller.py
@router.post("/personalizar")
def personalizar_plan(request: GenerarPlanRequest, ..., current_user: dict = Depends(get_current_user)):
    # Solo el terapeuta debería, o se genera auto en backend
    terapeuta_id = current_user.get("id")
    plan = uc.execute(request.patient_id, terapeuta_id, request.perfil_sensorial)
    return plan
```

**Impacto:** Cualquier rol autenticado puede generar planes para cualquier `patient_id`.  
**Recomendación:** Exigir `role == terapeuta` y verificar asignación terapeuta-paciente.

---

#### H-A01-07 — Creación de usuarios con rol arbitrario (admin)

El admin puede insertar cualquier string en `rol`, incluido `admin`, sin validar contra `RoleEnum`.

```26:30:backend/app/adapters/inbound/api/admin_controller.py
class UsuarioCreateRequest(BaseModel):
    nombre: str
    email: str
    password: str
    rol: str
```

```134:140:backend/app/adapters/inbound/api/admin_controller.py
                cur.execute(
                    """
                    INSERT INTO usuarios (nombre, email, password_hash, rol, activo)
                    VALUES (%s, %s, %s, %s, TRUE)
                    ...
                    (request.nombre, request.email, hashed_password, request.rol)
                )
```

**Impacto:** Escalación de privilegios si se crea rol inválido o admin adicional sin controles adicionales; valores no enumerados pueden romper lógica de autorización.  
**Recomendación:** Usar `RoleEnum` en Pydantic y whitelist estricta; auditar creación de admins.

---

### Controles positivos observados

- Función `_autorizar_acceso_nino` implementada y usada en endpoints seleccionados del dashboard:

```392:413:backend/app/adapters/inbound/api/dashboard_controller.py
def _autorizar_acceso_nino(nino_id: str, current_user: Dict[str, Any]):
    ...
    if current_user["role"] == "terapeuta":
        ...
    elif current_user["role"] in ("padre_tutor", "tutor", "padre"):
        ...
    elif current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Acceso denegado")
```

- SCQ verifica ownership del tutor:

```33:34:backend/app/adapters/inbound/api/scq_controller.py
    if not scq_repo.verify_tutor_owns_patient(request.patient_id, current_user["id"]):
        raise HTTPException(status_code=404, detail="Niño no encontrado para este tutor")
```

- Endpoints admin verifican `role == "admin"` (p. ej. `admin_controller.py` L40–41, L57–58).

- Subida de documentos en dashboard **sí** valida tutor-niño (`dashboard_controller.py` L2720–2733).

---

## A02 — Cryptographic Failures

**Nivel de riesgo: Alto**

### Hallazgos

#### H-A02-01 — Secreto JWT predecible por defecto en Docker Compose

```31:31:docker-compose.yml
      JWT_SECRET: ${JWT_SECRET:-rimai-super-secret-key-2026}
```

**Impacto:** Despliegues sin `.env` generan tokens JWT falsificables.  
**Recomendación:** Eliminar fallback; fallar al arrancar si `JWT_SECRET` no está definido o tiene entropía insuficiente (≥256 bits).

---

#### H-A02-02 — Credenciales embebidas como defaults de test en código

```9:10:backend/app/infrastructure/config.py
_DEFAULT_JWT_SECRET = "test-jwt-secret-rimai-pytest-only"
_DEFAULT_DATABASE_URL = "postgresql://rimai_user:rimai_secure_2026@localhost:5432/rimai_db"
```

Activos solo con `PYTEST_CURRENT_TEST` o `RIMAI_ALLOW_TEST_DEFAULTS=1` (`config.py` L4–7), pero permanecen en el repositorio.

**Recomendación:** Mover defaults exclusivamente a fixtures de test; nunca incluir credenciales reales en código fuente.

---

#### H-A02-03 — Contraseñas de demo documentadas en seeds SQL montados en Docker

```196:196:backend/sql/02_seed.sql
  RAISE NOTICE 'RimAI seed listo: terapeuta@rimai.com / test1234';
```

```14:14:docker-compose.yml
      - ./backend/sql/:/docker-entrypoint-initdb.d/
```

**Impacto:** Instancias Docker reciben cuentas con contraseñas conocidas públicamente en el repo.  
**Recomendación:** Separar seeds de demo de init de producción; forzar cambio de contraseña en primer login; no montar seeds en entornos productivos.

---

#### H-A02-04 — JWT de larga duración (7 días)

```10:10:backend/app/application/usecases/auth_usecases.py
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7
```

**Impacto:** Ventana amplia de abuso si un token se filtra (dispositivo comprometido, logs de proxy).  
**Recomendación:** Reducir a 15–60 minutos con refresh token rotativo almacenado de forma segura, o revocación server-side.

---

#### H-A02-05 — Algoritmo JWT configurable sin whitelist

```35:36:backend/app/infrastructure/config.py
def get_jwt_algorithm() -> str:
    return os.getenv("JWT_ALGORITHM", "HS256")
```

**Impacto:** Configuración errónea de `JWT_ALGORITHM` podría debilitar verificación (dependiendo del comportamiento de `python-jose`).  
**Recomendación:** Fijar `algorithms=["HS256"]` en código; ignorar variable de entorno o validar contra lista permitida.

---

### Controles positivos observados

- Hashing de contraseñas con bcrypt/passlib:

```9:21:backend/app/application/usecases/auth_usecases.py
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
...
        if not pwd_context.verify(password, user.hashed_password):
            return None
```

- Token JWT almacenado en Flutter Secure Storage:

```11:24:rimai_app/lib/infrastructure/config/auth_storage_service.dart
  static const String _keyJwtToken = 'jwt_token';
  ...
      _storage.write(key: _keyJwtToken, value: token),
```

- `.env` excluido de git (`.gitignore` L1–2).

---

## A03 — Injection

**Nivel de riesgo: Bajo**

### Hallazgos

#### H-A03-01 — SQL dinámico con nombres de columna desde whitelist (riesgo residual bajo)

```4511:4562:backend/app/adapters/inbound/api/dashboard_controller.py
    campos_permitidos = {"nivel_cognitivo", "diagnostico", "perfil_sensorial",
                         "objetivos_intervencion", "estado_clinico"}
    updates = {k: v for k, v in datos.items() if k in campos_permitidos}
    ...
            cur.execute(
                f"UPDATE ninos SET {', '.join(set_clauses)} WHERE id = %s RETURNING id, estado_clinico",
                values,
            )
```

Los identificadores SQL provienen de whitelist; los valores usan placeholders `%s`. **No se encontró** concatenación directa de input de usuario en cláusulas SQL en el resto del backend.

**Recomendación:** Mantener whitelist; considerar ORM o mapeo explícito columna→setter para eliminar `f-string` en SQL.

---

#### H-A03-02 — Path traversal mitigado en descarga de archivos

```184:186:backend/app/adapters/inbound/api/dashboard_controller.py
    safe_name = os.path.basename(filename)
    storage = CloudStorageAdapter()
    path = os.path.join(storage.upload_dir, safe_name)
```

**Recomendación:** Combinar con H-A01-02 (autorización), no solo sanitización de path.

---

### Evidencia de ausencia

- Búsqueda de `subprocess`, `os.system`, `eval(`, `exec(` en `backend/app/`: **sin coincidencias**.
- Repositorios PostgreSQL y controladores usan consultas parametrizadas con `%s` de forma consistente.

---

## A04 — Insecure Design

**Nivel de riesgo: Alto**

### Hallazgos

#### H-A04-01 — Registro público de cuentas familia sin verificación

```28:31:backend/app/adapters/inbound/api/auth_controller.py
@router.post("/register")
def register(request: RegisterRequest, auth_uc: AuthUseCases = Depends(get_auth_use_cases)):
    try:
        return auth_uc.register_family_user(request.nombre, request.email, request.password)
```

```54:67:backend/app/application/usecases/auth_usecases.py
    def register_family_user(self, nombre: str, email: str, password: str) -> dict:
        ...
        user = User(
            ...
            role="padre_tutor",
            ...
        )
        created = self.user_repo.create_family_user(user)
        return self.login(created.email, password)
```

**Impacto:** Cualquier actor puede crear cuentas tutor sin verificación de identidad ni invitación.  
**Recomendación:** Flujo de invitación por terapeuta, verificación de email, o registro deshabilitado en producción.

---

#### H-A04-02 — Sin rate limiting en login ni endpoints sensibles

Búsqueda en todo el repositorio de `rate limit`, `slowapi`, `throttle`, `brute`: **sin coincidencias**.

**Impacto:** Fuerza bruta sobre `/api/v1/auth/login` y abuso de endpoints autenticados.  
**Recomendación:** Implementar rate limiting (p. ej. `slowapi` + Redis) en login, registro y sync.

---

#### H-A04-03 — Upload de archivos sin validación de tipo ni tamaño

```27:35:backend/app/adapters/outbound/storage/cloud_storage_adapter.py
        safe_name = os.path.basename(filename).replace(" ", "_")
        unique_name = f"{uuid.uuid4()}_{safe_name}"
        target = os.path.join(self.upload_dir, unique_name)
        with open(target, "wb") as out:
            while True:
                chunk = file_stream.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
```

**Impacto:** Almacenamiento de archivos arbitrarios (malware, archivos enormes → DoS de disco).  
**Recomendación:** Whitelist MIME, límite de tamaño (p. ej. 10 MB), escaneo antivirus opcional.

---

#### H-A04-04 — Sin política de complejidad de contraseña

```12:15:backend/app/adapters/inbound/api/auth_controller.py
class RegisterRequest(BaseModel):
    nombre: str
    email: str
    password: str
```

**Recomendación:** `Field(min_length=12)` + validación de complejidad; considerar Have I Been Pwned API.

---

#### H-A04-05 — Endpoint IA accesible a cualquier usuario autenticado

```14:15:backend/app/adapters/inbound/api/ai_controller.py
@router.post("/estimar-apoyo")
def estimate_support(..., current_user: dict = Depends(get_current_user)):
```

Sin restricción de rol ni throttling.

**Recomendación:** Limitar a roles clínicos; cachear respuestas; cuotas por usuario.

---

## A05 — Security Misconfiguration

**Nivel de riesgo: Alto**

### Hallazgos

#### H-A05-01 — CORS con fallback a lista por defecto incluso fuera de tests

```43:50:backend/app/infrastructure/config.py
def get_cors_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS")
    if not raw:
        if _TEST_DEFAULTS_ALLOWED:
            raw = _DEFAULT_CORS_ORIGINS
        else:
            raw = _DEFAULT_CORS_ORIGINS
    return [origin.strip() for origin in raw.split(",") if origin.strip()]
```

Ambas ramas asignan `_DEFAULT_CORS_ORIGINS`; omitir `CORS_ORIGINS` no restringe orígenes.

**Recomendación:** En producción, fallar si `CORS_ORIGINS` está vacío; no usar fallback permisivo.

---

#### H-A05-02 — CORS permisivo en métodos y headers

```30:36:backend/app/main.py
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Recomendación:** Restringir a métodos necesarios (`GET`, `POST`, `PATCH`, `DELETE`) y headers explícitos.

---

#### H-A05-03 — OpenAPI/Swagger expuesto por defecto

```24:28:backend/app/main.py
app = FastAPI(
    title="RimAI API (Hexagonal)",
    ...
)
```

No se deshabilitan `docs_url`, `redoc_url` ni `openapi_url`.

**Recomendación:** Desactivar documentación interactiva en producción (`docs_url=None`).

---

#### H-A05-04 — PostgreSQL y pgAdmin expuestos en host (Docker dev)

```10:11:docker-compose.yml
    ports:
      - "5432:5432"
```

```51:54:docker-compose.yml
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "False"
    ports:
      - "5050:80"
```

**Recomendación:** No publicar puertos DB/admin en producción; usar redes internas.

---

#### H-A05-05 — Montaje de código fuente en contenedor API

```36:37:docker-compose.yml
    volumes:
      - ./backend:/app
```

**Recomendación:** Solo en desarrollo; imagen inmutable en producción.

---

#### H-A05-06 — Sin cabeceras de seguridad HTTP

Búsqueda de `SecurityHeaders`, `X-Frame-Options`, `HSTS`: **sin coincidencias** en backend.

**Recomendación:** Middleware con `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`.

---

#### H-A05-07 — Fuga de excepciones internas en admin

```85:86:backend/app/adapters/inbound/api/admin_controller.py
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno del servidor: {str(e)}")
```

(Mismo patrón en L117, L178, L218, L271.)

**Recomendación:** Mensaje genérico al cliente; log server-side con `logger.exception`.

---

## A06 — Vulnerable and Outdated Components

**Nivel de riesgo: Medio**

### Hallazgos

#### H-A06-01 — Sin escaneo automatizado de vulnerabilidades en CI

`.github/workflows/build-apk.yml` ejecuta pytest y flutter test; no hay `pip-audit`, `safety`, Dependabot, Trivy ni SBOM.

**Recomendación:** Añadir `pip-audit -r requirements.txt` y `dart pub outdated`/OSV en pipeline; habilitar Dependabot.

---

#### H-A06-02 — `pytest` en dependencias de runtime

```16:16:backend/requirements.txt
pytest==8.3.4
```

**Recomendación:** Mover a `requirements-dev.txt`.

---

#### H-A06-03 — `python-jose` para JWT (mantenimiento limitado)

```6:6:backend/requirements.txt
python-jose[cryptography]==3.3.0
```

```3:3:backend/app/application/usecases/auth_usecases.py
from jose import jwt
```

**Recomendación:** Evaluar migración a `PyJWT` o `authlib`; ejecutar escaneo CVE periódico.

---

#### H-A06-04 — Imagen pgAdmin sin pin de versión

```44:45:docker-compose.yml
  pgadmin:
    image: dpage/pgadmin4:latest
```

**Recomendación:** Fijar tag semver verificado.

---

#### H-A06-05 — Dependencias declaradas sin uso aparente en backend

```3:4:backend/requirements.txt
sqlalchemy==2.0.30
asyncpg==0.29.0
```

Superficie de ataque ampliada sin beneficio funcional detectado en `backend/app/`.

**Recomendación:** Eliminar dependencias no usadas.

---

### Nota

No se ejecutó escaneo CVE en tiempo real contra bases NVD/OSV en esta auditoría. Los hallazgos se basan en configuración del proyecto, no en CVE confirmados para versiones pinneadas.

---

## A07 — Identification and Authentication Failures

**Nivel de riesgo: Medio**

### Hallazgos

#### H-A07-01 — Sin protección contra fuerza bruta en login

```17:20:backend/app/adapters/inbound/api/auth_controller.py
@router.post("/login")
def login(request: LoginRequest, auth_uc: AuthUseCases = Depends(get_auth_use_cases)):
    try:
        return auth_uc.login(request.email, request.password)
```

Sin rate limit, captcha, lockout ni registro de intentos fallidos.

**Recomendación:** Rate limit + backoff exponencial; alertas tras N fallos.

---

#### H-A07-02 — Sin revocación server-side de tokens

JWT stateless sin blacklist ni refresh token (`auth_usecases.py` L41–48). Logout solo borra token en cliente (`auth_storage_service.dart` L71–77).

**Recomendación:** Refresh tokens con rotación; endpoint de revocación; TTL corto en access token.

---

#### H-A07-03 — Validación de email mínima en registro

Backend acepta cualquier string en `email: str` del `RegisterRequest`; el dominio `User` usa `EmailStr` internamente pero el endpoint de registro no lo aplica en el request model.

**Recomendación:** Usar `EmailStr` en `RegisterRequest` y `LoginRequest`.

---

#### H-A07-04 — Cliente Flutter asume token válido sin red

```114:115:rimai_app/lib/infrastructure/config/auth_storage_service.dart
      // Otro error (sin red, timeout) → asumir válido para no bloquear
      return true;
```

**Impacto:** Diseño offline-first; no es vulnerabilidad server-side, pero prolonga uso de tokens potencialmente revocados offline.  
**Recomendación:** Documentar trade-off; revalidar al recuperar conectividad.

---

### Controles positivos observados

- OAuth2 Bearer scheme (`dependencies.py` L28–41).
- Verificación server-side opcional vía `/api/v1/auth/me` (`auth_storage_service.dart` L103–106).
- Expiración JWT verificada en cliente (`JwtDecoder.isExpired`, L88–90).

---

## A08 — Software and Data Integrity Failures

**Nivel de riesgo: Medio**

### Hallazgos

#### H-A08-01 — Carga de modelo ML con `joblib.load` sin verificación de integridad

```11:17:backend/app/application/usecases/ai_support_usecases.py
    def _load_model(self):
        try:
            model_path = os.path.join(os.path.dirname(__file__), "..", "..", "ai", "models", "rf_support_level.pkl")
            if os.path.exists(model_path):
                self.model = joblib.load(model_path)
        except Exception:
            pass
```

**Impacto:** Si un atacante modifica el `.pkl` en disco, puede alterar predicciones clínicas (deserialización pickle).  
**Recomendación:** Firmar artefactos; verificar hash antes de cargar; preferir formatos seguros (ONNX); restringir permisos del directorio.

---

#### H-A08-02 — `requirements.txt` sin lockfile ni hashes

```1:16:backend/requirements.txt
fastapi==0.111.0
...
pytest==8.3.4
```

**Recomendación:** Generar `requirements.lock` con `pip-tools` y hashes `--require-hashes`.

---

#### H-A08-03 — Sin certificate pinning en cliente Flutter

```7:8:rimai_app/lib/core/constants/api_constants.dart
  static const String baseUrl = 'https://rimai-production.up.railway.app';
```

Búsqueda de `BadCertificate`, `SecurityContext` en `.dart`: **sin coincidencias**.

**Recomendación:** Evaluar pinning para entornos con datos clínicos sensibles.

---

#### H-A08-04 — CI build APK sin pasos de firma/attestación documentados

```87:90:.github/workflows/build-apk.yml
      - name: Build APK
        run: |
          cd rimai_app
          flutter build apk --release
```

**Recomendación:** Documentar firma con keystore en secrets; Play App Signing o verificación de integridad.

---

### Controles positivos observados

- `pubspec.lock` incluye hashes SHA256 de paquetes Flutter (p. ej. `pubspec.lock` L280–281).

---

## A09 — Security Logging and Monitoring Failures

**Nivel de riesgo: Medio**

### Hallazgos

#### H-A09-01 — Sin APM, SIEM ni alertas centralizadas

Búsqueda de `sentry`, `prometheus`, `structlog`, `logging.basicConfig` en backend: **sin coincidencias** de integración productiva.

**Recomendación:** Integrar Sentry/Datadog; alertas en errores 5xx, intentos de login fallidos, accesos IDOR.

---

#### H-A09-02 — Sin registro de intentos de autenticación fallidos

`auth_usecases.py` devuelve error genérico en login fallido sin log de auditoría de seguridad.

**Recomendación:** Registrar email (hash), IP, timestamp en tabla de seguridad o SIEM.

---

#### H-A09-03 — Auditoría parcial de acciones de negocio

Existe `_registrar_auditoria` insertando en `logs_auditoria` (`dashboard_controller.py` L130–163), usada en operaciones clínicas seleccionadas. No cubre accesos denegados, login, ni endpoints `/api/v1/reportes`.

**Recomendación:** Extender auditoría a lecturas de datos sensibles y eventos de seguridad.

---

#### H-A09-04 — Logs server-side con stack trace completo (correcto) vs fuga en admin

Handlers globales registran excepciones sin exponerlas al cliente:

```47:54:backend/app/adapters/inbound/api/exception_handlers.py
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    ...
    logger.exception("Error interno no controlado: %s", exc)
    return _error_body(
        "Error interno del servidor.",
        "INTERNAL_ERROR",
        500,
    )
```

Contraste con H-A05-07 (admin expone `str(e)`).

---

#### H-A09-05 — Errores de validación exponen detalle de campos

```28:34:backend/app/adapters/inbound/api/exception_handlers.py
        content={
            "detail": "Datos de entrada inválidos.",
            "code": "VALIDATION_ERROR",
            "errors": exc.errors(),
        },
```

**Impacto:** Bajo en API autenticada; puede revelar estructura interna de modelos.  
**Recomendación:** En producción, simplificar `errors` o limitar a campos del request.

---

## A10 — Server-Side Request Forgery (SSRF)

**Nivel de riesgo: Sin evidencia**

### Análisis

Búsqueda en `backend/**/*.py` de clientes HTTP salientes (`httpx`, `requests`, `aiohttp`, `urllib.request`): **0 coincidencias**.

El backend no implementa endpoints que reciban URLs de usuario y las fetcheen server-side. Las operaciones de red están en el cliente Flutter (`dio`, `http`) contra `baseUrl` configurado estáticamente.

**Recomendación:** Si en el futuro se añaden webhooks, importación de URLs o proxies, aplicar whitelist de destinos, bloqueo de IPs privadas (RFC 1918, link-local) y timeouts estrictos.

---

## Matriz de priorización de remediación

| Prioridad | ID | Categoría | Acción |
|-----------|-----|-----------|--------|
| P0 | H-A01-01, H-A01-02, H-A01-03 | A01 | Autorización en reportes, descarga de archivos y PATCH perfil clínico |
| P0 | H-A02-01, H-A02-03 | A02 | Eliminar JWT default en Docker; no usar seeds demo en producción |
| P1 | H-A01-04, H-A01-05, H-A01-06 | A01 | Ownership en perfiles v1, sync y planes |
| P1 | H-A04-02, H-A07-01 | A04/A07 | Rate limiting en login/registro |
| P1 | H-A05-01, H-A05-07 | A05 | CORS estricto; sanitizar errores admin |
| P2 | H-A02-04, H-A04-04 | A02/A04 | TTL JWT corto; política de contraseñas |
| P2 | H-A04-03 | A04 | Validación uploads |
| P2 | H-A06-01 | A06 | Escaneo CVE en CI |
| P2 | H-A08-01 | A08 | Integridad modelo ML |
| P3 | H-A05-03, H-A05-06 | A05 | Ocultar Swagger; security headers |
| P3 | H-A09-01, H-A09-02 | A09 | Monitoreo y logs de auth |

---

## Dictamen final

RimAI presenta **fundamentos de seguridad aceptables en capas puntuales** (bcrypt, JWT Bearer, SQL parametrizado, autorización robusta en SCQ y gran parte del dashboard terapeuta/familia), pero **no está listo para producción con datos clínicos reales** sin remediar los hallazgos P0.

Los riesgos más urgentes son de **control de acceso (IDOR)** en la capa hexagonal `/api/v1/*` y descarga de documentos, y de **gestión criptográfica** (secretos por defecto, cuentas seed con contraseñas conocidas, tokens de 7 días). La ausencia de rate limiting, escaneo de dependencias y monitoreo eleva el riesgo operacional.

**Calificación OWASP agregada: Alto** (con componentes en Bajo/Sin evidencia en inyección y SSRF).

---

*Auditoría basada en revisión estática del código al 11/06/2026. Complementa [`docs/01_auditoria_furps.md`](01_auditoria_furps.md) y [`docs/03_auditoria_implementacion_furps.md`](03_auditoria_implementacion_furps.md).*
