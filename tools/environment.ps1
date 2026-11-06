# Entorno de desarrollo ConDi. Cargar con: . .\tools\environment.ps1
$environmentScript = $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $environmentScript
$projectRoot = Split-Path -Parent $toolsRoot
$env:CONDI_PROJECT=$projectRoot
$env:FLUTTER_ROOT='E:\CodexTools\flutter'
$env:JAVA_HOME=Join-Path $projectRoot 'dev\jdk17'
$env:GRADLE_USER_HOME=Join-Path $projectRoot 'gradle'
$env:PUB_CACHE=Join-Path $projectRoot 'pub-cache'
$env:ANDROID_HOME='E:\CodexTools\android-sdk'
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:ANDROID_USER_HOME=Join-Path $projectRoot 'dev\android-user'
$env:ANDROID_AVD_HOME='E:\CodexTools\android-avd'
$env:NPM_CONFIG_CACHE=Join-Path $projectRoot 'dev\npm-cache'
$env:TEMP=Join-Path $projectRoot 'dev\temp'
$env:TMP=$env:TEMP
foreach($directory in @($env:TEMP,$env:GRADLE_USER_HOME,$env:PUB_CACHE,$env:NPM_CONFIG_CACHE)) {
    if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force | Out-Null}
}
$prefix=@("$env:JAVA_HOME\bin","$env:FLUTTER_ROOT\bin","$env:PUB_CACHE\bin","$env:ANDROID_HOME\platform-tools")
$remaining=@($env:PATH -split ';' | Where-Object {$_ -and $_ -notin $prefix -and $_ -notin @('C:\flutter\bin','C:\jdk17\bin')})
$env:PATH=($prefix+$remaining) -join ';'
