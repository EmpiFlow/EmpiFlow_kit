# EmpiFlow kit - start the stack automatically when this Windows user logs in.
#   scripts\autostart.cmd            create the task
#   scripts\autostart.cmd -Remove    remove it again (proven reversible)
[CmdletBinding()]
param([switch]$Remove)

. (Join-Path $PSScriptRoot 'lib.ps1')

$taskName = 'EmpiFlow kit'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($Remove) {
    if (-not $existing) {
        Write-Host 'Autostart was not set - nothing to remove.' -ForegroundColor Yellow
        exit 0
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    $still = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($still) { Write-Bad 'the task is still there'; exit 1 }
    Write-Host 'Autostart removed - EmpiFlow will no longer start at logon.' -ForegroundColor Green
    exit 0
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$start = Join-Path $PSScriptRoot 'start.ps1'
$action = New-ScheduledTaskAction -Execute $powershell `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -NoBrowser' -f $start)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'Starts the EmpiFlow kit stack (ERPNext + Frappe HR + Metabase) at logon.' -Force | Out-Null

$check = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $check) { Write-Bad 'the task was not registered'; exit 1 }
Write-Host ''
Write-Ok ('autostart task registered: ' + $taskName)
Write-Note 'It runs scripts\start.ps1, hidden, when you log in. Undo with: scripts\autostart.cmd -Remove'
exit 0
