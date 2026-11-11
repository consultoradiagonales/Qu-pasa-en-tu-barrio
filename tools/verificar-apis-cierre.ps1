param([string]$Output = 'dist\ConDi-Cierre-1.0.26+27\Producto\VALIDACION_APIS.json')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$targets = @(
    @{ name = 'Web ConDi'; url = 'https://project-5fc9024a-e961-42b7-9ee.web.app/' },
    @{ name = 'Central de monitoreo'; url = 'https://project-5fc9024a-e961-42b7-9ee.web.app/admin/' },
    @{ name = 'GeoRef municipios'; url = 'https://apis.datos.gob.ar/georef/api/municipios?nombre=La%20Plata&max=1' },
    @{ name = 'Open-Meteo 48 horas'; url = 'https://api.open-meteo.com/v1/forecast?latitude=-34.92&longitude=-57.95&hourly=precipitation_probability&forecast_days=3' },
    @{ name = 'MET Norway'; url = 'https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=-34.92&lon=-57.95' },
    @{ name = 'SMN CAP'; url = 'https://ssl.smn.gob.ar/CAP/AR.php' },
    @{ name = 'ARGWX'; url = 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/' },
    @{ name = 'Alertas PBA'; url = 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/data/alertas_pba.json' },
    @{ name = 'Crecidas'; url = 'https://consultoradiagonales.github.io/Qu-pasa-en-tu-barrio/argwx/data/crecidas.json' },
    @{ name = 'Google Play público'; url = 'https://play.google.com/store/apps/details?id=ar.com.consultoradiagonales.condi'; optional = $true },
    @{ name = 'Google Play prueba interna'; url = 'https://play.google.com/apps/internaltest/4701647237677047143' }
)

$results = foreach ($target in $targets) {
    $started = Get-Date
    try {
        if ($target.name -eq 'MET Norway') {
            $response = Invoke-WebRequest -Uri $target.url -UserAgent 'ConDi/1.0 (consultoradiagonales.com.ar)' -UseBasicParsing -TimeoutSec 30
        } else {
            $response = Invoke-WebRequest -Uri $target.url -UseBasicParsing -TimeoutSec 30
        }
        [ordered]@{ name=$target.name; url=$target.url; required=(-not [bool]$target.optional); ok=$true; status=[int]$response.StatusCode; elapsedMs=[int]((Get-Date)-$started).TotalMilliseconds }
    } catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        [ordered]@{ name=$target.name; url=$target.url; required=(-not [bool]$target.optional); ok=$false; status=$status; elapsedMs=[int]((Get-Date)-$started).TotalMilliseconds; error=$_.Exception.Message }
    }
}

$document = [ordered]@{
    generatedAt=(Get-Date).ToUniversalTime().ToString('o')
    corePassed=(@($results | Where-Object { $_.required -and -not $_.ok }).Count -eq 0)
    publicPlayAvailable=(@($results | Where-Object { $_.name -eq 'Google Play público' -and $_.ok }).Count -eq 1)
    results=$results
    note='Las funciones autenticadas se validan mediante pruebas automatizadas del backend; no se invocan sin credenciales.'
}
$absolute = Join-Path $root $Output
$parent = Split-Path -Parent $absolute
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $absolute -Encoding utf8
$document | ConvertTo-Json -Depth 6
