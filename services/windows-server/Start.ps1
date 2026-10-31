$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$node=Join-Path $root 'runtime\node.exe'
if (![IO.File]::Exists($node)) {throw 'Missing bundled Node.js runtime.'}
$homeDir=Join-Path $env:LOCALAPPDATA 'KinnectServer'
[IO.Directory]::CreateDirectory($homeDir)|Out-Null
$running=$false
try {$response=Invoke-WebRequest 'http://127.0.0.1:3128/' -UseBasicParsing -TimeoutSec 2; $running=$response.Content.Contains('Kinnect Server')}catch{}
if (!$running) {
 Start-Process -FilePath $node -ArgumentList ('"'+(Join-Path $root 'server.mjs')+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $homeDir 'manager.log') -RedirectStandardError (Join-Path $homeDir 'manager-error.log')
 for($i=0;$i -lt 40;$i++){Start-Sleep -Milliseconds 200;try{$response=Invoke-WebRequest 'http://127.0.0.1:3128/' -UseBasicParsing -TimeoutSec 1;if($response.Content.Contains('Kinnect Server')){$running=$true;break}}catch{}}
}
if (!$running){throw 'Cannot start manager. See manager-error.log in LocalAppData\KinnectServer.'}
$settings=[IO.File]::ReadAllText((Join-Path $homeDir 'settings.json'))|ConvertFrom-Json
Start-Process ('http://127.0.0.1:3128/#'+$settings.adminKey)
