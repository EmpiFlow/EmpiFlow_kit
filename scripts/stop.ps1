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
    Write-Step ('stopping WSL and its Docker engine ({0}); this frees the memory' -f $engine.Distro)
    # Terminate only the kit's distribution, not every WSL distribution the client may use for other work.
    & $script:WslExe --terminate $engine.Distro 2>$null | Out-Null
    Write-Ok ('WSL is stopped ({0}).' -f $engine.Distro)
} elseif ($engine.Kind -eq 'windows') {
    Write-Note 'Docker Desktop is left running - other programs may be using it.'
}

Write-Plain ''
Write-Plain 'Start it again with scripts\start.cmd'
exit 0
