# build-web.ps1 — Compila Flutter Web y sube a GitHub Pages (rama gh-pages)
# Uso: .\tools\build-web.ps1

$ErrorActionPreference = "Stop"
$PROJECT = "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"
$FLUTTER = "C:\flutter\bin\flutter.bat"

Push-Location $PROJECT

Write-Host "==> Compilando Flutter Web..." -ForegroundColor Cyan
& $FLUTTER build web --release --base-href "/Qu-pasa-en-tu-barrio/"

Write-Host "==> Subiendo a gh-pages..." -ForegroundColor Cyan
# Guarda el estado actual
$branch = git rev-parse --abbrev-ref HEAD

# Copia el output compilado
$tmpDir = "$env:TEMP\flutter_web_build"
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
Copy-Item "build\web" $tmpDir -Recurse

# Cambia a gh-pages
git checkout gh-pages
# Limpia los archivos anteriores de Flutter web (conserva los de la maqueta si existen)
Get-ChildItem -File | Where-Object { $_.Name -notlike "maqueta*" } | Remove-Item -Force
Get-ChildItem -Directory | Where-Object { $_.Name -notin @("maqueta","assets") } | Remove-Item -Recurse -Force

# Copia los nuevos archivos
Copy-Item "$tmpDir\*" "." -Recurse -Force
Remove-Item $tmpDir -Recurse -Force

git add .
git commit -m "deploy: Flutter Web build $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
git push origin gh-pages

# Vuelve a la rama original
git checkout $branch

Pop-Location
Write-Host "==> Deploy completado en https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/" -ForegroundColor Green
