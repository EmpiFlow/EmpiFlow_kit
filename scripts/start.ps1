# EmpiFlow kit - start the stack (and the engine, if it is not running yet). Safe to run any time.
[CmdletBinding()]
param([switch]$NoBrowser)

. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not (Test-IsWindowsOS)) {
    Write-Host 'EmpiFlow_kit is not configured to install on this operating system. This kit supports Windows 10 and Windows 11 only. Nothing has been changed on this machine.' -ForegroundColor Red
    exit 2
}

$engine = Get-EmpiEngine
if (-not $engine) {
    Write-Step 'the engine is not running - trying to start it'
    Start-EmpiEngine | Out-Null
    $engine = Get-EmpiEngine -Refresh
}
if (-not $engine) {
    Write-Bad 'no Docker engine found'
    Write-Note 'Run scripts\doctor.ps1 to see what is missing.'
    exit 1
}

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')

Write-Host ''
Write-Step 'starting EmpiFlow'
Invoke-Compose -Arguments @('up', '-d') | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Bad 'docker compose up failed - see scripts\logs.cmd'; exit 1 }

if (Wait-ForHttp -Url "http://127.0.0.1:$httpPort/api/method/ping" -TimeoutSeconds 300 -Label 'ERPNext') {
    Write-Host ''
    Write-Ok ('EmpiFlow is up:  http://127.0.0.1:{0}' -f $httpPort)
    Write-Ok ('Metabase:        http://127.0.0.1:{0}' -f $mbPort)
    if (-not $NoBrowser) { Open-Browser "http://127.0.0.1:$httpPort" }
    exit 0
}
Write-Host ''
Write-Bad 'the stack started but ERPNext is not answering yet'
Write-Note 'Give it a minute, or run scripts\status.cmd'
exit 1
