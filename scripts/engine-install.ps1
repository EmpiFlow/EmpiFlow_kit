# EmpiFlow kit - set up a Docker engine inside WSL 2 (no Docker Desktop, no account, no licence).
#
# Two phases, because Windows needs one restart in the middle:
#   phase 1  enables the two Windows features            -> exits 3, meaning "restart, then run me again"
#   phase 2  installs the WSL distribution + Docker      -> exits 0
#
# Run it from an elevated window (Install.cmd -InstallEngine does that for you):
#   powershell -ExecutionPolicy Bypass -File scripts\engine-install.ps1 -Accept
#
# Exit codes: 0 = engine ready   1 = failed   2 = not Windows   3 = restart required, then run again
[CmdletBinding()]
param(
    [switch]$Accept,
    [switch]$Force,
    [string]$Distro = 'Ubuntu-24.04'
)

. (Join-Path $PSScriptRoot 'lib.ps1')

if (-not (Test-IsWindowsOS)) { exit 2 }

if (-not (Test-IsElevated)) {
    $self = Join-Path $PSScriptRoot 'engine-install.ps1'
    Write-Host ''
    Write-Bad 'this step needs an administrator window'
    Write-Note 'Open "Windows PowerShell" from the Start menu with right-click -> Run as administrator, then run:'
    Write-Note ('  powershell -ExecutionPolicy Bypass -File "{0}" -Accept' -f $self)
    Write-Host ''
    exit 1
}

if (-not $Accept -and -not $Force) {
    Write-Host ''
    Write-Host 'This will install WSL 2 and the Docker engine on this machine.' -ForegroundColor Yellow
    Write-Host 'It changes Windows features, then asks for one restart. Continue? [y/N] ' -NoNewline
    if ((Read-Host) -notmatch '^[yY]') { Write-Host 'Nothing was changed.'; exit 1 }
}

# ?? phase 1: Windows features ???????????????????????????????????????????????
Write-Head 'Windows features'
$needReboot = $false
foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $f = Get-WindowsOptionalFeature -Online -FeatureName $feature
    if ($f.State -eq 'Enabled') {
        Write-Ok ("{0} is enabled" -f $feature)
    } else {
        Write-Step ("enabling {0}" -f $feature)
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
        if ($r.RestartNeeded) { $needReboot = $true }
        Write-Ok ("{0} enabled" -f $feature)
    }
}

if ($needReboot) {
    Write-Host ''
    Write-Host 'Windows has to restart once before WSL can run.' -ForegroundColor Yellow
    Write-Host 'After the restart, run Install.cmd again (it continues from here).' -ForegroundColor Yellow
    Write-Host ''
    exit 3
}

# --- phase 1b: memory caps. WSL2 takes half of RAM by default and never gives page cache back, which on an
# 8 GB laptop is how the whole machine (and WSL itself) stops answering. Measured on this project's own
# hardware: 3 GB + 6 GB swap + dropCache keeps the stack alive with Windows still usable (MG's own
# install notes, D:\OpenCode\MGDesktop\Install_Frappe_Stack_CafApp).
Write-Head 'Memory settings'
$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslConfig) {
    Write-Ok '.wslconfig already exists - leaving it alone'
    Write-Note 'if the laptop becomes unresponsive, cap WSL: [wsl2] memory=3GB / swap=6GB'
} else {
    Write-Step 'writing .wslconfig (WSL gets 3 GB, the rest stays with Windows)'
    $content = @"
# EmpiFlow kit - WSL2 resource caps for an 8 GB laptop.
# Written once by scripts\engine-install.ps1; delete this file to return to Windows defaults.
[general]
instanceIdleTimeout=-1

[wsl2]
memory=3GB
swap=6GB
vmIdleTimeout=-1

[experimental]
autoMemoryReclaim=dropCache
"@
    [System.IO.File]::WriteAllText($wslConfig, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok ("wrote " + $wslConfig)
    & $script:WslExe --shutdown 2>$null | Out-Null
}

# ?? phase 2: WSL runtime ????????????????????????????????????????????????????
Write-Head 'WSL 2'
$verProbe = Invoke-WslTimed -Arguments @('--version') -TimeoutSeconds 25 -UnicodeOutput
$wslOk = (-not $verProbe.TimedOut) -and (($verProbe.Output -join ' ') -match 'WSL version')
if (-not $wslOk -and $verProbe.TimedOut) {
    # A wedged WSL service is the one failure that looks exactly like "nothing happens". Recover it once.
    Write-Warn 'WSL did not answer within 25 s - restarting the WSL service'
    & $script:WslExe --shutdown 2>$null | Out-Null
    Start-Sleep -Seconds 3
    $verProbe = Invoke-WslTimed -Arguments @('--version') -TimeoutSeconds 25 -UnicodeOutput
    $wslOk = (-not $verProbe.TimedOut) -and (($verProbe.Output -join ' ') -match 'WSL version')
}

if (-not $wslOk) {
    Write-Step 'installing the WSL 2 runtime (this downloads ~100 MB)'
    & $script:WslExe --install --no-distribution --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    & $script:WslExe --update --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    $null = & $script:WslExe --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        # Windows 11 24H2+/25H2 ships a wsl.exe stub that cannot install itself: WSL is an MSIX package.
        # Measured on the G2 laptop (build 26200): `wsl --install` prints "not installed" and exits 1,
        # while `winget install Microsoft.WSL` installs 3.0.5 and works after one restart.
        Write-Step 'the WSL stub cannot install itself on this build - installing the package with winget'
        & winget.exe install --id Microsoft.WSL -e --accept-package-agreements --accept-source-agreements --silent 2>&1 |
            ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        Write-Host ''
        Write-Host 'WSL was installed as a Windows package and needs one restart.' -ForegroundColor Yellow
        Write-Host 'Restart the laptop, then run Install.cmd again.' -ForegroundColor Yellow
        Write-Host ''
        exit 3
    }
}
& $script:WslExe --set-default-version 2 2>&1 | Out-Null
Write-Ok 'WSL 2 is available'

# ?? phase 2b: a Linux distribution ??????????????????????????????????????????
# Primary route: import the official Ubuntu base rootfs. It is 30 MB, needs no Microsoft Store, no
# first-run account and no interactive window - all of which the Store installer does (measured on the
# G2 laptop: `wsl --install -d Ubuntu-24.04` hung with 2 CPU-seconds in 25 minutes).
$distros = @(Get-WslDistros)
if ($distros.Count -eq 0) {
    $imported = $false
    Write-Step ("creating {0} from the official Ubuntu base image (downloads ~30 MB, no Store needed)" -f $Distro)
    try {
        $tarPath = Join-Path $env:TEMP 'ubuntu-base-24.04.tar.gz'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz' `
            -OutFile $tarPath -TimeoutSec 900
        $rootDir = Join-Path $env:ProgramData ("EmpiFlow\wsl\" + $Distro)
        New-Item -ItemType Directory -Force -Path $rootDir | Out-Null
        & $script:WslExe --import $Distro $rootDir $tarPath --version 2 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        $distros = @(Get-WslDistros)
        $imported = ($distros.Count -gt 0)
    }
    catch { $imported = $false }

    if (-not $imported) {
        Write-Step 'falling back to the Microsoft Store installer'
        & $script:WslExe --install -d $Distro --no-launch --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        $distros = @(Get-WslDistros)
    }
    if ($distros.Count -eq 0) {
        Write-Bad 'no WSL distribution is installed'
        Write-Note 'Check the internet connection, then run Install.cmd -InstallEngine again.'
        exit 1
    }
}
if ($Distro -and ($distros -contains $Distro)) { $target = $Distro } else { $target = $distros[0] }
Write-Ok ("using the distribution {0}" -f $target)

# ?? phase 2c: Docker inside it ?????????????????????????????????????????????
Write-Head 'Docker engine inside WSL'

$bootstrap = @'
set -e
export DEBIAN_FRONTEND=noninteractive
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
echo "docker: $(docker --version)"
'@

$bootstrap = $bootstrap -replace "`r", ''
Write-Step 'installing Docker (first run only, a few minutes)'
$bootstrapProbe = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'bash', '-c', $bootstrap) -TimeoutSeconds 1500
$out = @($bootstrapProbe.Output) + @($bootstrapProbe.Error)
$out | ForEach-Object { if ("$_".Trim()) { Write-Host "         $_" -ForegroundColor DarkGray } }
$dockerNow = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'bash', '-c', 'command -v docker') -TimeoutSeconds 30
if ($bootstrapProbe.TimedOut -or -not ($dockerNow.Output -join '').Trim()) {
    Write-Bad 'the Docker installation inside WSL failed'
    Write-Note ('Check that the WSL distribution can reach the internet:  wsl -d {0} -u root -- apt-get update' -f $target)
    exit 1
}

# systemd makes docker start with the distribution (WSL starts it on demand).
Write-Step 'enabling systemd and the docker service'
$null = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'bash', '-c',
    'grep -qs "^systemd=true" /etc/wsl.conf || printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf') -TimeoutSeconds 30
& $script:WslExe --terminate $target 2>$null | Out-Null
Start-Sleep -Seconds 3
$null = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'bash', '-c',
    'systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true') -TimeoutSeconds 120

$ready = $false
$v = ''
for ($i = 0; $i -lt 30; $i++) {
    $probe = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'bash', '-c',
        'docker info --format "{{.ServerVersion}}" 2>/dev/null') -TimeoutSeconds 45
    $v = ($probe.Output -join '').Trim()
    if (-not $probe.TimedOut -and $probe.Code -eq 0 -and $v) { $ready = $true; break }
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    Write-Bad 'the Docker daemon did not start inside WSL'
    Write-Note ('Inspect it with:  wsl -d {0} -u root -- service docker start' -f $target)
    exit 1
}

$composeProbe = Invoke-WslTimed -Arguments @('-d', $target, '-u', 'root', '-e', 'docker', 'compose', 'version', '--short') -TimeoutSeconds 60
$compose = ($composeProbe.Output | Select-Object -First 1)
Write-Host ''
Write-Ok ("Docker {0} is running inside WSL ({1})" -f "$v".Trim(), $target)
Write-Ok ("docker compose {0}" -f "$compose".Trim())
Write-Host ''
exit 0
