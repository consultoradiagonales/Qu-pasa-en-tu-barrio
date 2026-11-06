$ErrorActionPreference = 'Stop'
$publishRoot = Split-Path -Parent $PSScriptRoot
$publishCli = Join-Path $publishRoot 'tools\firebase-cli\node_modules\firebase-tools\lib\bin\firebase.js'
$publishProject = 'project-5fc9024a-e961-42b7-9ee'
$env:GOOGLE_APPLICATION_CREDENTIALS = Join-Path $publishRoot 'tools\private\google-auth\application_default_credentials.json'
$env:XDG_CONFIG_HOME = Join-Path $publishRoot 'dev\qa\firebase-publish-config'
Push-Location $publishRoot
try {
    foreach ($publishFile in @('build/web/main.dart.js', 'build/web/index.html', 'build/web/version.json')) {
        if (-not (Test-Path -LiteralPath $publishFile)) { throw "Falta el artefacto de publicación: $publishFile" }
    }
    $publishVersion = Get-Content -Raw 'build/web/version.json' | ConvertFrom-Json
    if ($publishVersion.version -ne '1.0.22' -or $publishVersion.build_number -ne '23') { throw 'La compilación web no es la versión de validación esperada.' }
    & (Join-Path $PSScriptRoot 'sincronizar-admin-web.ps1') -Proyecto $publishRoot
    & node (Join-Path $PSScriptRoot 'preparar-publicacion-web.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la transición de publicación.' }
    & node $publishCli deploy --project $publishProject --only 'firestore:rules,firestore:indexes,functions:assignReportTeam,functions:generateMunicipalityReport' --non-interactive
    if ($LASTEXITCODE -ne 0) { throw 'No se publicó la web porque falló el despliegue previo del backend.' }
    & node $publishCli deploy --project $publishProject --only hosting --non-interactive
    if ($LASTEXITCODE -ne 0) { throw 'Falló la publicación de Firebase Hosting.' }
    & node (Join-Path $PSScriptRoot 'preparar-publicacion-web.cjs') --verificar
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo verificar la versión de reglas publicada.' }
    Write-Output 'ConDi: https://project-5fc9024a-e961-42b7-9ee.web.app/'
    Write-Output 'Gestión: https://project-5fc9024a-e961-42b7-9ee.web.app/admin/'
} finally {
    Pop-Location
}
