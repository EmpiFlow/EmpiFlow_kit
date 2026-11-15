# EmpiFlow kit - install. One double-click: check the machine, create .env, set up WSL 2 + Docker if
# they are missing, download the image, start the stack, and create the desktop shortcuts.
#
#   Install.cmd                  the normal, guided way (asks five questions, one UAC prompt when needed)
#   Install.cmd -Defaults        accept every default, ask nothing (unattended)
#   Install.cmd -Force           continue even when the machine check reports a problem
#   Install.cmd -NoBrowser       do not open ERPNext at the end
#   Install.cmd -SkipPull        use the image already on the machine
#   Install.cmd -InstallEngine   accepted for compatibility; engine setup is automatic now
#   Install.cmd -WslRoot D:\EmpiFlow\wsl   put the WSL disk on another drive on the FIRST install
#
# The long work runs in a hidden worker process that writes install-log.txt; this window tails that
# log and prints a heartbeat every 10 seconds (D-021, engine-quirks.md section 8).
#
# Exit codes: 0 = installed and answering   1 = stopped, nothing half-done   2 = unsupported OS
#             3 = restart Windows, then run again   10 = continued in the administrator window
[CmdletBinding()]
param(
    [switch]$Defaults,
    [switch]$Force,
    [switch]$InstallEngine,
    [switch]$NoBrowser,
    [switch]$SkipPull,
    [switch]$NoShortcuts,
    [switch]$Elevated,
    [switch]$Worker,
    [string]$LogPath = '',
    [string]$WslRoot = ''
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$refusal = 'EmpiFlow_kit is not configured to install on this operating system. This kit supports Windows 10 and Windows 11 only. Nothing has been changed on this machine.'

# ?? helpers ??????????????????????????????????????????????????????????????????
function Complete-Worker {
    param([int]$Code)
    Write-EmpiLog ("[empi] DONE {0}" -f $Code)
    exit $Code
}

function Get-Setting {
    param([hashtable]$Table, [string]$Name, [string]$Default = '')
    if ($Table.ContainsKey($Name) -and $Table[$Name] -ne '') { return $Table[$Name] }
    return $Default
}

function Invoke-EmpiInstallLauncher {
    $script:LauncherCode = 1
    if ($WslRoot -and (Test-Path $script:EnvFile)) {
        Write-Warn '-WslRoot is only used on the first install; .env already exists, so WSL_ROOT in .env wins.'
        $WslRoot = ''
    }
    Write-Plain ''
    Write-Plain 'EmpiFlow kit - installer'
    Write-Plain 'ERPNext 15 + Frappe HR + Metabase, on this laptop only.'
    if ($InstallEngine) {
        Write-Note '-InstallEngine is no longer needed: the installer sets up WSL and Docker automatically.'
    }
    Write-Plain ''

    if ($Elevated -and -not (Test-IsElevated)) {
        Write-Bad 'this window is not elevated - close it and run Install.cmd normally'
        $script:LauncherCode = 1
        return
    }
    if ($Elevated) {
        try { $Host.UI.RawUI.WindowTitle = 'EmpiFlow installer (administrator)' } catch { }
    }

    # 1. doctor first. It is read-only, and a failure here means nothing has been changed yet.
    Write-Head 'Machine check'
    & (Join-Path $PSScriptRoot 'doctor.ps1') -WslRoot $WslRoot
    $doctorExit = $LASTEXITCODE
    if ($doctorExit -eq 2) { $script:LauncherCode = 2; return }
    if ($doctorExit -ne 0 -and -not $Force) {
        Write-Plain ''
        Write-Bad 'the machine check found a problem - nothing has been changed'
        Write-Note 'Fix the problem above, then run Install.cmd again. To ignore it anyway: Install.cmd -Force'
        $script:LauncherCode = 1
        return
    }

    # 2. settings. Written before the elevation handoff so the elevated window asks nothing twice.
    Write-Head 'Settings'
    $needEnv = -not (Test-Path $script:EnvFile)
    $values = @{
        SITE_NAME      = 'empiflow.local'
        ADMIN_PASSWORD = 'admin'
        DB_PASSWORD    = 'admin'
        MB_RO_PASSWORD = 'metabase_ro'
        HTTP_PORT      = '8080'
        METABASE_PORT  = '3000'
        EMPI_IMAGE     = 'ghcr.io/empiflow/empiflow-kit-erpnext'
        EMPI_IMAGE_TAG = 'v1.0.0'
        WSL_ROOT       = (Join-Path $env:ProgramData 'EmpiFlow\wsl')
    }
    if ($WslRoot) { $values.WSL_ROOT = $WslRoot }

    if ($needEnv) {
        if ($Defaults) {
            Write-Step 'using the defaults (no questions asked)'
        } else {
            Write-Note 'Press Enter to accept the value in [brackets].'
            Write-Plain ''
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
            Write-Bad ("site name '{0}' is not valid - use letters, digits, dots and dashes" -f $values.SITE_NAME)
            $script:LauncherCode = 1
            return
        }
        foreach ($k in @('HTTP_PORT', 'METABASE_PORT')) {
            $n = 0
            if (-not [int]::TryParse($values[$k], [ref]$n) -or $n -lt 1024 -or $n -gt 65535) {
                Write-Bad ("{0} must be a number between 1024 and 65535" -f $k)
                $script:LauncherCode = 1
                return
            }
        }
        if (-not $values.ADMIN_PASSWORD) {
            Write-Bad 'the admin password cannot be empty'
            $script:LauncherCode = 1
            return
        }
        Write-EnvFile -Values $values
        Write-Ok "wrote $script:EnvFile"
    } else {
        $cur = Read-EnvFile
        foreach ($k in $cur.Keys) { $values[$k] = $cur[$k] }
        Write-Ok ".env already exists - keeping it (site $($values.SITE_NAME))"
    }

    # 3. engine. Try an installed-but-stopped engine without admin first; only a missing engine needs UAC.
    Write-Head 'Docker engine'
    $engine = Get-EmpiEngine
    if (-not $engine) {
        Write-Step 'no engine is answering - checking whether one is installed but stopped'
        $engine = Start-EmpiEngine
    }
    if ($engine) {
        Write-Ok (Show-Engine)
    } elseif (-not (Test-IsElevated)) {
        Write-Plain ''
        Write-Warn 'setting up WSL and Docker needs administrator rights once'
        Write-Note 'Windows will ask you to allow it. Click Yes, then continue in the new window.'
        $flags = @('-Elevated')
        if ($Defaults) { $flags += '-Defaults' }
        if ($Force) { $flags += '-Force' }
        if ($NoBrowser) { $flags += '-NoBrowser' }
        if ($SkipPull) { $flags += '-SkipPull' }
        if ($NoShortcuts) { $flags += '-NoShortcuts' }
        if ($WslRoot) { $flags += '-WslRoot'; $flags += ('"{0}"' -f $WslRoot) }
        $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $PSCommandPath, ($flags -join ' ')
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arg -WorkingDirectory $script:KitRoot | Out-Null
            Write-Note 'continuing in the administrator window...'
            $script:LauncherCode = 10
            return
        } catch {
            Write-Bad 'administrator rights were refused - no engine or stack was installed'
            Write-Note ("The settings file is still at " + $script:EnvFile)
            $script:LauncherCode = 1
            return
        }
    } else {
        Write-Ok 'this window is elevated - the engine can be installed from here'
    }

    # 4. hidden worker + live log window.
    Write-Head 'Installation'
    Write-Note 'the long steps run in the background; this window shows their progress'
    $log = Join-Path $script:KitRoot 'install-log.txt'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue

    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $wtokens = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath),
                 '-Worker', '-LogPath', ('"{0}"' -f $log))
    if ($Force) { $wtokens += '-Force' }
    if ($NoBrowser) { $wtokens += '-NoBrowser' }
    if ($SkipPull) { $wtokens += '-SkipPull' }
    if ($NoShortcuts) { $wtokens += '-NoShortcuts' }
    if ($WslRoot) { $wtokens += '-WslRoot'; $wtokens += ('"{0}"' -f $WslRoot) }

    $worker = $null
    try {
        $worker = Start-Process -FilePath $powershell -ArgumentList ($wtokens -join ' ') `
            -WorkingDirectory $script:KitRoot -WindowStyle Hidden -PassThru
    } catch {
        Write-Bad ('the installer worker could not be started: ' + $_.Exception.Message)
        $script:LauncherCode = 1
        return
    }
    if (-not $worker) {
        Write-Bad 'the installer worker could not be started'
        $script:LauncherCode = 1
        return
    }

    $code = Show-LiveLog -Path $log -WorkerPid $worker.Id -TimeoutMinutes 60 -Title 'EmpiFlow installer - progress'
    Write-Plain ''
    switch ($code) {
        0 {
            Write-Ok 'installation finished'
            Write-Ok ('ERPNext   http://127.0.0.1:{0}' -f (Get-Setting $values 'HTTP_PORT' '8080'))
            Write-Ok ('Metabase  http://127.0.0.1:{0}' -f (Get-Setting $values 'METABASE_PORT' '3000'))
            Write-Note ("full log: " + $log)
            $script:LauncherCode = 0
        }
        3 {
            Write-Warn 'Windows has to restart once before the engine can finish.'
            Write-Note 'Restart the laptop, then double-click Install.cmd again. It continues from here.'
            Write-Note ("full log: " + $log)
            $script:LauncherCode = 3
        }
        -2 {
            Write-Bad 'the installer did not finish within the time limit'
            Write-Note ("It may still be running. Watch the log: Get-Content -Wait `"$log`"")
            $script:LauncherCode = 1
        }
        default {
            Write-Bad 'the installation stopped before it finished'
            Write-Note ("The reason is in the log above, and in " + $log)
            $script:LauncherCode = 1
        }
    }
}

function Invoke-EmpiInstallWorker {
    Write-Plain ''
    Write-Plain 'EmpiFlow kit - installer (background worker)'
    Write-Plain ("log: " + $script:LogFile)
    Write-Plain ''

    $values = Read-EnvFile
    if ($values.Count -eq 0) {
        Write-Bad 'no .env file was found - run Install.cmd from the kit folder'
        Complete-Worker 1
    }
    $httpPort = [int](Get-Setting $values 'HTTP_PORT' '8080')
    $mbPort   = [int](Get-Setting $values 'METABASE_PORT' '3000')
    $image    = ('{0}:{1}' -f (Get-Setting $values 'EMPI_IMAGE' 'ghcr.io/empiflow/empiflow-kit-erpnext'),
                            (Get-Setting $values 'EMPI_IMAGE_TAG' 'v1.0.0'))

    # 1. engine: start an installed one, or install WSL 2 + Docker Engine.
    Write-Head 'Docker engine'
    $engine = Get-EmpiEngine
    if (-not $engine) {
        Write-Step 'no engine is running - trying to start an installed one'
        $engine = Start-EmpiEngine
    }
    if (-not $engine) {
        if (-not (Test-IsElevated)) {
            Write-Bad 'administrator rights are required to install WSL and Docker'
            Write-Note 'Close this and run Install.cmd again from a normal window; it asks for permission once.'
            Complete-Worker 1
        }
        $wslRoot = Get-WslRootPath -Override $WslRoot
        if (-not $wslRoot.Valid) {
            Write-Bad ('the WSL disk location is not usable: ' + $wslRoot.Reason)
            Write-Note 'Set WSL_ROOT in .env to a folder on a drive that exists, then run Install.cmd again.'
            Complete-Worker 1
        }
        Write-Step 'setting up WSL 2 and the Docker engine (this takes several minutes)'
        Write-Note ('the WSL disk will be created at: ' + $wslRoot.Path)
        & (Join-Path $PSScriptRoot 'engine-install.ps1') -Accept -LogPath $LogPath -WslRoot $WslRoot
        $code = $LASTEXITCODE
        if ($code -eq 3) {
            Write-Plain ''
            Write-Warn 'Windows has to restart once before the engine can finish.'
            Write-Note 'Restart the laptop, then double-click Install.cmd again. It continues from here.'
            Complete-Worker 3
        }
        if ($code -ne 0) {
            Write-Bad 'the engine setup failed - the reason is in the lines above'
            Complete-Worker 1
        }
        $engine = Get-EmpiEngine -Refresh
        if (-not $engine) {
            Write-Bad 'the engine still does not answer after setup'
            Complete-Worker 1
        }
    }
    Write-Ok (Show-Engine)

    # 2. doctor again, now that an engine exists: catches ports, disk and compose problems before the pull.
    Write-Head 'Machine check'
    & (Join-Path $PSScriptRoot 'doctor.ps1') -Quiet -LogPath $LogPath -WslRoot $WslRoot
    $doctorExit = $LASTEXITCODE
    if ($doctorExit -ne 0 -and -not $Force) {
        Write-Plain ''
        Write-Bad 'the machine check found a problem - the stack was not started'
        Write-Note 'Fix it, then run Install.cmd again. To ignore it anyway: Install.cmd -Force'
        Complete-Worker 1
    }

    # 3. image.
    if (-not $SkipPull) {
        Write-Head 'Downloading the stack image'
        Write-Note $image
        Write-Note 'about 1.5 GB the first time; this can take several minutes'
        Invoke-Compose -Arguments @('pull') -AllowFailure | ForEach-Object { Write-Detail "$_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Bad 'the image could not be downloaded'
            Write-Note 'If it says "unauthorized", the image is not public yet or this machine is offline.'
            Complete-Worker 1
        }
        Write-Ok 'image downloaded'
    } else {
        Write-Step 'skipping the image download (-SkipPull)'
    }

    # 4. stack.
    Write-Head 'Starting the stack'
    Write-Note 'the first start takes 5 to 15 minutes; the database and the site are created now'
    Invoke-Compose -Arguments @('up', '-d') -AllowFailure | ForEach-Object { Write-Detail "$_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Bad 'docker compose up failed'
        Write-Note 'Run scripts\status.cmd and read: scripts\logs.cmd create-site'
        Complete-Worker 1
    }

    $pingUrl = "http://127.0.0.1:$httpPort/api/method/ping"
    Write-Plain ''
    if (-not (Wait-ForHttp -Url $pingUrl -TimeoutSeconds 900 -Label 'ERPNext')) {
        Write-Plain ''
        Write-Bad 'ERPNext did not answer within 15 minutes'
        Write-Note 'The stack is still running. See docs\03-troubleshooting.md ("first start is slow").'
        Write-Note 'Quick look: scripts\logs.cmd create-site'
        Complete-Worker 1
    }
    Write-Plain ''
    Write-Ok 'ERPNext is answering'

    # 5. shortcuts. One folder with start, stop and the two pages (D-022).
    if (-not $NoShortcuts) {
        Write-Head 'Shortcuts'
        & (Join-Path $PSScriptRoot 'shortcuts.ps1') -Quiet -LogPath $LogPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'the shortcuts could not be created - run scripts\shortcuts.cmd later'
        } else {
            Write-Ok 'desktop and Start-menu folder "EmpiFlow" created'
        }
    }

    # 6. report.
    Write-Plain ''
    Write-Ok 'EmpiFlow is ready.'
    Write-Plain ''
    Write-Plain ('  ERPNext    http://127.0.0.1:{0}' -f $httpPort)
    Write-Plain ('             user: Administrator   password: (ADMIN_PASSWORD in .env)')
    Write-Plain ('  Metabase   http://127.0.0.1:{0}' -f $mbPort)
    Write-Plain ''
    Write-Plain '  Stop it:   scripts\stop.cmd        Start it again: scripts\start.cmd'
    Write-Plain '  Next:      docs\02-first-steps.md  (the setup wizard, where HR is, connecting Metabase)'
    Write-Plain ''
    if (-not $NoBrowser) {
        Open-Browser "http://127.0.0.1:$httpPort"
        Write-Note 'opening ERPNext in the browser'
    }
    Complete-Worker 0
}

# ?? dispatch ?????????????????????????????????????????????????????????????????
if (-not (Test-IsWindowsOS)) {
    Write-Host ''
    Write-Host $refusal -ForegroundColor Red
    Write-Host ''
    exit 2
}

if ($Worker) {
    if (-not $LogPath) { $LogPath = Join-Path $script:KitRoot 'install-log.txt' }
    Set-EmpiLog -Path $LogPath
    trap {
        Write-Bad ('unexpected error: ' + $_.Exception.Message)
        Write-Note ("The full log is at " + $LogPath)
        Write-EmpiLog '[empi] DONE 1'
        exit 1
    }
    Invoke-EmpiInstallWorker
    exit 1
}

Invoke-EmpiInstallLauncher

# The non-elevated .cmd hands over with code 10 and closes. The elevated continuation was started
# directly by PowerShell, so it has no .cmd wrapper to pause for it: keep its console open.
if ($Elevated -and $script:LauncherCode -ne 10 -and [Environment]::UserInteractive) {
    Write-Plain ''
    Write-Plain 'Press Enter to close this window.'
    [void](Read-Host)
}
exit $script:LauncherCode
