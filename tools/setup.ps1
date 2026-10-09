# setup.ps1 — Instala todo el entorno desde cero en un PC Windows
# Ejecutar desde PowerShell como administrador:
#   cd "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"
#   .\tools\setup.ps1

$ErrorActionPreference = "Stop"
$PROJECT = "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function SKIP($msg) { Write-Host "    SKIP: $msg" -ForegroundColor Yellow }

# ── 1. Flutter SDK ─────────────────────────────────────────────────────────────
Step "Flutter SDK"
if (Test-Path "C:\flutter\bin\flutter.bat") {
    SKIP "Ya instalado en C:\flutter"
} else {
    $zip = "$env:TEMP\flutter.zip"
    Write-Host "    Descargando (~1GB)..."
    Invoke-WebRequest "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.27.4-stable.zip" -OutFile $zip
    Expand-Archive $zip "C:\" -Force
    Remove-Item $zip
    OK "Flutter instalado en C:\flutter"
}

# ── 2. PATH de Flutter ─────────────────────────────────────────────────────────
Step "PATH"
$current = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($current -notlike "*C:\flutter\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$current;C:\flutter\bin", "User")
    $env:PATH = "$env:PATH;C:\flutter\bin"
    OK "C:\flutter\bin agregado al PATH del usuario"
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
    Expand-Archive $jdkZip "C:\" -Force
    Rename-Item "C:\jdk-17.0.2" "C:\jdk17" -ErrorAction SilentlyContinue
    Remove-Item $jdkZip
    $javaPath = "C:\jdk17\bin"
    $current = [Environment]::GetEnvironmentVariable("PATH", "User")
    [Environment]::SetEnvironmentVariable("PATH", "$current;$javaPath", "User")
    $env:PATH = "$env:PATH;$javaPath"
    [Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\jdk17", "User")
    $env:JAVA_HOME = "C:\jdk17"
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
& "C:\flutter\bin\dart.bat" pub global activate flutterfire_cli
$pubCache = "$env:LOCALAPPDATA\Pub\Cache\bin"
$current = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($current -notlike "*$pubCache*") {
    [Environment]::SetEnvironmentVariable("PATH", "$current;$pubCache", "User")
    $env:PATH = "$env:PATH;$pubCache"
}
OK "FlutterFire CLI instalado"

# ── 6. flutter pub get ─────────────────────────────────────────────────────────
Step "Dependencias del proyecto"
Push-Location $PROJECT
& "C:\flutter\bin\flutter.bat" pub get
Pop-Location
OK "pub get completado"

# ── 7. flutter doctor ─────────────────────────────────────────────────────────
Step "Flutter doctor"
& "C:\flutter\bin\flutter.bat" doctor

Write-Host "`n=== SETUP COMPLETO ===" -ForegroundColor Green
Write-Host "Próximos pasos:"
Write-Host "  1. Aceptar licencias Android: flutter doctor --android-licenses"
Write-Host "  2. Configurar Firebase: flutterfire configure"
Write-Host "  3. Compilar web:      .\tools\build-web.ps1"
Write-Host "  4. Compilar Android:  .\tools\build-android.ps1"
