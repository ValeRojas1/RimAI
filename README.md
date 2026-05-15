# RimAI — Plataforma Terapéutica Adaptativa con IA para niños con TEA

## Requisitos previos
- Flutter SDK 3.x
- Docker Desktop 4.x
- VS Code
- Git

## Levantar el entorno de desarrollo

### 1. Clonar el repositorio
```bash
git clone https://github.com/TU_USUARIO/rimai.git
cd rimai
git checkout develop
```

### 2. Configurar variables de entorno
```bash
# Copia el archivo de ejemplo y edita con tus datos
cp .env.example .env
```

### 3. Levantar la base de datos
```bash
docker compose up -d
```

### 4. Abrir el proyecto Flutter
```bash
cd rimai_app
flutter pub get
```

## Accesos locales
| Servicio | URL | Credenciales |
|---|---|---|
| pgAdmin | http://localhost:5050 | las de tu .env |
| PostgreSQL | localhost:5432 | las de tu .env |

## Estructura del proyecto

## Descarga Nuestra APP
- https://github.com/ValeRojas1/RimAI/releases/tag/v1
