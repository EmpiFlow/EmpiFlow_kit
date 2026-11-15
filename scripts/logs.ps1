# EmpiFlow kit - show the end of a service log.
#   scripts\logs.cmd                everything, last 80 lines each
#   scripts\logs.cmd create-site    one service
[CmdletBinding()]
param([string]$Service = '', [int]$Tail = 80)

. (Join-Path $PSScriptRoot 'lib.ps1')
if (-not (Get-EmpiEngine)) { Write-Host 'EmpiFlow is not running.' -ForegroundColor Yellow; exit 1 }

$arguments = @('logs', '--tail', "$Tail", '--no-color')
if ($Service) { $arguments += $Service }
Invoke-Compose -Arguments $arguments -AllowFailure | ForEach-Object { Write-Host $_ }
