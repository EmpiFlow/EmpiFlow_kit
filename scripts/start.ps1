# EmpiFlow kit - start WSL, the Docker engine and the stack. Safe to run any time.
#   scripts\start.cmd                 normal
#   scripts\start.cmd -NoBrowser      do not open ERPNext when it is up
[CmdletBinding()]
param([switch]$NoBrowser)

. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not (Test-IsWindowsOS)) {
    Write-Host 'EmpiFlow_kit is not configured to install on this operating system. This kit supports Windows 10 and Windows 11 only. Nothing has been changed on this machine.' -ForegroundColor Red
    exit 2
}

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')

Write-Plain ''
Write-Plain 'EmpiFlow kit - start'

# Already up? Then there is nothing to wait for.
try {
    $probe = Invoke-WebRequest -Uri "http://127.0.0.1:$httpPort/api/method/ping" -UseBasicParsing -TimeoutSec 4
    if ($probe.StatusCode -eq 200) {
        Write-Ok ('EmpiFlow is already up:  http://127.0.0.1:{0}' -f $httpPort)
        Write-Ok ('Metabase:                http://127.0.0.1:{0}' -f $mbPort)
        if (-not $NoBrowser) { Open-Browser "http://127.0.0.1:$httpPort" }
        exit 0
    }
} catch { }

$engine = Get-EmpiEngine
if (-not $engine) {
    Write-Step 'WSL and the Docker engine are not running - starting them (this can take 10-30 seconds)'
    $engine = Start-EmpiEngine
}
if (-not $engine) {
    Write-Bad 'no Docker engine was found on this machine'
    Write-Note 'If EmpiFlow has not been installed here yet, run Install.cmd first.'
    Write-Note 'Otherwise run scripts\doctor.cmd to see what is missing.'
    exit 1
}
Write-Ok (Show-Engine)

Write-Step 'starting the containers'
Invoke-Compose -Arguments @('up', '-d') -AllowFailure | ForEach-Object { Write-Detail "$_" }
if ($LASTEXITCODE -ne 0) {
    Write-Bad 'docker compose up failed - see scripts\logs.cmd'
    exit 1
}

Write-Plain ''
if (Wait-ForHttp -Url "http://127.0.0.1:$httpPort/api/method/ping" -TimeoutSeconds 300 -Label 'ERPNext') {
    Write-Plain ''
    Write-Ok ('EmpiFlow is up:  http://127.0.0.1:{0}' -f $httpPort)
    Write-Ok ('Metabase:        http://127.0.0.1:{0}' -f $mbPort)
    if (-not $NoBrowser) { Open-Browser "http://127.0.0.1:$httpPort" }
    exit 0
}
Write-Plain ''
Write-Bad 'the stack started but ERPNext is not answering yet'
Write-Note 'Give it a minute, or run scripts\status.cmd'
exit 1
