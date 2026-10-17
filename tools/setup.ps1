# setup.ps1 — Instala todo el entorno desde cero en un PC Windows
# Ejecutar desde PowerShell como administrador:
#   cd "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"
#   .\tools\setup.ps1

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "environment.ps1")
$PROJECT = "E:\condi"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function SKIP($msg) { Write-Host "    SKIP: $msg" -ForegroundColor Yellow }

# ── 1. Flutter SDK ─────────────────────────────────────────────────────────────
Step "Flutter SDK"
if (Test-Path "E:\CodexTools\flutter\bin\flutter.bat") {
    SKIP "Ya instalado en E:\CodexTools\flutter"
} else {
    $zip = "$env:TEMP\flutter.zip"
    Write-Host "    Descargando (~1GB)..."
    Invoke-WebRequest "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip" -OutFile $zip
    Expand-Archive $zip "E:\CodexTools" -Force
    Remove-Item $zip
    OK "Flutter instalado en E:\CodexTools\flutter"
}

# ── 2. PATH de Flutter ─────────────────────────────────────────────────────────
Step "PATH"
$current = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($current -notlike "*E:\CodexTools\flutter\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$current;E:\CodexTools\flutter\bin", "User")
    $env:PATH = "$env:PATH;E:\CodexTools\flutter\bin"
    OK "E:\CodexTools\flutter\bin agregado al PATH del usuario"
} else {
    SKIP "Ya en PATH"
}

# ── 3. Java JDK 17 ─────────────────────────────────────────────────────────────
Step "Java JDK 17"
if (Get-Command java -ErrorAction SilentlyContinue) {
    SKIP "Java ya disponible"
} else {
    Write-Host "    Descargando OpenJDK 17..."
    $jdkUrl = "https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d99f26a2/8/GPL/openjdk-17.0.2_windows-x64_bin.zip"
    $jdkZip = "$env:TEMP\jdk17.zip"
    Invoke-WebRequest $jdkUrl -OutFile $jdkZip
    Expand-Archive $jdkZip "E:\condi\dev" -Force
    Rename-Item "E:\condi\dev\jdk-17.0.2" "jdk17" -ErrorAction SilentlyContinue
    Remove-Item $jdkZip
    $javaPath = "E:\condi\dev\jdk17\bin"
    $current = [Environment]::GetEnvironmentVariable("PATH", "User")
    [Environment]::SetEnvironmentVariable("PATH", "$current;$javaPath", "User")
    $env:PATH = "$env:PATH;$javaPath"
    [Environment]::SetEnvironmentVariable("JAVA_HOME", "E:\condi\dev\jdk17", "User")
    $env:JAVA_HOME = "E:\condi\dev\jdk17"
    OK "Java JDK 17 instalado"
}

# ── 4. Firebase CLI ────────────────────────────────────────────────────────────
Step "Firebase CLI"
if (Get-Command firebase -ErrorAction SilentlyContinue) {
    SKIP "Ya instalado"
} else {
    npm install -g firebase-tools
    OK "Firebase CLI instalado"
}

# ── 5. FlutterFire CLI ─────────────────────────────────────────────────────────
Step "FlutterFire CLI"
& "E:\CodexTools\flutter\bin\dart.bat" pub global activate flutterfire_cli
$pubCache = "$env:PUB_CACHE\bin"
$current = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($current -notlike "*$pubCache*") {
    [Environment]::SetEnvironmentVariable("PATH", "$current;$pubCache", "User")
    $env:PATH = "$env:PATH;$pubCache"
}
OK "FlutterFire CLI instalado"

# ── 6. flutter pub get ─────────────────────────────────────────────────────────
Step "Dependencias del proyecto"
Push-Location $PROJECT
& "E:\CodexTools\flutter\bin\flutter.bat" pub get
Pop-Location
OK "pub get completado"

# ── 7. flutter doctor ─────────────────────────────────────────────────────────
Step "Flutter doctor"
& "E:\CodexTools\flutter\bin\flutter.bat" doctor

Write-Host "`n=== SETUP COMPLETO ===" -ForegroundColor Green
Write-Host "Próximos pasos:"
Write-Host "  1. Aceptar licencias Android: flutter doctor --android-licenses"
Write-Host "  2. Configurar Firebase: flutterfire configure"
Write-Host "  3. Compilar web:      .\tools\build-web.ps1"
Write-Host "  4. Compilar Android:  .\tools\build-android.ps1"
