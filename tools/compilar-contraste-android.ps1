$ErrorActionPreference = 'Stop'
$releaseRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath 'R:\') { throw 'La unidad temporal R está ocupada.' }
& "$env:SystemRoot/System32/subst.exe" R: $releaseRoot
if ($LASTEXITCODE -ne 0) { throw 'No se pudo preparar la ruta ASCII.' }
try {
    # Copia temporal dentro del mismo espacio de trabajo: evita tanto Unicode
    # en Java como el fallo de Gradle cuando el proyecto es la raíz R:/.
    $buildRoot = 'R:/dev/build-contraste-android'
    New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
    foreach ($releaseFolder in @('lib', 'assets', 'android')) {
        & robocopy (Join-Path $releaseRoot $releaseFolder) "$buildRoot/$releaseFolder" /E /XD .gradle .cxx build /XF local.properties /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) { throw "Falló la copia temporal de $releaseFolder." }
    }
    foreach ($releaseFile in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')) {
        Copy-Item -LiteralPath (Join-Path $releaseRoot $releaseFile) -Destination "$buildRoot/$releaseFile" -Force
    }
    $env:FLUTTER_ROOT = 'R:/dev/flutter'
    $env:JAVA_HOME = 'R:/dev/jdk17'
    $env:GRADLE_USER_HOME = 'R:/gradle'
    $env:PUB_CACHE = 'R:/pub-cache'
    $env:ANDROID_HOME = 'E:/CodexTools/android-sdk'
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $env:ANDROID_USER_HOME = 'R:/dev/android-user'
    $env:TEMP = 'R:/dev/temp'
    $env:TMP = $env:TEMP
    $previousFlutterConfig = (& "$env:FLUTTER_ROOT/bin/flutter.bat" --no-version-check config --machine | ConvertFrom-Json)
    $previousJdk = $previousFlutterConfig.'jdk-dir'
    & "$env:FLUTTER_ROOT/bin/flutter.bat" --no-version-check config --jdk-dir 'R:/dev/jdk17' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo seleccionar Java en la ruta ASCII.' }
    Push-Location $buildRoot
    try {
        & "$env:FLUTTER_ROOT/bin/flutter.bat" --no-version-check pub get --offline
        if ($LASTEXITCODE -ne 0) { throw 'No se pudieron preparar las dependencias locales.' }
        & "$env:FLUTTER_ROOT/bin/flutter.bat" --no-version-check -v build appbundle --release --build-name 1.0.24 --build-number 25
        if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación Android.' }
        Copy-Item -LiteralPath 'build/app/outputs/bundle/release/app-release.aab' -Destination (Join-Path $releaseRoot 'dist/ConDi-1.0.24+25-contraste.aab') -Force
    } finally { Pop-Location }
} finally {
    if ($null -ne $previousJdk) {
        & "$env:FLUTTER_ROOT/bin/flutter.bat" --no-version-check config "--jdk-dir=$previousJdk" | Out-Null
    }
    & "$env:SystemRoot/System32/subst.exe" R: /D
}
