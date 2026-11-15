# EmpiFlow kit - desktop and Start-menu shortcuts.
#   scripts\shortcuts.cmd            create them
#   scripts\shortcuts.cmd -Remove    remove them again
[CmdletBinding()]
param([switch]$Remove)

. (Join-Path $PSScriptRoot 'lib.ps1')

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')

$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\EmpiFlow'

$links = @(
    @{ Name = 'EmpiFlow ERPNext';  Url = "http://127.0.0.1:$httpPort" },
    @{ Name = 'EmpiFlow Metabase'; Url = "http://127.0.0.1:$mbPort" }
)

if ($Remove) {
    $removed = 0
    foreach ($l in $links) {
        $p = Join-Path $desktop ($l.Name + '.url')
        if (Test-Path $p) { Remove-Item -LiteralPath $p -Force; $removed++ }
    }
    if (Test-Path $startMenu) { Remove-Item -LiteralPath $startMenu -Recurse -Force; $removed++ }
    Write-Host ("Shortcuts removed ({0} item(s))." -f $removed) -ForegroundColor Green
    exit 0
}

$shell = New-Object -ComObject WScript.Shell

foreach ($l in $links) {
    $path = Join-Path $desktop ($l.Name + '.url')
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $l.Url
    $shortcut.Save()
}

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null

$item = $shell.CreateShortcut((Join-Path $startMenu 'Start EmpiFlow.lnk'))
$item.TargetPath = $powershell
$item.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot 'start.ps1')
$item.WorkingDirectory = $script:KitRoot
$item.IconLocation = "$env:SystemRoot\System32\shell32.dll,21"
$item.Description = 'Start the EmpiFlow kit stack'
$item.Save()

$item = $shell.CreateShortcut((Join-Path $startMenu 'Stop EmpiFlow.lnk'))
$item.TargetPath = $powershell
$item.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $PSScriptRoot 'stop.ps1')
$item.WorkingDirectory = $script:KitRoot
$item.IconLocation = "$env:SystemRoot\System32\shell32.dll,131"
$item.Description = 'Stop the EmpiFlow kit stack (data is kept)'
$item.Save()

Write-Host ''
Write-Ok 'two desktop shortcuts created (ERPNext, Metabase)'
Write-Ok ('Start menu folder created: ' + $startMenu)
Write-Note 'Undo with: scripts\shortcuts.cmd -Remove'
exit 0
