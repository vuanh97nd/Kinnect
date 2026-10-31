param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'stop', 'restart', 'status')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverPath = [System.IO.Path]::GetFullPath((Join-Path $root 'server.js'))
$port = 3000
$stateDir = Join-Path $env:TEMP 'kinnect-server-control'
$pidFile = Join-Path $stateDir 'server.pid'
$stdoutLog = Join-Path $stateDir 'server-out.log'
$stderrLog = Join-Path $stateDir 'server-error.log'

function Get-KinnectProcesses {
    if (-not (Test-Path -LiteralPath $pidFile)) { return @() }
    $savedId = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    $processId = 0
    if (-not [int]::TryParse([string]$savedId, [ref]$processId)) { return @() }
    if (@(Get-PortOwners) -notcontains $processId) { return @() }
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -ne 'node') { return @() }
    return $process
}
function Get-PortOwners {
    @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique)
}

function Start-Kinnect {
    $existing = @(Get-KinnectProcesses)
    if ($existing.Count -gt 0) {
        Write-Host "Kinnect server is already running. PID: $($existing.Id -join ', ')"
        return
    }

    $owners = Get-PortOwners
    if ($owners.Count -gt 0) {
        Write-Host "Port $port is already in use by PID $($owners -join ', ')."
        Write-Host "The controller will not stop an unrelated process."
        return
    }

    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Host "Node.js was not found. Install Node.js 22.13 or newer first."
        return
    }

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $process = Start-Process -FilePath $node.Source -ArgumentList ('"' + $serverPath + '"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ascii

    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
            Write-Host "Kinnect server is running at http://127.0.0.1:$port"
            Write-Host "PID: $($process.Id)"
            return
        } catch {
            if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
                Write-Host "The server stopped during startup. Check:"
                Write-Host $stderrLog
                if (Test-Path -LiteralPath $stderrLog) {
                    Get-Content -LiteralPath $stderrLog -Tail 20
                }
                return
            }
        }
    }

    Write-Host "The server started but did not answer the health check yet."
    Write-Host "Logs: $stdoutLog and $stderrLog"
}

function Stop-Kinnect {
    $processes = @(Get-KinnectProcesses)
    if ($processes.Count -eq 0) {
        if (Test-Path -LiteralPath $pidFile) {
            Remove-Item -LiteralPath $pidFile -Force
        }
        Write-Host "Kinnect server is not running."
        return
    }

    foreach ($process in $processes) {
        Stop-Process -Id $process.Id -Force
        Write-Host "Stopped Kinnect server PID $($process.Id)."
    }
    if (Test-Path -LiteralPath $pidFile) {
        Remove-Item -LiteralPath $pidFile -Force
    }
}

function Show-Status {
    $processes = @(Get-KinnectProcesses)
    $owners = Get-PortOwners
    if ($processes.Count -gt 0) {
        Write-Host "Kinnect server: RUNNING (PID $($processes.Id -join ', '))"
    } elseif ($owners.Count -gt 0) {
        Write-Host "Port $port is occupied by another process (PID $($owners -join ', '))."
    } else {
        Write-Host "Kinnect server: STOPPED"
    }
    Write-Host "Project: $root"
    Write-Host "Health check: http://127.0.0.1:$port/health"
}

switch ($Action) {
    'start' { Start-Kinnect }
    'stop' { Stop-Kinnect }
    'restart' { Stop-Kinnect; Start-Sleep -Seconds 1; Start-Kinnect }
    'status' { Show-Status }
}
