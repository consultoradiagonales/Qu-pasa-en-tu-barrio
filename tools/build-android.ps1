# build-android.ps1 — Genera APK firmado para distribución / APK debug para pruebas
# Uso: .\tools\build-android.ps1 [-debug] [-bundle]
param(
    [switch]$debug,    # APK debug (no necesita keystore)
    [switch]$bundle    # AAB para Play Store en lugar de APK
)

$ErrorActionPreference = "Stop"
$PROJECT = "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"
$FLUTTER = "C:\flutter\bin\flutter.bat"

Push-Location $PROJECT

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

Write-Host "==> Listo: $PROJECT\$apk" -ForegroundColor Green
Pop-Location
