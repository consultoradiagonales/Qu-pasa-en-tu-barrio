param(
  [int]$Repetitions = 20,
  [string]$Serial = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$adb = 'E:\CodexTools\android-sdk\platform-tools\adb.exe'
$apk = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-release.apk'
$packageName = 'ar.com.consultoradiagonales.condi'

if (-not (Test-Path $apk)) { throw "No existe el APK: $apk" }
& $adb -s $Serial install -r $apk | Out-Null
& $adb -s $Serial logcat -c

foreach ($n in 1..$Repetitions) {
  & $adb -s $Serial shell am force-stop $packageName
  & $adb -s $Serial shell monkey -p $packageName 1 | Out-Null
  Start-Sleep -Milliseconds 1100
  $appProcessId = (& $adb -s $Serial shell pidof $packageName).Trim()
  if (-not $appProcessId) {
    throw "La aplicación no quedó ejecutándose en el arranque $n."
  }
}

$crashes = & $adb -s $Serial logcat -d -v brief |
  Select-String -Pattern 'FATAL EXCEPTION|Fatal signal'
if ($crashes) { throw "Se detectó un crash Android: $($crashes[0].Line)" }

Write-Output "OK: $Repetitions arranques sin crash."
