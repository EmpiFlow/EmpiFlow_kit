# EmpiFlow kit - the "EmpiFlow" shortcut folder (D-022).
#
#   scripts\shortcuts.cmd            create it on the Desktop and in the Start menu
#   scripts\shortcuts.cmd -Remove    remove it again
#
# Four items, in this order:
#   1 Start EmpiFlow   starts WSL + Docker + ERPNext + Metabase (scripts\start.cmd)
#   2 Stop EmpiFlow    stops the stack and the WSL engine, data is kept (scripts\stop.cmd)
#   3 ERPNext          opens http://127.0.0.1:<HTTP_PORT>
#   4 Metabase         opens http://127.0.0.1:<METABASE_PORT>
[CmdletBinding()]
param([switch]$Remove, [switch]$Quiet, [string]$LogPath = '')

. (Join-Path $PSScriptRoot 'lib.ps1')
if ($LogPath) { Set-EmpiLog -Path $LogPath }

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')

$desktopRoot = [Environment]::GetFolderPath('Desktop')
$desktop = Join-Path $desktopRoot 'EmpiFlow'
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\EmpiFlow'

$items = @(
    @{ Kind = 'cmd'; Name = '1 Start EmpiFlow'; Path = (Join-Path $PSScriptRoot 'start.cmd'); Icon = "$env:SystemRoot\System32\shell32.dll,21"; Description = 'Start WSL, Docker, ERPNext and Metabase' },
    @{ Kind = 'cmd'; Name = '2 Stop EmpiFlow';  Path = (Join-Path $PSScriptRoot 'stop.cmd');  Icon = "$env:SystemRoot\System32\shell32.dll,131"; Description = 'Stop EmpiFlow (data is kept)' },
    @{ Kind = 'url'; Name = '3 ERPNext';        Path = "http://127.0.0.1:$httpPort";          Icon = "$env:SystemRoot\System32\shell32.dll,13";  Description = 'ERPNext + Frappe HR' },
    @{ Kind = 'url'; Name = '4 Metabase';       Path = "http://127.0.0.1:$mbPort";            Icon = "$env:SystemRoot\System32\shell32.dll,17";  Description = 'Metabase dashboards' }
)

function Say-Ok { param([string]$Text) if ($Quiet) { Write-EmpiLog "  [ OK ] $Text" } else { Write-Ok $Text } }
function Say-Note { param([string]$Text) if ($Quiet) { Write-EmpiLog "         $Text" } else { Write-Note $Text } }

if ($Remove) {
    $removed = 0
    foreach ($folder in @($desktop, $startMenu)) {
        foreach ($item in $items) {
            $ext = '.lnk'
            if ($item.Kind -eq 'url') { $ext = '.url' }
            $p = Join-Path $folder ($item.Name + $ext)
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
        }
        # Migrate away from the first release: two loose .url files on the Desktop and two .lnk
        # files in the Start-menu folder.
        foreach ($legacy in @('Start EmpiFlow.lnk', 'Stop EmpiFlow.lnk')) {
            $p = Join-Path $folder $legacy
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
        }
        if (Test-Path -LiteralPath $folder) {
            $left = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue)
            if ($left.Count -eq 0) { Remove-Item -LiteralPath $folder -Force }
        }
    }
    # The first release put two loose .url files straight on the Desktop.
    foreach ($legacy in @('EmpiFlow ERPNext.url', 'EmpiFlow Metabase.url')) {
        $p = Join-Path $desktopRoot $legacy
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
    }
    # If an earlier run of this version wrote the loose items onto the Desktop root, remove those too.
    foreach ($item in $items) {
        $ext = '.lnk'
        if ($item.Kind -eq 'url') { $ext = '.url' }
        $p = Join-Path $desktopRoot ($item.Name + $ext)
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host ("EmpiFlow shortcuts removed ({0} item(s))." -f $removed) -ForegroundColor Green
    }
    exit 0
}

$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @($desktop, $startMenu)) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    foreach ($item in $items) {
        if ($item.Kind -eq 'cmd') {
            $path = Join-Path $folder ($item.Name + '.lnk')
            $shortcut = $shell.CreateShortcut($path)
            $shortcut.TargetPath = $item.Path
            $shortcut.WorkingDirectory = $script:KitRoot
            $shortcut.IconLocation = $item.Icon
            $shortcut.Description = $item.Description
            $shortcut.Save()
        } else {
            # A .url file has no IconLocation property; setting one throws and aborts the whole set.
            $path = Join-Path $folder ($item.Name + '.url')
            $shortcut = $shell.CreateShortcut($path)
            $shortcut.TargetPath = $item.Path
            $shortcut.Save()
        }
    }
}

Say-Ok ('shortcut folder created: ' + $desktop)
Say-Ok ('Start-menu folder created: ' + $startMenu)
Say-Note 'Start with item 1; item 2 stops the stack and the WSL engine (data is kept).'
Say-Note 'Undo with: scripts\shortcuts.cmd -Remove'
exit 0
