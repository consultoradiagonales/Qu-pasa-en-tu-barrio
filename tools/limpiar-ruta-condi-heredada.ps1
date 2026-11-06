param(
    [int]$TimeoutSeconds = 7200
)

$ErrorActionPreference = 'SilentlyContinue'
$legacy = 'E:\condi'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    $excelOpen = Get-Process -Name EXCEL -ErrorAction SilentlyContinue
    if (-not $excelOpen -and (Test-Path -LiteralPath $legacy)) {
        $item = Get-Item -LiteralPath $legacy -Force
        $contents = @(Get-ChildItem -LiteralPath $legacy -Recurse -Force)
        $unexpected = @($contents | Where-Object {
            $_.FullName -ne 'E:\condi\dev' -and $_.FullName -notlike 'E:\condi\dev\temp*'
        })

        if (-not $item.LinkType -and $unexpected.Count -eq 0) {
            Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $legacy)) { exit 0 }
        }
    }

    Start-Sleep -Seconds 5
}

exit 1
