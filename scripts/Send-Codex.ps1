param(
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$ThreadId = '01a1887d-0a8d-7b60-8a8c-25b9da8a1f93'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$codexCli = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\a159911ff70742e9\codex.exe'
if (-not (Test-Path -LiteralPath $codexCli)) {
    $found = Get-ChildItem -Path "$env:LOCALAPPDATA\OpenAI\Codex" -Filter "codex.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $codexCli = $found.FullName }
    else { throw 'OpenAI Codex CLI not found.' }
}

Write-Host "Queueing message to Codex thread: $ThreadId" -ForegroundColor Cyan
& $codexCli queue --thread $ThreadId --message $Message --resume
exit $LASTEXITCODE
