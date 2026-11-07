param(
  [Parameter(Mandatory = $true)][string]$MunicipalityId,
  [Parameter(Mandatory = $true)][string]$MunicipalityName,
  [Parameter(Mandatory = $true)][string]$ProvinceName,
  [string]$ProvinceId = '',
  [string]$VersionName = '1.0.17',
  [int]$BuildNumber = 18
)

$ErrorActionPreference = 'Stop'
if ($MunicipalityId -notmatch '^(georef_)?[A-Za-z0-9_-]{2,120}$') {
  throw 'MunicipalityId inválido.'
}
if ([string]::IsNullOrWhiteSpace($MunicipalityName) -or [string]::IsNullOrWhiteSpace($ProvinceName)) {
  throw 'MunicipalityName y ProvinceName son obligatorios.'
}

$safeName = ($MunicipalityName -replace '[^A-Za-z0-9_-]', '-').Trim('-')
if (-not $safeName) { throw 'MunicipalityName no permite crear un nombre de archivo.' }
$outDir = Join-Path $PSScriptRoot "..\dist\municipalities\$safeName"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$env:ORG_GRADLE_PROJECT_APP_LABEL = "ConDi - $MunicipalityName"
$defines = @(
  "CONDI_MUNICIPALITY_ID=$MunicipalityId",
  "CONDI_MUNICIPALITY_NAME=$MunicipalityName",
  "CONDI_PROVINCE_ID=$ProvinceId",
  "CONDI_PROVINCE_NAME=$ProvinceName"
)
$args = @('build', 'appbundle', '--release', "--build-name=$VersionName", "--build-number=$BuildNumber")
foreach ($define in $defines) { $args += "--dart-define=$define" }
& flutter @args
if ($LASTEXITCODE -ne 0) { throw 'Falló la compilación municipal.' }

$source = Join-Path $PSScriptRoot '..\build\app\outputs\bundle\release\app-release.aab'
$destination = Join-Path $outDir "ConDi-$safeName-$VersionName+$BuildNumber.aab"
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output $destination
