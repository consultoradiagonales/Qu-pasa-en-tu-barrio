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
# Se monta el directorio padre, no el proyecto: Gradle necesita que éste tenga
# padre y Java no soporta correctamente la ruta Unicode larga del workspace.
$availableDrives = @('Q:', 'R:', 'S:') |
    Where-Object { -not (Test-Path -LiteralPath "$($_)\") } |
    Select-Object -First 2
if ($availableDrives.Count -lt 2) {
    throw 'No hay dos letras de unidad temporales disponibles para compilar.'
}
$buildDrive = $availableDrives[0]
$sourceDrive = $availableDrives[1]
$projectParent = Split-Path -Parent $PROJECT
$projectShortName = (& cmd.exe /d /c 'for %I in ("%CONDI_PROJECT%") do @echo %~snxI').Trim()
& "$env:SystemRoot\System32\subst.exe" $buildDrive $PROJECT
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo crear la unidad temporal de compilación.'
}
& "$env:SystemRoot\System32\subst.exe" $sourceDrive $projectParent
if ($LASTEXITCODE -ne 0) {
    & "$env:SystemRoot\System32\subst.exe" $buildDrive /D | Out-Null
    throw 'No se pudo crear la unidad temporal del proyecto.'
}
$buildRoot = "$sourceDrive\$projectShortName"
$originalJdk = $env:JAVA_HOME
$localPropertiesPath = Join-Path $PROJECT 'android\local.properties'
$localPropertiesOriginal = [System.IO.File]::ReadAllText($localPropertiesPath)

try {
    $buildFlutter = "$buildRoot\dev\flutter\bin\flutter.bat"
    $env:JAVA_HOME = "$buildRoot\dev\jdk17"
    $env:GRADLE_USER_HOME = "$buildDrive\gradle"
    $env:PUB_CACHE = "$buildDrive\pub-cache"
    $env:ANDROID_USER_HOME = "$buildDrive\dev\android-user"
    $env:TEMP = "$buildDrive\dev\temp"
    $env:TMP = $env:TEMP
    $localPropertiesBuild = @(
        "flutter.sdk=$($buildRoot.Replace(':', '\:'))\\dev\\flutter"
        "sdk.dir=$($buildRoot.Replace(':', '\:'))\\dev\\android-sdk"
    ) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText($localPropertiesPath, $localPropertiesBuild, [System.Text.UTF8Encoding]::new($false))
    Push-Location $buildRoot
    try {
        if ($debug) {
            Write-Host "==> APK debug..." -ForegroundColor Cyan
            & $buildFlutter build apk --debug
            $apk = "build\app\outputs\flutter-apk\app-debug.apk"
        } elseif ($bundle) {
            Write-Host "==> Android App Bundle (Play Store)..." -ForegroundColor Cyan
            # Requiere key.properties configurado en android/
            & $buildFlutter build appbundle --release
            $apk = "build\app\outputs\bundle\release\app-release.aab"
        } else {
            Write-Host "==> APK release..." -ForegroundColor Cyan
            # Requiere android/key.properties con credenciales de firma
            # Ver tools/signing/README.md para generar el keystore
            & $buildFlutter build apk --release --split-per-abi
            $apk = "build\app\outputs\flutter-apk\"
        }

        if ($LASTEXITCODE -ne 0) {
            throw "La compilación de Flutter falló con código $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
} finally {
    [System.IO.File]::WriteAllText($localPropertiesPath, $localPropertiesOriginal, [System.Text.UTF8Encoding]::new($false))
    & "$env:SystemRoot\System32\subst.exe" $sourceDrive /D | Out-Null
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
