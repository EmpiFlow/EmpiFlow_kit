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

# ?? phase 2: WSL runtime ????????????????????????????????????????????????????
Write-Head 'WSL 2'
$wslOk = $true
try {
    $null = & wsl.exe --version 2>$null
    if ($LASTEXITCODE -ne 0) { $wslOk = $false }
} catch { $wslOk = $false }

if (-not $wslOk) {
    Write-Step 'installing the WSL 2 runtime (this downloads ~100 MB)'
    & wsl.exe --install --no-distribution --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    & wsl.exe --update --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
}
& wsl.exe --set-default-version 2 2>&1 | Out-Null
Write-Ok 'WSL 2 is available'

# ?? phase 2b: a Linux distribution ??????????????????????????????????????????
$distros = @(Get-WslDistros)
if ($distros.Count -eq 0) {
    Write-Step ("installing {0} (this downloads ~300 MB)" -f $Distro)
    & wsl.exe --install -d $Distro --no-launch --web-download 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) {
        Write-Step 'retrying through the Microsoft Store'
        & wsl.exe --install -d $Distro --no-launch 2>&1 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    }
    $distros = @(Get-WslDistros)
    if ($distros.Count -eq 0) {
        Write-Bad 'no WSL distribution is installed'
        Write-Note 'Run this from a window that has internet, or install Ubuntu 24.04 from the Microsoft Store.'
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

Write-Step 'installing Docker (first run only, a few minutes)'
$out = & wsl.exe -d $target -u root -e bash -c $bootstrap 2>&1
$out | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
if ($LASTEXITCODE -ne 0) {
    Write-Bad 'the Docker installation inside WSL failed'
    Write-Note ('Check that the WSL distribution can reach the internet:  wsl -d {0} -u root -- apt-get update' -f $target)
    exit 1
}

# systemd makes docker start with the distribution (WSL starts it on demand).
Write-Step 'enabling systemd and the docker service'
$null = & wsl.exe -d $target -u root -e bash -c 'grep -qs "^systemd=true" /etc/wsl.conf || printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf'
& wsl.exe --terminate $target 2>$null | Out-Null
Start-Sleep -Seconds 3
$null = & wsl.exe -d $target -u root -e bash -c 'systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true'

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    $v = & wsl.exe -d $target -u root -e bash -c 'docker info --format "{{.ServerVersion}}" 2>/dev/null'
    if ($LASTEXITCODE -eq 0 -and $v) { $ready = $true; break }
    Start-Sleep -Seconds 2
}

if (-not $ready) {
    Write-Bad 'the Docker daemon did not start inside WSL'
    Write-Note ('Inspect it with:  wsl -d {0} -u root -- service docker start' -f $target)
    exit 1
}

$compose = (& wsl.exe -d $target -u root -e docker compose version --short 2>$null | Select-Object -First 1)
Write-Host ''
Write-Ok ("Docker {0} is running inside WSL ({1})" -f "$v".Trim(), $target)
Write-Ok ("docker compose {0}" -f "$compose".Trim())
Write-Host ''
exit 0
