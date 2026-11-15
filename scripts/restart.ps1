# EmpiFlow kit - apply changes made in .env (ports, passwords, image tag). Data is kept.
[CmdletBinding()]
param([switch]$NoBrowser)

. (Join-Path $PSScriptRoot 'lib.ps1')

$engine = Get-EmpiEngine
if (-not $engine) { Start-EmpiEngine | Out-Null; $engine = Get-EmpiEngine -Refresh }
if (-not $engine) { Write-Bad 'no Docker engine found'; exit 1 }

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
Write-Host ''
Write-Step 'recreating the stack with the current .env (data volumes are kept)'
Invoke-Compose -Arguments @('down') -AllowFailure | Out-Null
Invoke-Compose -Arguments @('up', '-d') -AllowFailure | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Bad 'restart failed - see scripts\logs.cmd'; exit 1 }

if (Wait-ForHttp -Url "http://127.0.0.1:$httpPort/api/method/ping" -TimeoutSeconds 300 -Label 'ERPNext') {
    Write-Host ''
    Write-Ok ('EmpiFlow is up:  http://127.0.0.1:{0}' -f $httpPort)
    if (-not $NoBrowser) { Open-Browser "http://127.0.0.1:$httpPort" }
    exit 0
}
Write-Bad 'the stack was recreated but ERPNext is not answering yet - scripts\status.cmd'
exit 1
