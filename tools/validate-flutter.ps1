param([switch]$Full, [switch]$AnalyzeChanged, [switch]$SkipTests)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
$project = $env:CONDI_PROJECT
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
$drive = @('Q:', 'R:', 'S:', 'T:') |
    Where-Object { -not (Test-Path -LiteralPath "$($_)\") } |
    Select-Object -First 1
if (-not $drive) { throw 'No hay una letra de unidad temporal disponible.' }

$mappedByScript = $false
try {
    & "$env:SystemRoot\System32\subst.exe" $drive $project
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear la unidad temporal.' }
    $mappedByScript = $true
    $env:JAVA_HOME = "$drive\dev\jdk17"
    $env:GRADLE_USER_HOME = "$drive\gradle"
    $env:PUB_CACHE = "$drive\pub-cache"
    $env:ANDROID_USER_HOME = "$drive\dev\android-user"
    $env:TEMP = "$drive\dev\temp"
    $env:TMP = $env:TEMP
    Push-Location "$drive\"
    try {
        & $flutter pub get
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if (-not $SkipTests) {
            if ($Full) {
                & $flutter test --no-pub
            } else {
                & $flutter test --no-pub test\report_model_test.dart test\citizen_photo_flow_test.dart test\municipality_profile_access_test.dart
            }
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        if ($AnalyzeChanged) {
            & $flutter analyze --no-pub lib\data\services\georef_service.dart lib\data\models\report_model.dart lib\features\report\report_flow.dart lib\features\report\screens\new_report_screen.dart
        } else {
            & $flutter analyze --no-pub
        }
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    if ($mappedByScript) {
        & "$env:SystemRoot\System32\subst.exe" $drive /D | Out-Null
    }
}
