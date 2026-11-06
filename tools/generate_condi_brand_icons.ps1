$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$logoPath = Join-Path $root 'Logo ConDi®.png'
if (-not (Test-Path -LiteralPath $logoPath)) { throw "No se encontró el logo: $logoPath" }

$source = [System.Drawing.Bitmap]::new($logoPath)
try {
    # Use the uniform field behind the mark, not the darker top-left vignette.
    $background = $source.GetPixel(
        [int][Math]::Round($source.Width * 0.52),
        [int][Math]::Round($source.Height * 0.08))
    $backgroundHex = '#{0:X2}{1:X2}{2:X2}' -f $background.R, $background.G, $background.B
    # El recorte conserva el símbolo geoterritorial del logo y omite el texto,
    # que ya aparece como nombre ConDi debajo del icono del teléfono.
    $crop = [System.Drawing.Rectangle]::new(
        [int][Math]::Round($source.Width * 0.28),
        [int][Math]::Round($source.Height * 0.04),
        [int][Math]::Round($source.Width * 0.44),
        [int][Math]::Round($source.Height * 0.49))

    function New-ConDiIcon([int]$Size, [double]$ContentScale, [string]$Path) {
        $canvas = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($canvas)
            try {
                $graphics.Clear($background)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $maxSide = $Size * $ContentScale
                $scale = [Math]::Min($maxSide / $crop.Width, $maxSide / $crop.Height)
                $drawWidth = [int][Math]::Round($crop.Width * $scale)
                $drawHeight = [int][Math]::Round($crop.Height * $scale)
                $target = [System.Drawing.Rectangle]::new(
                    [int][Math]::Floor(($Size - $drawWidth) / 2),
                    [int][Math]::Floor(($Size - $drawHeight) / 2),
                    $drawWidth, $drawHeight)
                $graphics.DrawImage($source, $target, $crop, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $graphics.Dispose() }
            $canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $canvas.Dispose() }
    }

    $fullLogo = Join-Path $root 'assets\images\condi_logo.png'
    $source.Save($fullLogo, [System.Drawing.Imaging.ImageFormat]::Png)

    $storeIcon = Join-Path $root 'store_assets\icon_512.png'
    New-ConDiIcon 512 0.82 $storeIcon

    $feature = [System.Drawing.Bitmap]::new(1024, 500, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $g = [System.Drawing.Graphics]::FromImage($feature)
        try {
            $g.Clear($background)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $fullMarkCrop = [System.Drawing.Rectangle]::new(420, 90, 700, 710)
            $markW = 420
            $markH = [int][Math]::Round($markW * $fullMarkCrop.Height / $fullMarkCrop.Width)
            $markBox = [System.Drawing.Rectangle]::new(35, [int](($feature.Height - $markH) / 2), $markW, $markH)
            $g.DrawImage($source, $markBox, $fullMarkCrop, [System.Drawing.GraphicsUnit]::Pixel)

            $navy = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 18, 48, 87))
            $green = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 31, 139, 89))
            $titleFont = [System.Drawing.Font]::new('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)
            $bodyFont = [System.Drawing.Font]::new('Segoe UI', 18, [System.Drawing.FontStyle]::Regular)
            $brandFont = [System.Drawing.Font]::new('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
            try {
                $g.DrawString("Reportá lo que pasa`nen tu barrio", $titleFont, $navy,
                    [System.Drawing.RectangleF]::new(500, 115, 490, 110))
                $g.FillRectangle($green, 500, 245, 115, 5)
                $g.DrawString('Ubicación, seguimiento y respuesta en un mismo lugar.', $bodyFont, $navy,
                    [System.Drawing.RectangleF]::new(500, 275, 475, 95))
                $g.DrawString('ConDi® · inteligencia territorial', $brandFont, $green,
                    [System.Drawing.RectangleF]::new(500, 397, 480, 35))
            } finally {
                $navy.Dispose(); $green.Dispose()
                $titleFont.Dispose(); $bodyFont.Dispose(); $brandFont.Dispose()
            }
        } finally { $g.Dispose() }
        $feature.Save((Join-Path $root 'store_assets\feature_graphic_1024x500.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $feature.Dispose() }

    $androidRes = Join-Path $root 'android\app\src\main\res'
    foreach ($entry in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
        $dir = Join-Path $androidRes "mipmap-$($entry[0])"
        New-ConDiIcon $entry[1] 0.82 (Join-Path $dir 'ic_launcher.png')
    }
    foreach ($entry in @(@('mdpi',108),@('hdpi',162),@('xhdpi',216),@('xxhdpi',324),@('xxxhdpi',432))) {
        $dir = Join-Path $androidRes "mipmap-$($entry[0])"
        New-ConDiIcon $entry[1] 0.62 (Join-Path $dir 'ic_launcher_foreground.png')
    }
    New-ConDiIcon 512 0.82 (Join-Path $androidRes 'drawable\ic_launcher.png')
    @"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$backgroundHex</color>
</resources>
"@ | Set-Content -LiteralPath (Join-Path $androidRes 'values\ic_launcher_background.xml') -Encoding utf8

    $iosIconDir = Join-Path $root 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
    $contentsPath = Join-Path $iosIconDir 'Contents.json'
    $contents = Get-Content -Raw -LiteralPath $contentsPath | ConvertFrom-Json
    foreach ($item in $contents.images) {
        if (-not $item.filename) { continue }
        $points = [double]($item.size -split 'x')[0]
        $scale = [double]($item.scale -replace 'x','')
        $pixels = [int][Math]::Round($points * $scale)
        New-ConDiIcon $pixels 0.82 (Join-Path $iosIconDir $item.filename)
    }

    $webDir = Join-Path $root 'web'
    if (Test-Path -LiteralPath $webDir) {
        New-ConDiIcon 192 0.78 (Join-Path $webDir 'icons\Icon-192.png')
        New-ConDiIcon 512 0.78 (Join-Path $webDir 'icons\Icon-512.png')
        New-ConDiIcon 192 0.68 (Join-Path $webDir 'icons\Icon-maskable-192.png')
        New-ConDiIcon 512 0.68 (Join-Path $webDir 'icons\Icon-maskable-512.png')
        New-ConDiIcon 64 0.78 (Join-Path $webDir 'favicon.png')
    }
    [pscustomobject]@{ Background=$backgroundHex; Crop=$crop; StoreIcon=$storeIcon; FeatureGraphic='store_assets\feature_graphic_1024x500.png'; Logo=$fullLogo }
} finally { $source.Dispose() }
