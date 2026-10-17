$ErrorActionPreference='Stop'
$project='project-5fc9024a-e961-42b7-9ee'
$base="https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents"
$key=[regex]::Match((Get-Content (Join-Path $PSScriptRoot '..\lib\firebase_options.dart') -Raw),"apiKey: '([^']+)'").Groups[1].Value
$owner=@{Authorization="Bearer $((gcloud auth print-access-token).Trim())"}
$users=@(); $checks=[System.Collections.Generic.List[object]]::new(); $id="qa-ad-$([guid]::NewGuid().ToString('N'))"
function Check($name,$action,$denied=$false) {
 try { & $action | Out-Null; if($denied){throw 'La operación debió ser rechazada'}; $checks.Add(@{test=$name;passed=$true}) }
 catch { if($denied -and $_.Exception.Response.StatusCode.value__ -eq 403){$checks.Add(@{test=$name;passed=$true})}else{$checks.Add(@{test=$name;passed=$false;error=$_.Exception.Message})} }
}
try {
 foreach($role in @('admin','citizen','other')){
  $a=Invoke-RestMethod -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$key" -ContentType 'application/json' -Body (@{email="adsqa.$([guid]::NewGuid().ToString('N'))@example.com";password="Qa!$([guid]::NewGuid().ToString('N'))";returnSecureToken=$true}|ConvertTo-Json)
  $users+= $a
  $municipality=if($role -eq 'other'){'060441'}else{'060707'}
  $profileRole=if($role -eq 'admin'){'admin'}else{'citizen'}
  Invoke-RestMethod -Method Patch -Uri "$base/users/$($a.localId)" -Headers $owner -ContentType 'application/json' -Body (@{fields=@{role=@{stringValue=$profileRole};disabled=@{booleanValue=$false};municipalityId=@{stringValue=$municipality};reportsCount=@{integerValue='0'}}}|ConvertTo-Json -Depth 10)|Out-Null
 }
 $admin=@{Authorization="Bearer $($users[0].idToken)"};$citizen=@{Authorization="Bearer $($users[1].idToken)"};$other=@{Authorization="Bearer $($users[2].idToken)"}
 $fields=@{municipalityId=@{stringValue='060707'};business=@{stringValue='QA Comercio'};message=@{stringValue='Anuncio de prueba'};imageUrl=@{stringValue=''};link=@{stringValue='https://example.com'};startsAt=@{timestampValue='2026-10-01T00:00:00Z'};endsAt=@{timestampValue='2026-12-01T00:00:00Z'};active=@{booleanValue=$true}}
 $body=@{writes=@(@{update=@{name="projects/$project/databases/(default)/documents/localAds/$id";fields=$fields};updateTransforms=@(@{fieldPath='updatedAt';setToServerValue='REQUEST_TIME'})})}
 Check 'Ciudadano no publica publicidad' {Invoke-RestMethod -Method Post -Uri "${base}:commit" -Headers $citizen -ContentType 'application/json' -Body ($body|ConvertTo-Json -Depth 15)} $true
 Check 'Administrador publica publicidad' {Invoke-RestMethod -Method Post -Uri "${base}:commit" -Headers $admin -ContentType 'application/json' -Body ($body|ConvertTo-Json -Depth 15)}
 Check 'Vecino del municipio lee anuncio' {Invoke-RestMethod -Uri "$base/localAds/$id" -Headers $citizen}
 Check 'Vecino de otro municipio no lee anuncio' {Invoke-RestMethod -Uri "$base/localAds/$id" -Headers $other} $true
 $query=@{structuredQuery=@{from=@(@{collectionId='localAds'});where=@{compositeFilter=@{op='AND';filters=@(@{fieldFilter=@{field=@{fieldPath='municipalityId'};op='EQUAL';value=@{stringValue='060707'}}},@{fieldFilter=@{field=@{fieldPath='active'};op='EQUAL';value=@{booleanValue=$true}}})}};limit=50}}
 Check 'Consulta de banners sin índice faltante' {Invoke-RestMethod -Method Post -Uri "${base}:runQuery" -Headers $citizen -ContentType 'application/json' -Body ($query|ConvertTo-Json -Depth 15)}
 $fields.endsAt=@{timestampValue='2026-09-01T00:00:00Z'}
 Check 'Fechas inválidas rechazadas' {Invoke-RestMethod -Method Post -Uri "${base}:commit" -Headers $admin -ContentType 'application/json' -Body ($body|ConvertTo-Json -Depth 15)} $true
 $fields.endsAt=@{timestampValue='2026-12-01T00:00:00Z'}; $fields.active=@{booleanValue=$false}
 Check 'Administrador desactiva anuncio' {Invoke-RestMethod -Method Post -Uri "${base}:commit" -Headers $admin -ContentType 'application/json' -Body ($body|ConvertTo-Json -Depth 15)}
 Check 'Anuncio desactivado oculto al vecino' {Invoke-RestMethod -Uri "$base/localAds/$id" -Headers $citizen} $true
} finally {
 Invoke-RestMethod -Method Delete -Uri "$base/localAds/$id" -Headers $owner -ErrorAction SilentlyContinue|Out-Null
 foreach($a in $users){Invoke-RestMethod -Method Delete -Uri "$base/users/$($a.localId)" -Headers $owner -ErrorAction SilentlyContinue|Out-Null;Invoke-RestMethod -Method Post -Uri "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$key" -ContentType 'application/json' -Body (@{idToken=$a.idToken}|ConvertTo-Json) -ErrorAction SilentlyContinue|Out-Null}
}
$checks|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot '..\store_assets\PRUEBAS_PUBLICIDAD.json') -Encoding UTF8
$checks|ForEach-Object {Write-Output "$($_.passed): $($_.test)"}
if(@($checks|Where-Object {-not $_.passed}).Count){throw 'Fallaron pruebas de publicidad'}
