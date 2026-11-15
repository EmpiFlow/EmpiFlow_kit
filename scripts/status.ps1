# EmpiFlow kit - what is running right now.
[CmdletBinding()]
param([switch]$Json)

. (Join-Path $PSScriptRoot 'lib.ps1')

$httpPort = [int](Get-EnvValue 'HTTP_PORT' '8080')
$mbPort   = [int](Get-EnvValue 'METABASE_PORT' '3000')
$engine   = Get-EmpiEngine

$state = @{}
if ($engine) { try { $state = Get-ComposeServiceState } catch { } }

$erp = 'offline'
$mb  = 'offline'
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$httpPort/api/method/ping" -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200) { $erp = 'ok' }
} catch { }
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$mbPort/api/health" -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200) { $mb = 'ok' }
} catch { }

if ($Json) {
    [pscustomobject]@{
        engine   = $(if ($engine) { $engine.Kind } else { $null })
        version  = $(if ($engine) { $engine.Version } else { $null })
        services = $state
        erpnext  = $erp
        metabase = $mb
        httpPort = $httpPort
        mbPort   = $mbPort
    } | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host ''
if (-not $engine) {
    Write-Host 'EmpiFlow is not running (no Docker engine found).' -ForegroundColor Yellow
    Write-Host 'Install it with Install.cmd, or check the machine with scripts\doctor.cmd.' -ForegroundColor DarkGray
    exit 1
}
Write-Host ('Docker: ' + (Show-Engine)) -ForegroundColor DarkGray
Write-Host ''

if ($state.Count -eq 0) {
    Write-Host 'The stack has not been installed yet. Run Install.cmd.' -ForegroundColor Yellow
    exit 1
}

Write-Host ('{0,-12} {1}' -f 'SERVICE', 'STATE') -ForegroundColor White
foreach ($k in ($state.Keys | Sort-Object)) {
    $s = $state[$k]
    $color = 'Yellow'
    if ($s -eq 'running') { $color = 'Green' }
    if ($s -eq 'exited')  { $color = 'DarkGray' }
    Write-Host ('{0,-12} {1}' -f $k, $s) -ForegroundColor $color
}

Write-Host ''
if ($erp -eq 'ok') { Write-Ok ('ERPNext   http://127.0.0.1:{0}' -f $httpPort) }
else { Write-Warn ('ERPNext   http://127.0.0.1:{0}  (not answering yet)' -f $httpPort) }
if ($mb -eq 'ok') { Write-Ok ('Metabase  http://127.0.0.1:{0}' -f $mbPort) }
else { Write-Warn ('Metabase  http://127.0.0.1:{0}  (not answering yet)' -f $mbPort) }
Write-Host ''
exit 0
