param(
    [Parameter(Mandatory = $true)][int]$VersionCode,
    [Parameter(Mandatory = $true)][string]$VersionName,
    [Parameter(Mandatory = $true)][string]$Bundle,
    [string]$ReleaseNotes = 'Mejoras de estabilidad y experiencia de uso.'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$bundlePath = if ([System.IO.Path]::IsPathRooted($Bundle)) {
    $Bundle
} else {
    Join-Path $project $Bundle
}
if (-not (Test-Path -LiteralPath $bundlePath)) {
    throw "No existe el paquete: $bundlePath"
}

$env:CLOUDSDK_CONFIG = Join-Path $PSScriptRoot 'private\google-auth'
$gcloud = Join-Path $PSScriptRoot 'google-cloud-sdk\bin\gcloud.cmd'
$package = 'ar.com.consultoradiagonales.condi'
$base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$package"
$expectedHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
$token = (& $gcloud auth application-default print-access-token).Trim()
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Falta autorización de Google.' }
$headers = @{ Authorization = "Bearer $token"; 'X-Goog-User-Project' = 'condi-maps-2026' }

$edit = Invoke-RestMethod -Method Post -Uri "$base/edits" -Headers $headers -ContentType 'application/json' -Body '{}'
$uploaded = Invoke-RestMethod -Method Post -Uri "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$package/edits/$($edit.id)/bundles?uploadType=media" -Headers $headers -ContentType 'application/octet-stream' -InFile $bundlePath -TimeoutSec 900
if ([int]$uploaded.versionCode -ne $VersionCode) {
    throw "Código inesperado: $($uploaded.versionCode)"
}

$release = @{
    track = 'internal'
    releases = @(@{
        name = "ConDi beta interna $VersionName"
        versionCodes = @("$VersionCode")
        status = 'completed'
        releaseNotes = @(@{
            language = 'es-419'
            text = $ReleaseNotes
        })
    })
} | ConvertTo-Json -Depth 8
Invoke-RestMethod -Method Put -Uri "$base/edits/$($edit.id)/tracks/internal" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $release | Out-Null
$commit = Invoke-RestMethod -Method Post -Uri "$base/edits/$($edit.id):commit" -Headers $headers -ContentType 'application/json' -Body '{}'

$verifyEdit = Invoke-RestMethod -Method Post -Uri "$base/edits" -Headers $headers -ContentType 'application/json' -Body '{}'
$track = Invoke-RestMethod -Uri "$base/edits/$($verifyEdit.id)/tracks/internal" -Headers $headers
if (-not ($track.releases | Where-Object {
    $_.status -eq 'completed' -and $_.versionCodes -contains "$VersionCode"
})) {
    throw 'No se confirmó la versión en el segmento interno.'
}

$result = @{
    versionCode = $VersionCode
    versionName = $VersionName
    sha256 = $expectedHash
    editId = $commit.id
    track = 'internal'
    link = 'https://play.google.com/apps/internaltest/4701647237677047143'
    bundle = $bundlePath
}
$resultPath = Join-Path $project "store_assets\PLAY_RELEASE_$VersionName.json"
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Output ($result | ConvertTo-Json -Compress)
