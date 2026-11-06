# Inicia ConDi y el centro de gestión contra Firebase Emulator Suite.
[CmdletBinding()]
param(
    [switch]$OmitirCompilacion
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')

$proyecto = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
$firebase = Join-Path $proyecto 'dev\firebase-cli\lib\bin\firebase.js'

if (-not (Test-Path -LiteralPath $flutter)) {
    throw "No se encontró Flutter en $flutter"
}
if (-not (Test-Path -LiteralPath $firebase)) {
    throw "No se encontró Firebase CLI en $firebase"
}

Push-Location $proyecto
try {
    if (-not $OmitirCompilacion) {
        & $flutter build web --release --no-tree-shake-icons
        if ($LASTEXITCODE -ne 0) {
            throw 'No se pudo compilar la versión web de ConDi.'
        }
    }
    & (Join-Path $PSScriptRoot 'sincronizar-admin-web.ps1') -Proyecto $proyecto

    Write-Host ''
    Write-Host 'ConDi local:      http://127.0.0.1:5000/' -ForegroundColor Green
    Write-Host 'Gestión local:    http://127.0.0.1:5000/admin/' -ForegroundColor Green
    Write-Host 'Firebase Emulator: http://127.0.0.1:4000/' -ForegroundColor Green
    Write-Host ''
    & node $firebase emulators:start --project project-5fc9024a-e961-42b7-9ee --only auth,firestore,storage,functions,hosting
    if ($LASTEXITCODE -ne 0) {
        throw 'Firebase Emulator Suite finalizó con un error.'
    }
} finally {
    Pop-Location
}
