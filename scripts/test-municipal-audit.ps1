$ErrorActionPreference = 'Stop'
$auditProjectRoot = Split-Path -Parent $PSScriptRoot
$auditRuntime = Join-Path ([System.IO.Path]::GetTempPath()) 'condi-audit-emulators'
# Java en Windows puede interpretar mal los caracteres de la ruta del proyecto.
# El espejo temporal contiene únicamente reglas, configuración y el JAR local.
if ($auditRuntime -match '[^\x00-\x7F]') { throw 'TEMP debe apuntar a una ruta ASCII para el emulador Java.' }
New-Item -ItemType Directory -Path $auditRuntime -Force | Out-Null
foreach ($auditFile in @('firebase.audit.json', 'firestore.rules', 'firestore.indexes.json')) {
    Copy-Item -LiteralPath (Join-Path $auditProjectRoot $auditFile) -Destination $auditRuntime -Force
}
$auditJar = 'cloud-firestore-emulator-v1.22.0.jar'
$auditJarSource = Join-Path $auditProjectRoot "dev\firebase-cache\emulators\$auditJar"
if (-not (Test-Path -LiteralPath (Join-Path $auditRuntime $auditJar)) -and (Test-Path -LiteralPath $auditJarSource)) {
    Copy-Item -LiteralPath $auditJarSource -Destination $auditRuntime
}
$auditTestPath = Join-Path $auditProjectRoot 'functions\municipal-security.emulator.test.js'
$auditRunner = Join-Path $auditRuntime 'run-municipal-tests.cjs'
Set-Content -LiteralPath $auditRunner -Value ('require(' + (ConvertTo-Json $auditTestPath -Compress) + ');') -Encoding utf8
$auditPreviousConfig = $env:XDG_CONFIG_HOME
$auditPreviousCache = $env:FIREBASE_EMULATORS_PATH
try {
    $env:XDG_CONFIG_HOME = Join-Path $auditRuntime 'config'
    $env:FIREBASE_EMULATORS_PATH = $auditRuntime
    $auditCli = Join-Path $auditProjectRoot 'tools\firebase-cli\node_modules\firebase-tools\lib\bin\firebase.js'
    & node $auditCli emulators:exec --config (Join-Path $auditRuntime 'firebase.audit.json') --project demo-condi-audit --only auth,firestore "node --test `"$auditRunner`""
    if ($LASTEXITCODE -ne 0) { throw 'Falló la verificación municipal en emuladores.' }
} finally {
    $env:XDG_CONFIG_HOME = $auditPreviousConfig
    $env:FIREBASE_EMULATORS_PATH = $auditPreviousCache
}
