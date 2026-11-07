param([ValidateRange(1,10000)][int]$Reports=20,[switch]$KeepReports)
$ErrorActionPreference='Stop'
$project='project-5fc9024a-e961-42b7-9ee'
$base="https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents"
$options=Get-Content (Join-Path $PSScriptRoot '..\lib\firebase_options.dart') -Raw
$apiKey=[regex]::Match($options,"apiKey: '([^']+)'").Groups[1].Value
$run="saladillo-$(Get-Date -Format yyyyMMdd-HHmmss)"
$email="qa.$([guid]::NewGuid().ToString('N'))@example.com"
$password="Qa!$([guid]::NewGuid().ToString('N'))"
$auth=Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey" -Body (@{email=$email;password=$password;returnSecureToken=$true}|ConvertTo-Json)
$headers=@{Authorization="Bearer $($auth.idToken)"}
$now=(Get-Date).ToUniversalTime().ToString('o')
$profile=@{fields=@{displayName=@{stringValue='Banco de pruebas Saladillo'};realName=@{stringValue='Banco de pruebas Saladillo'};email=@{stringValue=$email};role=@{stringValue='citizen'};municipalityId=@{stringValue='060707'};reportsCount=@{integerValue='0'};disabled=@{booleanValue=$false};createdAt=@{timestampValue=$now}}}
Invoke-RestMethod -Method Patch -ContentType 'application/json' -Headers $headers -Uri "$base/users/$($auth.localId)" -Body ($profile|ConvertTo-Json -Depth 8)|Out-Null
$results=[System.Collections.Generic.List[object]]::new()
$started=Get-Date
$categories=@('infrastructure','lighting','garbage','environment','transport')
foreach($n in 1..$Reports){
 $id="qa-$run-$n"
 $stamp=(Get-Date).ToUniversalTime().ToString('o')
 $fields=@{userId=@{stringValue=$auth.localId};municipalityId=@{stringValue='060707'};title=@{stringValue="[PRUEBA] Saladillo $n / $Reports"};description=@{stringValue="Reporte simulado del banco de pruebas $run. No constituye una incidencia real."};testRunId=@{stringValue=$run};category=@{stringValue=$categories[($n-1)%$categories.Count]};location=@{mapValue=@{fields=@{lat=@{doubleValue=(-35.6384+(($n%20)-10)*0.00015)};lng=@{doubleValue=(-59.7779+(([math]::Floor($n/20)%20)-10)*0.00015)};geohash=@{stringValue='69yg'};address=@{stringValue='Saladillo, Buenos Aires (ubicación simulada)'}}}};status=@{stringValue='pending'};priority=@{integerValue='1'};supportCount=@{integerValue='0'};hidden=@{booleanValue=$false};flaggedCount=@{integerValue='0'};commentsCount=@{integerValue='0'};createdAt=@{timestampValue=$stamp};updatedAt=@{timestampValue=$stamp}}
 foreach($key in @('photosReport','photosBefore','photosProgress','photosAfter')){$fields[$key]=@{arrayValue=@{values=@()}}}
 foreach($key in @('assignedTeamId','assignedWorkerId','assignedAt','workerArrivedAt','workStartedAt','workFinishedAt','workerNotes','resolvedAt','rejectionReason','rating','ratingComment')){$fields[$key]=@{nullValue=$null}}
 $watch=[System.Diagnostics.Stopwatch]::StartNew()
 try {
  Invoke-RestMethod -Method Patch -ContentType 'application/json' -Headers $headers -Uri "$base/reports/$id" -Body (@{fields=$fields}|ConvertTo-Json -Depth 20)|Out-Null
  $doc=Invoke-RestMethod -Headers $headers -Uri "$base/reports/$id"
  if($doc.fields.testRunId.stringValue -ne $run -or $doc.fields.hidden.booleanValue -ne $false){throw 'Verificación de lectura incorrecta'}
  $results.Add(@{id=$id;success=$true;readVerified=$true;milliseconds=$watch.ElapsedMilliseconds})
 }catch{$results.Add(@{id=$id;success=$false;error=$_.Exception.Message;milliseconds=$watch.ElapsedMilliseconds})}
 if($n%100 -eq 0){Write-Output "Procesados $n / $Reports"}
}
$successful=@($results|Where-Object {$_.success}).Count
if(-not $KeepReports){
 $admin=@{Authorization="Bearer $((gcloud auth print-access-token).Trim())"}
 foreach($r in $results){if($r.success){Invoke-RestMethod -Method Delete -Headers $admin -Uri "$base/reports/$($r.id)"|Out-Null}}
}
$manifest=@{runId=$run;startedAt=$started.ToUniversalTime().ToString('o');finishedAt=(Get-Date).ToUniversalTime().ToString('o');requested=$Reports;successful=$successful;failed=($Reports-$successful);retained=[bool]$KeepReports;municipalityId='060707';scope='1000 operaciones de escritura y lectura autenticadas bajo Firestore Rules; no son 1000 recorridos UI Android';results=$results}
$path=Join-Path $PSScriptRoot "..\store_assets\PRUEBAS_$run.json"
$manifest|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding UTF8
Write-Output "Resultado: $successful / $Reports. Manifest: $path"
if($successful -ne $Reports){throw 'Hay pruebas fallidas; consultar manifest'}
