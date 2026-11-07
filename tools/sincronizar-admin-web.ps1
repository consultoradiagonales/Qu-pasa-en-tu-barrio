param(
    [string]$Proyecto = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$origen = Join-Path $Proyecto 'web\admin'
$destino = Join-Path $Proyecto 'build\web\admin'

if (-not (Test-Path -LiteralPath $origen)) {
    throw "No se encontró el panel web en $origen"
}

New-Item -ItemType Directory -Path $destino -Force | Out-Null
Copy-Item -Path (Join-Path $origen '*') -Destination $destino -Recurse -Force
