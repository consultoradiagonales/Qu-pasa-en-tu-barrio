$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$product = Join-Path $root 'dist\ConDi-Cierre-1.0.26+27\Producto'
$commercial = Join-Path $root 'dist\ConDi-Paquete-Comercial-2026-11-10'
$productZip = Join-Path $root 'dist\ConDi-Cierre-Tecnico-1.0.26+27.zip'
$commercialZip = Join-Path $root 'dist\ConDi-Paquete-Comercial-2026-11-10.zip'

Copy-Item -LiteralPath (Join-Path $root 'dist\qa_manual\Manual_de_Uso_ConDi_1.0.26.pdf') -Destination (Join-Path $product 'Manual_de_Uso_ConDi_1.0.26.pdf') -Force
Copy-Item -LiteralPath (Join-Path $root 'output\clima-2026-11-06\publicacion-android.json') -Destination (Join-Path $product 'PUBLICACION_GOOGLE_PLAY_INTERNA.json') -Force

$hashes = Get-ChildItem -LiteralPath $product -File |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
[System.IO.File]::WriteAllLines((Join-Path $product 'SHA256SUMS.txt'), $hashes, [System.Text.UTF8Encoding]::new($false))

Compress-Archive -LiteralPath $product -DestinationPath $productZip -CompressionLevel Optimal -Force
Compress-Archive -LiteralPath $commercial -DestinationPath $commercialZip -CompressionLevel Optimal -Force

Get-Item $productZip, $commercialZip | Select-Object FullName, Length, LastWriteTime
