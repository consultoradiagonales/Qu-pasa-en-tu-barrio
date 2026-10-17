# Compila y publica la web desde una copia Git aislada; conserva el proyecto y sus SDK.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'environment.ps1')
$project='E:\condi'
$flutter=Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
$deployment=$null
$completed=$false
Push-Location $project
try {
    & $flutter build web --release --base-href '/Qu-pasa-en-tu-barrio/' --no-tree-shake-icons
    if($LASTEXITCODE -ne 0){throw 'Falló la compilación web; no se publica'}
    $base=Join-Path $project 'dev\deploy-worktrees'
    New-Item -ItemType Directory -Force -Path $base | Out-Null
    $deployment=Join-Path $base ([guid]::NewGuid().ToString('N'))
    $resolvedBase=[IO.Path]::GetFullPath($base).TrimEnd('\')+'\'
    $resolvedDeployment=[IO.Path]::GetFullPath($deployment)
    if(-not $resolvedDeployment.StartsWith($resolvedBase,[StringComparison]::OrdinalIgnoreCase)){throw 'Destino de publicación fuera de alcance'}
    & git worktree add --detach $deployment gh-pages
    if($LASTEXITCODE -ne 0){throw 'No se pudo crear la copia aislada de gh-pages'}
    foreach($item in Get-ChildItem -LiteralPath $deployment -Force){
        if($item.Name -eq '.git' -or $item.Name -like 'maqueta*' -or $item.Name -eq 'assets'){continue}
        $absolute=[IO.Path]::GetFullPath($item.FullName)
        if(-not $absolute.StartsWith($resolvedDeployment+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Archivo fuera de la copia de publicación'}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'La copia de publicación contiene enlaces que requieren revisión'}
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
    foreach($item in Get-ChildItem -LiteralPath (Join-Path $project 'build\web') -Force){
        Copy-Item -LiteralPath $item.FullName -Destination $deployment -Recurse -Force
    }
    & git -C $deployment add -A
    if($LASTEXITCODE -ne 0){throw 'No se pudo preparar la publicación'}
    & git -C $deployment diff --cached --quiet
    if($LASTEXITCODE -eq 1){
        & git -C $deployment commit -m ('deploy: Flutter Web build '+(Get-Date -Format 'yyyy-MM-dd HH:mm'))
        if($LASTEXITCODE -ne 0){throw 'No se pudo crear el commit de publicación'}
        & git -C $deployment push origin HEAD:gh-pages
        if($LASTEXITCODE -ne 0){throw "Falló la publicación; se conserva la copia en $deployment"}
    }elseif($LASTEXITCODE -ne 0){throw 'No se pudo comprobar el contenido de la publicación'}
    $completed=$true
    Write-Host 'Web compilada y publicación completada.'
} finally {
    Pop-Location
    if($completed -and $deployment){
        & git -C $project worktree remove $deployment
        if($LASTEXITCODE -ne 0){Write-Warning "La copia de publicación se conserva en $deployment"}
    }
}
