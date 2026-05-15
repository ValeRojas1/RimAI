# ============================================================
# RimAI â€” Script de aplicaciÃ³n de migraciones
# ============================================================
# Uso: .\backend\sql\apply_migrations.ps1
#
# Requisitos previos:
#   1. Docker Desktop corriendo
#   2. Contenedor rimai-db (postgres) arriba:
#      docker compose up -d db
# ============================================================

param(
    [string]$DbContainer = "rimai_postgres",
    [string]$DbName      = "rimai_db",
    [string]$DbUser      = "rimai_user",
    [switch]$WithTestSeed,
    [switch]$ResetFirst
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$MIGRATIONS = @(
    "01_init.sql",
    "02_seed.sql",
    "03_migration_estados.sql",
    "04_migration_compat.sql"
)

if ($WithTestSeed) {
    $MIGRATIONS += "05_seed_test.sql"
}

# --- FunciÃ³n auxiliar --------------------------------------------------------
function Invoke-SQL {
    param([string]$File, [string]$Label)
    Write-Host ""
    Write-Host "  â–¶ $Label" -ForegroundColor Cyan
    $fullPath = Join-Path $SCRIPT_DIR $File
    $result = docker exec -i $DbContainer psql -U $DbUser -d $DbName -f "/migrations/$File" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  âœ— ERROR en $File" -ForegroundColor Red
        Write-Host $result
        exit 1
    }
    Write-Host "  âœ“ OK" -ForegroundColor Green
}

# --- Verificar que el contenedor estÃ© corriendo ------------------------------
Write-Host ""
Write-Host "=== RimAI â€” Aplicador de Migraciones ===" -ForegroundColor Yellow
Write-Host ""

$containerStatus = docker inspect --format="{{.State.Status}}" $DbContainer 2>$null
if ($containerStatus -ne "running") {
    Write-Host "  El contenedor '$DbContainer' no estÃ¡ corriendo." -ForegroundColor Red
    Write-Host "  Ejecuta primero: docker compose up -d db" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Contenedor '$DbContainer': OK" -ForegroundColor Green

# --- Copiar scripts al contenedor --------------------------------------------
Write-Host ""
Write-Host "  Copiando scripts SQL al contenedor..."
docker exec $DbContainer mkdir -p /migrations | Out-Null
foreach ($file in $MIGRATIONS) {
    $localPath = Join-Path $SCRIPT_DIR $file
    if (Test-Path $localPath) {
        docker cp $localPath "${DbContainer}:/migrations/$file" | Out-Null
        Write-Host "    â†‘ $file" -ForegroundColor DarkGray
    } else {
        Write-Host "    âš  $file no encontrado, se omite" -ForegroundColor Yellow
    }
}

# --- Resetear base si se pide ------------------------------------------------
if ($ResetFirst) {
    Write-Host ""
    Write-Host "  âš  RESET: eliminando y recreando base de datos..." -ForegroundColor Yellow
    docker exec $DbContainer psql -U $DbUser -d postgres -c "DROP DATABASE IF EXISTS $DbName;" | Out-Null
    docker exec $DbContainer psql -U $DbUser -d postgres -c "CREATE DATABASE $DbName;" | Out-Null
    Write-Host "  Base '$DbName' recreada." -ForegroundColor Green
}

# --- Aplicar migraciones en orden --------------------------------------------
Write-Host ""
Write-Host "  Aplicando migraciones..." -ForegroundColor White

foreach ($file in $MIGRATIONS) {
    $localPath = Join-Path $SCRIPT_DIR $file
    if (Test-Path $localPath) {
        Invoke-SQL -File $file -Label $file
    }
}

# --- Resumen final -----------------------------------------------------------
Write-Host ""
Write-Host "=== MigraciÃ³n completada ===" -ForegroundColor Green
Write-Host ""

$statsQuery = @"
SELECT
    estado_clinico,
    COUNT(*) AS total
FROM ninos
WHERE activo = TRUE
GROUP BY estado_clinico
ORDER BY estado_clinico;
"@

Write-Host "  Estado actual de la base:" -ForegroundColor White
docker exec $DbContainer psql -U $DbUser -d $DbName -c $statsQuery

Write-Host ""
if ($WithTestSeed) {
    Write-Host "  Usuarios de prueba disponibles:" -ForegroundColor Cyan
    Write-Host "    terapeuta@rimai.dev  / Rimai2024!" -ForegroundColor White
    Write-Host "    familia1@rimai.dev   / Rimai2024!" -ForegroundColor White
    Write-Host "    familia2@rimai.dev   / Rimai2024!" -ForegroundColor White
}
Write-Host ""

