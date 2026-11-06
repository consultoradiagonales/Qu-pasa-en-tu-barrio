[CmdletBinding()]
param([switch]$Instalar)

$ErrorActionPreference = 'Stop'
$shortcutProjectRoot = Split-Path -Parent $PSScriptRoot
$shortcutOutput = Join-Path $shortcutProjectRoot 'output\publicacion-2026-10-30'
$shortcutName = 'ConDi - Gestión Municipal.lnk'
$shortcutPrepared = Join-Path $shortcutOutput $shortcutName
$shortcutDesktop = Join-Path ([Environment]::GetFolderPath('Desktop')) $shortcutName
$shortcutBrowser = 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
$shortcutPanelUrl = 'https://project-5fc9024a-e961-42b7-9ee.web.app/admin/'
if (-not (Test-Path -LiteralPath $shortcutBrowser)) { throw 'No se encontró el navegador del acceso directo.' }
New-Item -ItemType Directory -Path $shortcutOutput -Force | Out-Null
if (-not ('ConDiShortcutPath' -as [type])) {
    Add-Type -TypeDefinition 'using System.Text; using System.Runtime.InteropServices; public class ConDiShortcutPath { [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern uint GetShortPathName(string path, StringBuilder result, uint size); }'
}
$shortcutShortOutput = New-Object System.Text.StringBuilder 4096
[void][ConDiShortcutPath]::GetShortPathName($shortcutOutput, $shortcutShortOutput, 4096)
if (-not $shortcutShortOutput.Length) { throw 'No se pudo resolver la ruta del acceso directo.' }
$shortcutComPath = Join-Path $shortcutShortOutput.ToString() $shortcutName
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcut = $shortcutShell.CreateShortcut($shortcutComPath)
$shortcut.TargetPath = $shortcutBrowser
$shortcut.Arguments = "--app=$shortcutPanelUrl"
$shortcut.WorkingDirectory = Split-Path -Parent $shortcutBrowser
$shortcut.IconLocation = (Join-Path $shortcutProjectRoot 'web\icons\ConDi-Admin.ico') + ',0'
$shortcut.Description = 'ConDi · Panel de gestión municipal publicado'
$shortcut.Save()
$shortcutCheck = $shortcutShell.CreateShortcut($shortcutComPath)
if ($shortcutCheck.Arguments -ne "--app=$shortcutPanelUrl") { throw 'No se pudo verificar el acceso preparado.' }
if ($Instalar) {
    if (Test-Path -LiteralPath $shortcutDesktop) {
        $shortcutBackup = Join-Path $shortcutOutput 'ConDi - Gestión Municipal.anterior.lnk'
        if (-not (Test-Path -LiteralPath $shortcutBackup)) {
            Copy-Item -LiteralPath $shortcutDesktop -Destination $shortcutBackup
        }
    }
    Copy-Item -LiteralPath $shortcutPrepared -Destination $shortcutDesktop -Force
    $shortcutInstalled = $shortcutShell.CreateShortcut($shortcutDesktop)
    if ($shortcutInstalled.TargetPath -ne $shortcutBrowser -or $shortcutInstalled.Arguments -ne "--app=$shortcutPanelUrl") {
        throw 'No se pudo verificar el acceso instalado en el escritorio.'
    }
}
@{ prepared = $shortcutPrepared; installed = [bool]$Instalar; desktop = $shortcutDesktop; url = $shortcutPanelUrl } | ConvertTo-Json -Compress
