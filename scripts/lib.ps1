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

# ?? output ???????????????????????????????????????????????????????????????????
function Write-Head { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  [ OK ] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Note { param([string]$Text) Write-Host "         $Text" -ForegroundColor DarkGray }
function Write-Step { param([string]$Text) Write-Host "  -> $Text" -ForegroundColor Gray }

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
    if (-not (Test-CommandExists 'wsl.exe')) { return @() }
    $raw = @()
    try {
        $raw = @(& wsl.exe -l -q 2>$null)
    }
    catch { return @() }
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

function Get-TotalRamGb {
    $bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    return [math]::Round($bytes / 1GB, 1)
}

function Get-FreeDiskGb {
    $drive = (Split-Path -Qualifier $script:KitRoot)
    $d = Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $d) { return -1 }
    return [math]::Round($d.Free / 1GB, 1)
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

function Write-EnvFile {
    param([hashtable]$Values)
    $order = @('SITE_NAME', 'ADMIN_PASSWORD', 'DB_PASSWORD', 'MB_RO_PASSWORD',
               'HTTP_PORT', 'METABASE_PORT', 'EMPI_IMAGE', 'EMPI_IMAGE_TAG')
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
        $v = & wsl.exe -d $distro -u root -e bash -c 'docker info --format "{{.ServerVersion}}" 2>/dev/null' 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            $wslRoot = (& wsl.exe -d $distro -e wslpath -a $script:KitRoot 2>$null | Select-Object -First 1)
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

    if (Test-CommandExists 'docker') {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (Test-Path $desktop) {
            Write-Step 'starting Docker Desktop'
            try { Start-Process $desktop | Out-Null } catch { }
        }
    }
    foreach ($distro in (Get-WslDistros)) {
        & wsl.exe -d $distro -u root -e bash -c 'systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true' 2>$null | Out-Null
    }

    for ($i = 0; $i -lt 30; $i++) {
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

    if ($engine.Kind -eq 'windows') {
        Push-Location $script:KitRoot
        try { & docker @Arguments } finally { Pop-Location }
    }
    else {
        & wsl.exe -d $engine.Distro -u root --cd $engine.WslRoot -e docker @Arguments
    }
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "docker $($Arguments -join ' ') failed (exit $LASTEXITCODE)"
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
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { return $true }
        }
        catch {
            # 502/503 while gunicorn boots are expected; anything else is still "not yet".
        }
        $left = [int]($TimeoutSeconds - $sw.Elapsed.TotalSeconds)
        Write-Host ("`r  waiting for {0} ... {1,4}s elapsed, {2,4}s left " -f $Label, [int]$sw.Elapsed.TotalSeconds, [math]::Max($left, 0)) -NoNewline
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
