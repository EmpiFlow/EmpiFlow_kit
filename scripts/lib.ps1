# EmpiFlow kit - shared helpers. Dot-source this file; never run it directly.
# Written for Windows PowerShell 5.1 (the shell a client gets by double-clicking), not only PowerShell 7.

# Deliberately NOT `$ErrorActionPreference = 'Stop'`: every native tool Windows gives us (wsl.exe,
# docker, netstat) writes progress and warnings to stderr, and Stop turns those into terminating errors.
# Individual calls use -ErrorAction / try-catch where a failure really must stop the script.

$script:KitRoot     = Split-Path -Parent $PSScriptRoot
$script:ComposeFile = Join-Path $KitRoot 'compose.yml'
$script:EnvFile     = Join-Path $KitRoot '.env'
$script:EnvExample  = Join-Path $KitRoot '.env.example'
$script:Engine      = $null
$script:WslExe      = Join-Path $env:SystemRoot 'System32\wsl.exe'
$script:LogFile     = $null

# ?? output ???????????????????????????????????????????????????????????????????
# Every helper writes to the console *and* to the log file when one is set. That is what lets the
# installer run headless while a second, visible window tails the log (engine-quirks.md section 8).
function Set-EmpiLog {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (-not (Test-Path -LiteralPath $Path)) {
            [System.IO.File]::WriteAllText($Path, '', (New-Object System.Text.UTF8Encoding($false)))
        }
        $script:LogFile = $Path
    } catch { $script:LogFile = $null }
}

function Write-EmpiLog {
    param([string]$Text)
    if (-not $script:LogFile) { return }
    try {
        $stamp = (Get-Date).ToString('HH:mm:ss')
        # One physical line per entry: docker progress output can carry CR/LF fragments.
        $flat = ($Text -replace "`r", '' -replace "`n", ' / ')
        $line = "[$stamp] $flat"
        [System.IO.File]::AppendAllText($script:LogFile, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

function Write-Head { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan; Write-EmpiLog ''; Write-EmpiLog "== $Text" }
function Write-Ok   { param([string]$Text) Write-Host "  [ OK ] $Text" -ForegroundColor Green; Write-EmpiLog "  [ OK ] $Text" }
function Write-Warn { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow; Write-EmpiLog "  [WARN] $Text" }
function Write-Bad  { param([string]$Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red; Write-EmpiLog "  [FAIL] $Text" }
function Write-Note { param([string]$Text) Write-Host "         $Text" -ForegroundColor DarkGray; Write-EmpiLog "         $Text" }
function Write-Step { param([string]$Text) Write-Host "  -> $Text" -ForegroundColor Gray; Write-EmpiLog "  -> $Text" }
function Write-Detail { param([string]$Text) Write-Host "         $Text" -ForegroundColor DarkGray; Write-EmpiLog "         $Text" }
function Write-Plain { param([string]$Text) Write-Host $Text; Write-EmpiLog $Text }

# Show a log file that a hidden worker is writing, with a heartbeat when it goes quiet.
# The worker cannot be paused by a click in this window (engine-quirks.md section 8).
function Show-LiveLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$WorkerPid = 0,
        [int]$TimeoutMinutes = 45,
        [string]$Title = 'EmpiFlow installer'
    )
    $start = Get-Date
    $deadline = $start.AddMinutes($TimeoutMinutes)
    $seen = 0
    $lastOutput = Get-Date
    $done = $false
    $final = $false
    $code = $null

    try { $Host.UI.RawUI.WindowTitle = $Title } catch { }
    Write-Host ''
    Write-Host "== $Title" -ForegroundColor Cyan
    Write-Host '   The work runs in the background. This window shows its log; you can keep working.' -ForegroundColor DarkGray
    Write-Host ''

    while (-not $done) {
        $text = ''
        if (Test-Path -LiteralPath $Path) {
            try {
                $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $sr = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
                    $text = $sr.ReadToEnd()
                    $sr.Dispose()
                } finally { $fs.Dispose() }
            } catch { $text = '' }
        }

        $newLines = 0
        if ($text) {
            $complete = $text
            if (-not $text.EndsWith("`n")) {
                $idx = $text.LastIndexOf("`n")
                if ($idx -ge 0) { $complete = $text.Substring(0, $idx + 1) } else { $complete = '' }
            }
            if ($complete) {
                $lines = @($complete -split "`n")
                if ($lines.Count -gt 1 -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
                elseif ($lines.Count -eq 1 -and $lines[0] -eq '') { $lines = @() }
                for ($i = $seen; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i].TrimEnd("`r")
                    # The log writer prefixes every line with [HH:mm:ss], so the marker is not at column 1.
                    if ($line -match '^(?:\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\s*)?\[empi\] DONE (-?\d+)$') {
                        $code = [int]$Matches[1]
                        $done = $true
                        break
                    }
                    $color = 'Gray'
                    if ($line -match '\[ OK \]') { $color = 'Green' }
                    elseif ($line -match '\[WARN\]') { $color = 'Yellow' }
                    elseif ($line -match '\[FAIL\]') { $color = 'Red' }
                    elseif ($line -match '^==') { $color = 'Cyan' }
                    elseif ($line -match '^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\]') { $color = 'Gray' }
                    Write-Host $line -ForegroundColor $color
                    $newLines++
                }
                $seen = $lines.Count
            }
        }
        if ($done) { break }
        if ($newLines -gt 0) { $lastOutput = Get-Date }

        if (-not $final -and $WorkerPid -gt 0) {
            $proc = Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue
            if (-not $proc) {
                $final = $true
                $WorkerPid = 0
                Start-Sleep -Milliseconds 400
                continue
            }
        }
        if ($final) {
            if ($null -eq $code) { $code = -1 }
            break
        }
        if ((Get-Date) -gt $deadline) {
            Write-Host ''
            Write-Host ('   The installer has been silent for more than {0} minutes.' -f $TimeoutMinutes) -ForegroundColor Yellow
            Write-Host '   It may still be running; the log is at:' -ForegroundColor Yellow
            Write-Host "   $Path" -ForegroundColor Yellow
            if ($null -eq $code) { $code = -2 }
            break
        }
        if (((Get-Date) - $lastOutput).TotalSeconds -ge 10) {
            $elapsed = (Get-Date) - $start
            Write-Host ("   ... still working ({0:mm\:ss} elapsed)" -f $elapsed) -ForegroundColor DarkGray
            $lastOutput = Get-Date
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host ''
    switch ($code) {
        0  { Write-Host '== Finished.' -ForegroundColor Green }
        3  { Write-Host '== A restart is needed. See the lines above.' -ForegroundColor Yellow }
        -2 { Write-Host '== No completion marker found; see the log above.' -ForegroundColor Yellow }
        default { Write-Host '== Stopped without finishing. See the lines above.' -ForegroundColor Red }
    }
    return $code
}

# ?? small utilities ??????????????????????????????????????????????????????????
function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindowsOS {
    return ($env:OS -eq 'Windows_NT')
}

function Test-IsElevated {
    if (-not (Test-IsWindowsOS)) { return $false }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WslDistros {
    # wsl.exe writes UTF-16 (PowerShell decodes it with NULs between characters) and, on a machine where
    # WSL was never installed, writes its "not installed" notice to stderr. Both are handled here: a
    # machine without WSL must return an empty list, never an exception (measured on the G2 laptop).
    # A *wedged* WSL service must also return an empty list rather than hang - hence the timeout.
    if (-not (Test-Path $script:WslExe)) { return @() }
    $probe = Invoke-WslTimed -Arguments @('-l', '-q') -TimeoutSeconds 25 -UnicodeOutput
    if ($probe.TimedOut) { return @() }
    $raw = @($probe.Output)
    if (-not $raw -or $raw.Count -eq 0) { return @() }
    $names = @()
    foreach ($line in $raw) {
        if ($line -isnot [string]) { continue }
        $name = ($line -replace "`0", '').Trim()
        if (-not $name) { continue }
        if ($name -match '\s') { continue }          # the notice is a sentence; distro names never have spaces
        $names += $name
    }
    return $names
}

function Get-WslDistroStates {
    # name -> state ('Running', 'Stopped', ...), parsed from `wsl -l -v`. Same defenses as Get-WslDistros:
    # UTF-16 output with NULs, a missing wsl.exe, and a wedged service all yield an empty table.
    if (-not (Test-Path $script:WslExe)) { return @{} }
    $probe = Invoke-WslTimed -Arguments @('-l', '-v') -TimeoutSeconds 25 -UnicodeOutput
    if ($probe.TimedOut) { return @{} }
    $table = @{}
    foreach ($line in @($probe.Output)) {
        if ($line -isnot [string]) { continue }
        $clean = (($line -replace "`0", '') -replace "`a", ' ').Trim()
        if (-not $clean) { continue }
        if ($clean -match '^\*?\s*NAME\s+STATE') { continue }     # header
        if ($clean -notmatch '^\*?\s*(\S+)\s+(Running|Stopped|Installing|Uninstalling|Converting|Starting)\b') { continue }
        $table[$Matches[1]] = $Matches[2]
    }
    return $table
}

function Stop-WslEngine {
    # Stop the kit's distribution and give its RAM back. `wsl --terminate` alone does NOT: the WSL2 utility
    # VM stays alive and keeps its working set (measured 2026-11-16 on the G2 target: `Ubuntu-24.04` Stopped,
    # vmmemWSL still 851.9 MB, the ext4.vhdx still locked; `wsl --shutdown` removed the process within a
    # second and released the file). `--shutdown` would also kill a client's *other* WSL distributions, so it
    # is only used when nothing else is running - which is the normal case on a kit laptop.
    param([Parameter(Mandatory = $true)][string]$Distro)
    $null = Invoke-WslTimed -Arguments @('--terminate', $Distro) -TimeoutSeconds 40
    $states = Get-WslDistroStates
    $others = @()
    foreach ($name in @($states.Keys)) {
        if ($name -ne $Distro -and $states[$name] -eq 'Running') { $others += $name }
    }
    if ($others.Count -gt 0) {
        return [pscustomobject]@{ Shutdown = $false; Stopped = $Distro; Others = $others }
    }
    $null = Invoke-WslTimed -Arguments @('--shutdown') -TimeoutSeconds 40
    return [pscustomobject]@{ Shutdown = $true; Stopped = $Distro; Others = @() }
}

function Get-TotalRamGb {
    # Installed capacity, not the figure Windows reports as usable: an 8 GB laptop shows ~7.7 GB in
    # Win32_ComputerSystem, and an 8 GB floor must not fail on the machine the kit is designed for.
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if ($mods.Count -gt 0) {
        $sum = ($mods | Measure-Object -Property Capacity -Sum).Sum
        if ($sum -gt 0) { return [math]::Round($sum / 1GB, 1) }
    }
    $cs = Get-CimInstance Win32_ComputerSystem
    return [math]::Ceiling($cs.TotalPhysicalMemory / 1GB)
}

function Get-UsableRamGb {
    $cs = Get-CimInstance Win32_ComputerSystem
    return [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
}

function Get-FreeDiskGbForPath {
    param([string]$Path)
    if (-not $Path) { return -1 }
    $full = $Path
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { }
    $drive = Split-Path -Qualifier $full
    if (-not $drive) { return -1 }
    $d = Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $d) { return -1 }
    return [math]::Round($d.Free / 1GB, 1)
}

function Get-FreeDiskGb {
    return Get-FreeDiskGbForPath $script:KitRoot
}

# Where the WSL distribution's disk is created. It is a setting because it is 2-4 GB on the system
# drive and a client may have a small C: (T-018 / D-017).
function Get-WslRootPath {
    param([string]$Override = '')
    $default = Join-Path $env:ProgramData 'EmpiFlow\wsl'
    $raw = $Override
    if (-not $raw) { $raw = Get-EnvValue 'WSL_ROOT' '' }
    if (-not $raw) { $raw = $default }
    $raw = [Environment]::ExpandEnvironmentVariables($raw)
    $full = $raw
    $valid = $true
    $reason = ''
    if (-not [System.IO.Path]::IsPathRooted($raw)) {
        $valid = $false
        $reason = 'the path is not absolute'
    } else {
        try { $full = [System.IO.Path]::GetFullPath($raw) } catch { $full = $raw; $valid = $false; $reason = 'the path is not valid' }
        if ($full -match '^[A-Za-z]:\\?$') {
            $valid = $false
            $reason = 'use a folder on the drive, not the drive root'
        } else {
            $drive = Split-Path -Qualifier $full
            if ($drive -and -not (Test-Path ($drive + '\'))) {
                $valid = $false
                $reason = "drive $drive does not exist"
            }
        }
    }
    return [pscustomobject]@{ Path = $full; Valid = $valid; Reason = $reason; Default = $default }
}

function Test-PortListening {
    param([int]$Port)
    $hits = netstat -ano | Select-String -Pattern (":{0}\s" -f $Port)
    return [bool]$hits
}

function Get-EnvValue {
    param([string]$Name, [string]$Default = '')
    $table = Read-EnvFile
    if ($table.ContainsKey($Name) -and $table[$Name] -ne '') { return $table[$Name] }
    return $Default
}

function Read-EnvFile {
    param([string]$Path)
    $table = @{}
    if (-not $Path) { $Path = $script:EnvFile }
    if (-not (Test-Path $Path)) { return $table }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $line.Substring(0, $i).Trim()
        $val = $line.Substring($i + 1).Trim()
        $table[$key] = $val
    }
    return $table
}

function Set-EnvValue {
    # Change one key in an existing .env without rewriting the file (comments and advanced keys survive).
    param([Parameter(Mandatory = $true)][string]$Name, [string]$Value, [string]$Path = '')
    if (-not $Path) { $Path = $script:EnvFile }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $lines = @(Get-Content -LiteralPath $Path)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*' + [regex]::Escape($Name) + '\s*=')) {
            $lines[$i] = "$Name=$Value"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "$Name=$Value" }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"), $utf8NoBom)
    return $true
}

function Write-EnvFile {
    param([hashtable]$Values)
    $order = @('SITE_NAME', 'ADMIN_PASSWORD', 'DB_PASSWORD', 'MB_RO_PASSWORD',
               'HTTP_PORT', 'METABASE_PORT', 'WSL_ROOT', 'EMPI_IMAGE', 'EMPI_IMAGE_TAG')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# EmpiFlow kit settings - written by install.ps1. Edit and run scripts\restart.cmd.')
    [void]$sb.AppendLine('# See .env.example for what each value means. This file is never committed.')
    [void]$sb.AppendLine('')
    foreach ($k in $order) {
        if ($Values.ContainsKey($k)) { [void]$sb.AppendLine("$k=$($Values[$k])") }
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:EnvFile, $sb.ToString().Replace("`r`n", "`n"), $utf8NoBom)
}

function Get-KitImage {
    $repo = Get-EnvValue 'EMPI_IMAGE' 'ghcr.io/empiflow/empiflow-kit-erpnext'
    $tag  = Get-EnvValue 'EMPI_IMAGE_TAG' 'v1.0.0'
    return "$repo`:$tag"
}

# ?? Docker engine ????????????????????????????????????????????????????????????
# Run wsl.exe with a hard timeout. A wedged WSL service otherwise blocks the installer forever with a
# blinking cursor and no message - measured on the G2 laptop, where `wsl -l -q` never returned.
function ConvertTo-WslArgumentString {
    # Start-Process takes one string, not an argv array: quote anything with spaces or quotes so wsl.exe
    # (and the shell behind -c) receives exactly one argument.
    param([string[]]$Arguments)
    $parts = @()
    foreach ($a in $Arguments) {
        $a = ($a -replace "`r", "")   # bash payloads must never carry CRLF
        if ($a -match '[\s"]') { $parts += ('"' + ($a -replace '"', '\"') + '"') }
        else { $parts += $a }
    }
    return ($parts -join ' ')
}

function Invoke-WslTimed {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [switch]$UnicodeOutput
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $result = @{ TimedOut = $false; Code = 0; Output = @(); Error = @() }
    try {
        $p = Start-Process -FilePath $script:WslExe -ArgumentList (ConvertTo-WslArgumentString $Arguments) -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch { }
            $result.TimedOut = $true
            $result.Code = -1
            return $result
        }
        # Settle: the parameterless WaitForExit flushes the redirected streams. ExitCode from
        # Start-Process -PassThru is unreliable in Windows PowerShell 5.1 (measured: stays $null),
        # so callers judge success by the content of Output instead.
        $p.WaitForExit()
        $enc = 'Default'
        if ($UnicodeOutput) { $enc = 'Unicode' }
        $result.Output = @(Get-Content -LiteralPath $outFile -Encoding $enc -ErrorAction SilentlyContinue)
        $result.Error = @(Get-Content -LiteralPath $errFile -Encoding $enc -ErrorAction SilentlyContinue)
        return $result
    }
    catch {
        $result.Code = -1
        $result.Error = @("$($_.Exception.Message)")
        return $result
    }
    finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-EmpiEngine {
    param([switch]$Refresh)
    if ($script:Engine -and -not $Refresh) { return $script:Engine }

    # 1. A Docker CLI on the Windows PATH talking to a live daemon (Docker Desktop or a native engine).
    if (Test-CommandExists 'docker') {
        $v = & docker info --format '{{.ServerVersion}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            $script:Engine = [pscustomobject]@{ Kind = 'windows'; Distro = $null; WslRoot = $null; Version = "$v".Trim() }
            return $script:Engine
        }
    }

    # 2. Docker Engine inside a WSL distribution (this laptop, and the kit's own engine-install.ps1 route).
    foreach ($distro in (Get-WslDistros)) {
        $probe = Invoke-WslTimed -Arguments @('-d', $distro, '-u', 'root', '-e', 'bash', '-c',
            'docker info --format "{{.ServerVersion}}" 2>/dev/null') -TimeoutSeconds 45
        $v = ($probe.Output -join '').Trim()
        if (-not $probe.TimedOut -and $v) {
            $rootProbe = Invoke-WslTimed -Arguments @('-d', $distro, '-e', 'wslpath', '-a', $script:KitRoot) -TimeoutSeconds 20
            $wslRoot = ($rootProbe.Output | Select-Object -First 1)
            if (-not $wslRoot) { $wslRoot = $script:KitRoot -replace '\\', '/' -replace '^([A-Za-z]):', '/mnt/$1' }
            $script:Engine = [pscustomobject]@{ Kind = 'wsl'; Distro = $distro; WslRoot = "$wslRoot".Trim(); Version = "$v".Trim() }
            return $script:Engine
        }
    }

    $script:Engine = $null
    return $null
}

function Start-EmpiEngine {
    # Try to bring an installed engine up: Docker Desktop on Windows, or the docker daemon inside WSL.
    if (Get-EmpiEngine) { return $script:Engine }

    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    $hasDesktop = (Test-CommandExists 'docker') -and (Test-Path $desktop)
    $distros = @(Get-WslDistros)

    # Nothing installed at all: do not make a blank machine wait 90 seconds for an engine that is not
    # there. Install.cmd goes straight to the UAC prompt and the engine installer.
    if (-not $hasDesktop -and $distros.Count -eq 0) {
        Write-Note 'no installed engine was found to start'
        return $null
    }

    if ($hasDesktop) {
        Write-Step 'starting Docker Desktop'
        try { Start-Process $desktop | Out-Null } catch { }
    }
    foreach ($distro in $distros) {
        Write-Step ("starting the Docker engine inside WSL ({0})" -f $distro)
        $null = Invoke-WslTimed -Arguments @('-d', $distro, '-u', 'root', '-e', 'bash', '-c',
            'systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true') -TimeoutSeconds 60
    }

    # Docker Desktop needs longer than a daemon start inside an already-running distro.
    $iterations = 10
    if ($hasDesktop) { $iterations = 30 }
    Write-Note ('waiting for the engine to answer (up to {0} seconds)' -f ($iterations * 3))
    for ($i = 0; $i -lt $iterations; $i++) {
        Start-Sleep -Seconds 3
        $e = Get-EmpiEngine -Refresh
        if ($e) { return $e }
    }
    return $null
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $engine = Get-EmpiEngine
    if (-not $engine) { throw 'No Docker engine found. Run scripts\doctor.ps1 for the fix.' }

    # The WSL VM occasionally stops answering for a few seconds while Windows pages memory
    # (Wsl/Service/WSAETIMEDOUT, seen on both laptops). One retry turns a spurious failure into a pause.
    $attempt = 0
    while ($true) {
        $attempt++
        $output = @()
        if ($engine.Kind -eq 'windows') {
            Push-Location $script:KitRoot
            try { $output = @(& docker @Arguments 2>&1) } finally { Pop-Location }
        }
        else {
            $output = @(& $script:WslExe -d $engine.Distro -u root --cd $engine.WslRoot -e docker @Arguments 2>&1)
        }
        $code = $LASTEXITCODE
        $text = ($output -join "`n")
        if ($code -ne 0 -and $text -match 'WSAETIMEDOUT' -and $attempt -lt 3) {
            Start-Sleep -Seconds 5
            $null = Start-EmpiEngine
            continue
        }
        break
    }
    $output | ForEach-Object { $_ }
    if (-not $AllowFailure -and $code -ne 0) {
        throw "docker $($Arguments -join ' ') failed (exit $code)"
    }
}

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$Arguments, [switch]$AllowFailure)
    $all = @('compose', '--env-file', '.env', '-f', 'compose.yml') + $Arguments
    Invoke-Docker -Arguments $all -AllowFailure:$AllowFailure
}

function Get-ComposeServiceState {
    # Returns a hashtable service -> state ('running', 'exited', ...). Empty when nothing is deployed.
    $json = Invoke-Compose -Arguments @('ps', '--all', '--format', 'json') -AllowFailure
    $rows = @()
    foreach ($line in @($json)) {
        if (-not "$line".Trim()) { continue }
        try { $rows += ("$line" | ConvertFrom-Json) } catch { }
    }
    $table = @{}
    foreach ($r in $rows) { if ($r.Service) { $table[$r.Service] = $r.State } }
    return $table
}

function Test-KitRunning {
    $s = Get-ComposeServiceState
    return ($s.ContainsKey('backend') -and $s['backend'] -eq 'running' -and
            $s.ContainsKey('frontend') -and $s['frontend'] -eq 'running')
}

function Wait-ForHttp {
    param([string]$Url, [int]$TimeoutSeconds = 600, [string]$Label = 'the site')
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastLog = 0
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return $true }
        }
        catch {
            # 502/503 while gunicorn boots are expected; anything else is still "not yet".
        }
        $elapsed = [int]$sw.Elapsed.TotalSeconds
        $left = [int]($TimeoutSeconds - $elapsed)
        Write-Host ("`r  waiting for {0} ... {1,4}s elapsed, {2,4}s left " -f $Label, $elapsed, [math]::Max($left, 0)) -NoNewline
        # The console line above is invisible in a hidden worker; the watcher needs a durable heartbeat.
        if ($elapsed - $lastLog -ge 30) {
            Write-EmpiLog ("  waiting for {0} ... {1}s elapsed" -f $Label, $elapsed)
            $lastLog = $elapsed
        }
        Start-Sleep -Seconds 5
    }
    Write-Host ''
    return $false
}

function Open-Browser {
    param([string]$Url)
    try { Start-Process $Url | Out-Null } catch { }
}

function Show-Engine {
    $e = Get-EmpiEngine
    if (-not $e) { return 'not found' }
    if ($e.Kind -eq 'windows') { return "docker $($e.Version) on Windows" }
    return "docker $($e.Version) inside WSL ($($e.Distro))"
}
