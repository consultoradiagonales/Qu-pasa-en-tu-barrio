# deploy-firebase.ps1 — Despliega Cloud Functions, Firestore rules e índices
# Requiere: firebase login hecho previamente, y firebase_options.dart configurado
# Uso: .\tools\deploy-firebase.ps1

$ErrorActionPreference = "Stop"
$PROJECT = "E:\CODEX ChatGPT\04 - APP municipal → Qué pasa en tu barrio"

Push-Location $PROJECT

Write-Host "==> Login Firebase (si no estás logueado, abre el browser)..." -ForegroundColor Cyan
firebase login --no-localhost

Write-Host "==> Desplegando Firestore rules..." -ForegroundColor Cyan
firebase deploy --only firestore:rules

Write-Host "==> Desplegando Firestore indexes..." -ForegroundColor Cyan
firebase deploy --only firestore:indexes

Write-Host "==> Instalando dependencias de Functions..." -ForegroundColor Cyan
Push-Location functions
npm install
Pop-Location

Write-Host "==> Desplegando Cloud Functions..." -ForegroundColor Cyan
firebase deploy --only functions

Write-Host "==> Deploy completo." -ForegroundColor Green
Pop-Location
