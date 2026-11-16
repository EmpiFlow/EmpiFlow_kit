# EmpiFlow kit - stop the stack (data is kept). With the WSL engine, WSL and Docker are stopped too,
# which gives the RAM back to Windows. Start again with start.cmd.
#   scripts\stop.cmd                 stop the stack and the WSL engine
#   scripts\stop.cmd -KeepEngine     stop the containers only, leave WSL/Docker running
[CmdletBinding()]
param([switch]$KeepEngine)

. (Join-Path $PSScriptRoot 'lib.ps1')

Write-Plain ''
Write-Plain 'EmpiFlow kit - stop'

$engine = Get-EmpiEngine
if (-not $engine) {
    Write-Warn 'EmpiFlow is not running (no Docker engine found) - nothing to stop.'
    exit 0
}

Invoke-Compose -Arguments @('stop') -AllowFailure | Out-Null
Write-Ok 'the containers are stopped; your data is kept.'

if ($engine.Kind -eq 'wsl' -and -not $KeepEngine) {
    Write-Step ('stopping WSL and its Docker engine ({0})' -f $engine.Distro)
    # `wsl --terminate` stops the distribution but leaves the shared WSL2 virtual machine (vmmemWSL) alive
    # with its memory still Resident - measured 851.9 MB after terminate on the G2 target, 2026-11-16.
    # Stop-WslEngine adds `wsl --shutdown`, but only when no other distribution is running, because that
    # command would also kill a client's own WSL work.
    $stop = Stop-WslEngine -Distro $engine.Distro
    if ($stop.Shutdown) {
        Write-Ok ('WSL is stopped ({0}); the memory is back with Windows.' -f $engine.Distro)
    } else {
        Write-Ok ('WSL is stopped ({0}); the containers are down.' -f $engine.Distro)
        Write-Warn ('another WSL distribution is running ({0}) - the shared WSL machine stays up and keeps its memory.' -f ($stop.Others -join ', '))
        Write-Note 'Close it, or run "wsl --shutdown" in a normal window to free that memory too.'
    }
} elseif ($engine.Kind -eq 'windows') {
    Write-Note 'Docker Desktop is left running - other programs may be using it.'
}

Write-Plain ''
Write-Plain 'Start it again with scripts\start.cmd'
exit 0
