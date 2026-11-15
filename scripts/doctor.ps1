# EmpiFlow kit - doctor. Read-only pre-flight: it changes nothing.
#
#   scripts\doctor.cmd            normal run
#   scripts\doctor.cmd -Quiet     only show problems
#   scripts\doctor.cmd -Json      machine-readable rows (used by the acceptance suite)
#
# Exit codes:  0 = ready (PASS/WARN only)   1 = something FAILED   2 = this operating system is not supported
[CmdletBinding()]
param([switch]$Quiet, [switch]$Json, [string]$LogPath = '', [string]$WslRoot = '')

. (Join-Path $PSScriptRoot 'lib.ps1')
if ($LogPath) { Set-EmpiLog -Path $LogPath }

$refusal = 'EmpiFlow_kit is not configured to install on this operating system. This kit supports Windows 10 and Windows 11 only. Nothing has been changed on this machine.'

if (-not (Test-IsWindowsOS)) {
    Write-Host ''
    Write-Host $refusal -ForegroundColor Red
    Write-Host ''
    exit 2
}

$rows = New-Object System.Collections.ArrayList
function Add-Row {
    param([string]$Id, [string]$Status, [string]$Text, [string]$Fix = '')
    [void]$rows.Add([pscustomobject]@{ Id = $Id; Status = $Status; Text = $Text; Fix = $Fix })
}

# ?? 1. operating system ?????????????????????????????????????????????????????
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
$caption = $os.Caption -replace 'Microsoft ', '' -replace 'Microsoft? ', ''
if ($build -ge 22000) { $winName = 'Windows 11' }
elseif ($build -ge 10240) { $winName = 'Windows 10' }
else { $winName = 'an unsupported Windows version' }
if ($build -ge 19041) {
    Add-Row 'OS' 'PASS' ("{0} (build {1})" -f $winName, $build)
} else {
    Add-Row 'OS' 'FAIL' ("{0} (build {1}) is too old" -f $winName, $build) 'Windows 10 version 2004 (build 19041) or newer is required.'
}

if ([Environment]::Is64BitOperatingSystem) {
    Add-Row 'ARCH' 'PASS' '64-bit Windows'
} else {
    Add-Row 'ARCH' 'FAIL' '32-bit Windows' 'This kit needs 64-bit Windows.'
}

# ?? 2. memory and disk ??????????????????????????????????????????????????????
# D-018: the floor is 8 GB *installed*. Windows reports an 8 GB laptop as ~7.7 GB usable, so the
# installed module capacity is what this check uses (Get-TotalRamGb).
$ram = Get-TotalRamGb
$ramUsable = Get-UsableRamGb
if ($ram -lt 8) {
    Add-Row 'RAM' 'FAIL' ("{0} GB of memory installed - this kit needs 8 GB" -f $ram) 'Use a machine with 8 GB installed. ERPNext, the database and Metabase run together; below 8 GB Windows and WSL compete and the laptop can freeze.'
} else {
    Add-Row 'RAM' 'PASS' ("{0} GB of memory installed ({1} GB usable)" -f $ram, $ramUsable)
}

# The WSL disk is a setting (T-018 / D-017). It, not the kit folder, is what grows by 2-4 GB.
$wslTarget = Get-WslRootPath -Override $WslRoot
if (-not $wslTarget.Valid) {
    Add-Row 'DISK' 'FAIL' ("the WSL disk location is not usable ({0}): {1}" -f $wslTarget.Reason, $wslTarget.Path) 'Set WSL_ROOT in .env (or run Install.cmd -WslRoot D:\EmpiFlow\wsl) to a folder on a drive that exists, then run this again.'
} else {
    $disk = Get-FreeDiskGbForPath $wslTarget.Path
    $diskDrive = Split-Path -Qualifier $wslTarget.Path
    if ($disk -lt 15) {
        Add-Row 'DISK' 'FAIL' ("{0} GB free on {1} (the WSL disk)" -f $disk, $diskDrive) 'Free at least 15 GB (20 GB recommended), or run Install.cmd -WslRoot D:\EmpiFlow\wsl to put the disk on a larger drive.'
    } elseif ($disk -lt 25) {
        Add-Row 'DISK' 'WARN' ("{0} GB free on {1} (the WSL disk) - enough, tight" -f $disk, $diskDrive)
    } else {
        Add-Row 'DISK' 'PASS' ("{0} GB free on {1} (the WSL disk)" -f $disk, $diskDrive)
    }
}

# ?? 3. Docker ???????????????????????????????????????????????????????????????
$engine = Get-EmpiEngine
$virtualization = $null
$hypervisor = $null
try { $virtualization = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled } catch { }
try { $hypervisor = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent } catch { }
# VirtualizationFirmwareEnabled is false on a machine where Hyper-V/WSL is already running (measured
# on this laptop, build 26200). HypervisorPresent is the reliable "it is available" signal.
$vtdAvailable = ($virtualization -ne $false) -or ($hypervisor -eq $true)

if ($engine) {
    Add-Row 'DOCKER' 'PASS' (Show-Engine)
    if (-not $vtdAvailable) {
        Add-Row 'VTD' 'WARN' 'virtualisation is off in the firmware, but a working Docker engine was found' ''
    } else {
        Add-Row 'VTD' 'PASS' 'virtualisation available'
    }

    $cv = $null
    try { $cv = (Invoke-Docker -Arguments @('compose', 'version', '--short') -AllowFailure) } catch { }
    if ($cv) {
        Add-Row 'COMPOSE' 'PASS' ("docker compose " + "$cv".Trim())
    } else {
        Add-Row 'COMPOSE' 'FAIL' 'docker compose v2 is not available' 'Update Docker (the kit needs the compose v2 plugin).'
    }
} else {
    # D-019: a missing engine is not a broken machine. Setting one up is Install.cmd's job; doctor
    # only refuses when a prerequisite (RAM, disk, virtualisation, internet) is actually wrong.
    Add-Row 'DOCKER' 'WARN' 'no Docker engine yet - Install.cmd sets one up (WSL 2 + Docker Engine)' ''
    if (-not $vtdAvailable) {
        Add-Row 'VTD' 'FAIL' 'virtualisation is disabled in the firmware' 'Turn on virtualisation (VT-x/AMD-V) in the BIOS and start again.'
    } else {
        Add-Row 'VTD' 'PASS' 'virtualisation available'
    }
    Add-Row 'COMPOSE' 'SKIP' 'not checked without an engine'

    $distros = @(Get-WslDistros)
    if ($distros.Count -gt 0) {
        Add-Row 'WSL' 'WARN' ("WSL is present ({0}) but no Docker engine answers" -f ($distros -join ', ')) 'Install.cmd starts the engine, or installs it if it is missing.'
    } else {
        Add-Row 'WSL' 'WARN' 'WSL is not set up yet - Install.cmd does it (one restart may be needed)' ''
    }
}

# D-018: the memory cap is part of the RAM requirement. Show it when the kit will use WSL.
if (-not $engine -or $engine.Kind -eq 'wsl') {
    $wslConfigFile = Join-Path $env:USERPROFILE '.wslconfig'
    if (Test-Path $wslConfigFile) {
        $memLine = @(Get-Content -LiteralPath $wslConfigFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\s*memory\s*=' } | Select-Object -First 1)
        if ($memLine.Count -gt 0) {
            Add-Row 'WSLMEM' 'PASS' ("WSL memory cap set (" + $memLine[0].Trim() + ")")
        } else {
            Add-Row 'WSLMEM' 'WARN' 'WSL is not capped in .wslconfig' 'Install.cmd writes memory=3GB and swap=6GB; without the cap an 8 GB laptop can freeze.'
        }
    } else {
        Add-Row 'WSLMEM' 'WARN' 'WSL memory cap is not set yet' 'Install.cmd writes %USERPROFILE%\.wslconfig (3 GB / 6 GB swap) when it sets up the engine.'
    }
}

$dockerDesktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if (-not $engine -and (Test-Path $dockerDesktop)) {
    Add-Row 'DESKTOP' 'WARN' 'Docker Desktop is installed but not running' 'Start "Docker Desktop" from the Start menu, wait for the whale, then run this again.'
}

# ?? 4. ports ????????????????????????????????????????????????????????????????
$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')
$kitUp = $false
if ($engine) { try { $kitUp = Test-KitRunning } catch { $kitUp = $false } }
# Compose state can lag for a few seconds after a WSL restart while the pages already answer.
# A live ping is the stronger signal, and it keeps a re-run of Install.cmd from failing on its own ports.
# It is checked even when the engine probe failed: the pages answering is proof enough that the ports are ours.
if (-not $kitUp) {
    try {
        $ping = Invoke-WebRequest -Uri "http://127.0.0.1:$httpPort/api/method/ping" -UseBasicParsing -TimeoutSec 4
        if ($ping.StatusCode -eq 200) { $kitUp = $true }
    } catch { }
}

foreach ($p in @(@{ Port = $httpPort; Name = 'ERPNext' }, @{ Port = $mbPort; Name = 'Metabase' })) {
    $inUse = Test-PortListening -Port $p.Port
    if (-not $inUse) {
        Add-Row ("PORT$($p.Port)") 'PASS' ("port {0} is free ({1})" -f $p.Port, $p.Name)
    } elseif ($kitUp) {
        Add-Row ("PORT$($p.Port)") 'PASS' ("port {0} is in use by EmpiFlow itself ({1})" -f $p.Port, $p.Name)
    } else {
        Add-Row ("PORT$($p.Port)") 'FAIL' ("port {0} is used by another program ({1})" -f $p.Port, $p.Name) ("Close that program, or set HTTP_PORT/METABASE_PORT in .env to a free port.")
    }
}

# ?? 5. internet ?????????????????????????????????????????????????????????????
try {
    $online = Test-NetConnection -ComputerName 'ghcr.io' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
} catch { $online = $false }
if ($online) {
    Add-Row 'NET' 'PASS' 'ghcr.io reachable (the image is downloaded from there)'
} else {
    Add-Row 'NET' 'FAIL' 'cannot reach ghcr.io on port 443' 'Check the internet connection, or a proxy/firewall that blocks GitHub.'
}

if (Test-IsElevated) {
    Add-Row 'ADMIN' 'PASS' 'this window is elevated'
} else {
    Add-Row 'ADMIN' 'WARN' 'not elevated - fine for starting the stack, not enough to install the engine' ''
}

# ?? report ??????????????????????????????????????????????????????????????????
$fails = @($rows | Where-Object { $_.Status -eq 'FAIL' })
$warns = @($rows | Where-Object { $_.Status -eq 'WARN' })
$oks   = @($rows | Where-Object { $_.Status -eq 'PASS' })
$skips = @($rows | Where-Object { $_.Status -eq 'SKIP' })

if ($Json) {
    $exitNow = 0
    if ($fails.Count -gt 0) { $exitNow = 1 }
    [pscustomobject]@{
        exit      = $exitNow
        pass      = $oks.Count
        warn      = $warns.Count
        fail      = $fails.Count
        rows      = $rows
        engine    = $(if ($engine) { $engine.Kind } else { $null })
        distro    = $(if ($engine) { $engine.Distro } else { $null })
        kitRoot   = $script:KitRoot
        httpPort  = $httpPort
        mbPort    = $mbPort
        ramGb     = $ram
        ramUsableGb = $ramUsable
        wslRoot   = $wslTarget.Path
        wslRootValid = $wslTarget.Valid
    } | ConvertTo-Json -Depth 6
    exit $exitNow
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host 'EmpiFlow kit - machine check' -ForegroundColor White
    Write-Host ''
}
foreach ($r in $rows) {
    if ($Quiet -and $r.Status -eq 'PASS') { continue }
    switch ($r.Status) {
        'PASS' { Write-Ok   $r.Text }
        'WARN' { Write-Warn $r.Text }
        'FAIL' { Write-Bad  $r.Text }
        'SKIP' { Write-Note ("skipped: " + $r.Text) }
    }
    if ($r.Fix -and $r.Status -ne 'PASS') { Write-Note ("fix: " + $r.Fix) }
}

Write-Host ''
Write-Host ("{0} checks: {1} OK, {2} warning(s), {3} problem(s)" -f $rows.Count, $oks.Count, $warns.Count, $fails.Count) -ForegroundColor White
if ($fails.Count -gt 0) {
    Write-Host ''
    Write-Host 'Fix the problems above, then run this check again.' -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'This machine can run the EmpiFlow kit.' -ForegroundColor Green
if (-not $engine) {
    Write-Host 'Next: double-click Install.cmd - it sets up WSL and Docker for you.' -ForegroundColor DarkGray
}
exit 0
