# EmpiFlow kit - install. Creates .env if needed, checks the machine, downloads the image, starts the stack.
#
#   Install.cmd                  the normal, guided way (asks five questions)
#   Install.cmd -Defaults        accept every default, ask nothing (unattended)
#   Install.cmd -InstallEngine   also set up the Docker engine in WSL when none is found (needs admin)
#   Install.cmd -Force           continue even when the machine check reports a problem
#
# Exit codes: 0 = installed and answering   1 = stopped, nothing half-done   2 = unsupported operating system
[CmdletBinding()]
param(
    [switch]$Defaults,
    [switch]$Force,
    [switch]$InstallEngine,
    [switch]$NoBrowser,
    [switch]$SkipPull
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$refusal = 'EmpiFlow_kit is not configured to install on this operating system. This kit supports Windows 10 and Windows 11 only. Nothing has been changed on this machine.'
if (-not (Test-IsWindowsOS)) {
    Write-Host ''
    Write-Host $refusal -ForegroundColor Red
    Write-Host ''
    exit 2
}

Write-Host ''
Write-Host 'EmpiFlow kit - installer' -ForegroundColor White
Write-Host 'ERPNext 15 + Frappe HR + Metabase, on this laptop only.' -ForegroundColor DarkGray

# ?? 1. settings ?????????????????????????????????????????????????????????????
Write-Head 'Settings'
$needEnv = -not (Test-Path $script:EnvFile)
$values = @{
    SITE_NAME     = 'empiflow.local'
    ADMIN_PASSWORD = 'admin'
    DB_PASSWORD   = 'admin'
    MB_RO_PASSWORD = 'metabase_ro'
    HTTP_PORT     = '8080'
    METABASE_PORT = '3000'
    EMPI_IMAGE    = 'ghcr.io/empiflow/empiflow-kit-erpnext'
    EMPI_IMAGE_TAG = 'v1.0.0'
}

if ($needEnv) {
    if ($Defaults) {
        Write-Step 'using the defaults (no questions asked)'
    } else {
        Write-Note 'Press Enter to accept the value in [brackets].'
        Write-Host ''
        $site = Read-Host "  Site name                    [$($values.SITE_NAME)]"
        if ($site) { $values.SITE_NAME = $site.Trim() }
        $admin = Read-Host "  ERPNext admin password       [$($values.ADMIN_PASSWORD)]"
        if ($admin) { $values.ADMIN_PASSWORD = $admin }
        $db = Read-Host "  Database password            [$($values.DB_PASSWORD)]"
        if ($db) { $values.DB_PASSWORD = $db }
        $http = Read-Host "  ERPNext port                 [$($values.HTTP_PORT)]"
        if ($http) { $values.HTTP_PORT = $http.Trim() }
        $mb = Read-Host "  Metabase port                [$($values.METABASE_PORT)]"
        if ($mb) { $values.METABASE_PORT = $mb.Trim() }
    }
    if ($values.SITE_NAME -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]{1,60}$') {
        Write-Bad ("site name '{0}' is not valid - use letters, digits, dots and dashes" -f $values.SITE_NAME); exit 1
    }
    foreach ($k in @('HTTP_PORT', 'METABASE_PORT')) {
        $n = 0
        if (-not [int]::TryParse($values[$k], [ref]$n) -or $n -lt 1024 -or $n -gt 65535) {
            Write-Bad ("{0} must be a number between 1024 and 65535" -f $k); exit 1
        }
    }
    if (-not $values.ADMIN_PASSWORD) { Write-Bad 'the admin password cannot be empty'; exit 1 }
    Write-EnvFile -Values $values
    Write-Ok "wrote $script:EnvFile"
} else {
    $cur = Read-EnvFile
    foreach ($k in $cur.Keys) { $values[$k] = $cur[$k] }
    Write-Ok ".env already exists - keeping it (site $($values.SITE_NAME))"
}

$httpPort = [int]$values.HTTP_PORT
$mbPort   = [int]$values.METABASE_PORT
$image    = "$($values.EMPI_IMAGE):$($values.EMPI_IMAGE_TAG)"

# ?? 2. docker engine ????????????????????????????????????????????????????????
Write-Head 'Docker engine'
$engine = Get-EmpiEngine
if (-not $engine) {
    if ($InstallEngine) {
        Write-Step 'no engine found - setting one up in WSL'
        # Run it as its own process: a child script that calls `exit 3` does not reliably set
        # $LASTEXITCODE, and the exit code is what tells us "restart Windows, then run this again".
        $engineScript = Join-Path $PSScriptRoot 'engine-install.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $engineScript -Accept
        $code = $LASTEXITCODE
        if ($code -eq 3) {
            Write-Host ''
            Write-Host 'Windows has to restart once before the engine can finish.' -ForegroundColor Yellow
            Write-Host 'Restart the laptop, then run Install.cmd again.' -ForegroundColor Yellow
            Write-Host ''
            exit 3
        }
        if ($code -ne 0) { exit 1 }
        $engine = Get-EmpiEngine -Refresh
    }
}
if (-not $engine) {
    Write-Bad 'no Docker engine is running on this machine'
    Write-Note 'Two ways forward, both in docs\01-install-windows.md:'
    Write-Note '  a) run  Install.cmd -InstallEngine   in a window started with "Run as administrator"'
    Write-Note '  b) install Docker Desktop from https://www.docker.com/products/docker-desktop/, then run Install.cmd again'
    exit 1
}
Write-Ok (Show-Engine)

# ?? 3. machine check ????????????????????????????????????????????????????????
Write-Head 'Machine check'
$doctorOut = & (Join-Path $PSScriptRoot 'doctor.ps1') -Quiet 2>&1
$doctorExit = $LASTEXITCODE
$doctorOut | ForEach-Object { Write-Host "$_" }
if ($doctorExit -eq 2) { exit 2 }
if ($doctorExit -ne 0 -and -not $Force) {
    Write-Host ''
    Write-Bad 'the machine check found a problem - nothing has been started'
    Write-Note 'Fix it, then run Install.cmd again. To ignore it anyway: Install.cmd -Force'
    exit 1
}

# ?? 4. image + stack ????????????????????????????????????????????????????????
if (-not $SkipPull) {
    Write-Head 'Downloading the stack image'
    Write-Note $image
    $pullOut = Invoke-Compose -Arguments @('pull') -AllowFailure 2>&1
    if ($LASTEXITCODE -ne 0) {
        $pullOut | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        Write-Bad 'the image could not be downloaded'
        Write-Note 'If it says "unauthorized", the image is not public yet or this machine is offline.'
        exit 1
    }
    Write-Ok 'image downloaded'
}

Write-Head 'Starting the stack'
Write-Note 'the first start takes 5 to 15 minutes (the database and the site are created now)'
$upOut = Invoke-Compose -Arguments @('up', '-d') -AllowFailure 2>&1
if ($LASTEXITCODE -ne 0) {
    $upOut | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    Write-Bad 'docker compose up failed'
    Write-Note 'Run scripts\status.cmd and read the last lines of:  scripts\logs.cmd create-site'
    exit 1
}

$pingUrl = "http://127.0.0.1:$httpPort/api/method/ping"
Write-Host ''
if (Wait-ForHttp -Url $pingUrl -TimeoutSeconds 900 -Label 'ERPNext') {
    Write-Host ''
    Write-Ok 'ERPNext is answering'
} else {
    Write-Host ''
    Write-Bad 'ERPNext did not answer within 15 minutes'
    Write-Note 'The stack is still running. See docs\03-troubleshooting.md ("first start is slow").'
    Write-Note 'Quick look: scripts\logs.cmd create-site'
    exit 1
}

# ?? 5. report ???????????????????????????????????????????????????????????????
Write-Host ''
Write-Host '  EmpiFlow is ready.' -ForegroundColor Green
Write-Host ''
Write-Host ("  ERPNext    http://127.0.0.1:{0}" -f $httpPort) -ForegroundColor White
Write-Host ("             user: Administrator   password: (ADMIN_PASSWORD in .env)" -f $httpPort) -ForegroundColor DarkGray
Write-Host ("  Metabase   http://127.0.0.1:{0}" -f $mbPort) -ForegroundColor White
Write-Host ''
Write-Host '  Stop it:   scripts\stop.cmd        Start it again: scripts\start.cmd' -ForegroundColor DarkGray
Write-Host '  Next:      docs\02-first-steps.md  (the setup wizard, where HR is, connecting Metabase)' -ForegroundColor DarkGray
Write-Host ''
if (-not $NoBrowser) { Open-Browser "http://127.0.0.1:$httpPort" }
exit 0
