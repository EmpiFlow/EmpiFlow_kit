# EmpiFlow kit - stop the stack. Data is kept; start it again with start.cmd.
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'lib.ps1')
$engine = Get-EmpiEngine
if (-not $engine) {
    Write-Host 'EmpiFlow is not running (no Docker engine found) - nothing to stop.' -ForegroundColor Yellow
    exit 0
}
Invoke-Compose -Arguments @('stop') -AllowFailure | Out-Null
Write-Host ''
Write-Host 'EmpiFlow is stopped. Your data is kept.' -ForegroundColor Green
Write-Host 'Start it again with scripts\start.cmd' -ForegroundColor DarkGray
exit 0
