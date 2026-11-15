# EmpiFlow kit - doctor. Read-only pre-flight: it changes nothing.
#
#   scripts\doctor.cmd            normal run
#   scripts\doctor.cmd -Quiet     only show problems
#   scripts\doctor.cmd -Json      machine-readable rows (used by the acceptance suite)
#
# Exit codes:  0 = ready (PASS/WARN only)   1 = something FAILED   2 = this operating system is not supported
[CmdletBinding()]
param([switch]$Quiet, [switch]$Json)

. (Join-Path $PSScriptRoot 'lib.ps1')

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
$ram = Get-TotalRamGb
if ($ram -lt 6) {
    Add-Row 'RAM' 'FAIL' ("{0} GB of memory - the stack needs about 2.5 GB free and Windows needs the rest" -f $ram) 'Use a machine with 8 GB or more.'
} elseif ($ram -lt 8) {
    Add-Row 'RAM' 'WARN' ("{0} GB of memory - it works, but close other programs during the first start" -f $ram) ''
} else {
    Add-Row 'RAM' 'PASS' ("{0} GB of memory" -f $ram)
}

$disk = Get-FreeDiskGb
if ($disk -lt 15) {
    Add-Row 'DISK' 'FAIL' ("{0} GB free on {1}" -f $disk, (Split-Path -Qualifier $script:KitRoot)) 'Free at least 15 GB (20 GB recommended).'
} elseif ($disk -lt 25) {
    Add-Row 'DISK' 'WARN' ("{0} GB free - enough, tight" -f $disk)
} else {
    Add-Row 'DISK' 'PASS' ("{0} GB free" -f $disk)
}

# ?? 3. Docker ???????????????????????????????????????????????????????????????
$engine = Get-EmpiEngine
$virtualization = $null
try { $virtualization = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled } catch { }

if ($engine) {
    Add-Row 'DOCKER' 'PASS' (Show-Engine)
    if ($virtualization -eq $false) {
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
    Add-Row 'DOCKER' 'FAIL' 'no Docker engine answers' 'Run Install.cmd and let it set one up, or install Docker Desktop.'
    if ($virtualization -eq $false) {
        Add-Row 'VTD' 'FAIL' 'virtualisation is disabled in the firmware' 'Turn on virtualisation (VT-x/AMD-V) in the BIOS and start again.'
    } else {
        Add-Row 'VTD' 'PASS' 'virtualisation available'
    }
    Add-Row 'COMPOSE' 'SKIP' 'not checked without an engine'
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
exit 0
