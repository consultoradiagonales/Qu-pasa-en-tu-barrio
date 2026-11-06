# build-android.ps1 — Genera APK firmado para distribución / APK debug para pruebas
# Uso: .\tools\build-android.ps1 [-debug] [-bundle]
param(
    [switch]$debug,    # APK debug (no necesita keystore)
    [switch]$bundle    # AAB para Play Store en lugar de APK
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "environment.ps1")
$PROJECT = $env:CONDI_PROJECT
$FLUTTER = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
$buildDrive = @('Q:', 'R:', 'S:') |
    Where-Object { -not (Test-Path -LiteralPath "$($_)\") } |
    Select-Object -First 1
if (-not $buildDrive) {
    throw 'No hay una letra de unidad temporal disponible para compilar.'
}

& "$env:SystemRoot\System32\subst.exe" $buildDrive $PROJECT
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo crear la unidad temporal de compilación.'
}
$originalJdk = $env:JAVA_HOME

try {
    $env:JAVA_HOME = "$buildDrive\dev\jdk17"
    $env:GRADLE_USER_HOME = "$buildDrive\gradle"
    $env:PUB_CACHE = "$buildDrive\pub-cache"
    $env:ANDROID_USER_HOME = "$buildDrive\dev\android-user"
    $env:TEMP = "$buildDrive\dev\temp"
    $env:TMP = $env:TEMP
    & $FLUTTER config --jdk-dir "$buildDrive\dev\jdk17" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo preparar Java para la unidad temporal.'
    }
    Push-Location "$buildDrive\"
    try {
        if ($debug) {
            Write-Host "==> APK debug..." -ForegroundColor Cyan
            & $FLUTTER build apk --debug
            $apk = "build\app\outputs\flutter-apk\app-debug.apk"
        } elseif ($bundle) {
            Write-Host "==> Android App Bundle (Play Store)..." -ForegroundColor Cyan
            # Requiere key.properties configurado en android/
            & $FLUTTER build appbundle --release
            $apk = "build\app\outputs\bundle\release\app-release.aab"
        } else {
            Write-Host "==> APK release..." -ForegroundColor Cyan
            # Requiere android/key.properties con credenciales de firma
            # Ver tools/signing/README.md para generar el keystore
            & $FLUTTER build apk --release --split-per-abi
            $apk = "build\app\outputs\flutter-apk\"
        }

        if ($LASTEXITCODE -ne 0) {
            throw "La compilación de Flutter falló con código $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
} finally {
    & $FLUTTER config --jdk-dir $originalJdk | Out-Null
    & "$env:SystemRoot\System32\subst.exe" $buildDrive /D | Out-Null
    $env:JAVA_HOME = $originalJdk
    $env:GRADLE_USER_HOME = Join-Path $PROJECT 'gradle'
    $env:PUB_CACHE = Join-Path $PROJECT 'pub-cache'
    $env:ANDROID_USER_HOME = Join-Path $PROJECT 'dev\android-user'
    $env:TEMP = Join-Path $PROJECT 'dev\temp'
    $env:TMP = $env:TEMP
    Push-Location $PROJECT
    try {
        & $FLUTTER pub get | Out-Null
    } finally {
        Pop-Location
    }
}

Write-Host "==> Listo: $PROJECT\$apk" -ForegroundColor Green
