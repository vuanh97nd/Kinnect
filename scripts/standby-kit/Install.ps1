param([string]$InstallPath = 'C:\Kinnect-Standby')
$ErrorActionPreference = 'Stop'
try {
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.PSObject.Properties) {
        $file = Join-Path $PSScriptRoot $entry.Name
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Value) { throw "Package checksum failed: $($entry.Name)" }
    }
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    & $node -e "const [a,b]=process.versions.node.split('.').map(Number);if(a<22||(a===22&&b<13))process.exit(1);require('node:sqlite');"
    if ($LASTEXITCODE -ne 0) { throw 'Install Node.js LTS (22.13 or newer) from https://nodejs.org/ first.' }
    $target = [IO.Path]::GetFullPath($InstallPath)
    if (Test-Path -LiteralPath $target) { throw "Target already exists. Choose a new empty path: $target" }
    New-Item -ItemType Directory -Path $target | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot 'server\*') -Destination $target -Recurse
    Push-Location $target
    try {
        & npm.cmd ci --omit=dev --ignore-scripts --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed. Check internet, then use a new target folder.' }
        & $node --check server.js
        if ($LASTEXITCODE -ne 0) { throw 'Server syntax check failed.' }
    } finally { Pop-Location }
    'STANDBY - not activated; no production data or credentials installed.' | Set-Content -LiteralPath (Join-Path $target 'STANDBY.txt')
    Write-Host "INSTALLED: $target" -ForegroundColor Green
    Write-Host 'Standby only. No server, tunnel, firewall rule or startup task was enabled.'
    Write-Host 'Next: private connection, consistent database backup, media sync, SFU and controlled failover.'
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
