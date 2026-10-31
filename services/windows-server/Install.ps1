$ErrorActionPreference='Stop'
$destination=Join-Path $env:LOCALAPPDATA 'KinnectServerApp'
$source=[IO.Path]::GetFullPath($PSScriptRoot)
$target=[IO.Path]::GetFullPath($destination)
if($source -ne $target){
 [IO.Directory]::CreateDirectory($target)|Out-Null
 foreach($name in @('server.mjs','store.mjs','sync.mjs','index.html','choose-folder.ps1','Start.ps1','Kinnect-Server.cmd','README.txt','runtime')){
  Copy-Item -LiteralPath (Join-Path $source $name) -Destination $target -Recurse -Force
 }
}
$shell=New-Object -ComObject WScript.Shell
$shortcut=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Kinnect Server.lnk'))
$shortcut.TargetPath=Join-Path $target 'Kinnect-Server.cmd'
$shortcut.WorkingDirectory=$target
$shortcut.Description='Kinnect Server - Media storage and incremental sync'
$shortcut.Save()
& (Join-Path $target 'Start.ps1')
