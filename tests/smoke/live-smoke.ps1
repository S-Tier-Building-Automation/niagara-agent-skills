<# .SYNOPSIS  Read-only live smoke against a configured host (optionally one restart with -AllowRestart). Needs a real Niagara install + credentials. #>
param([string] $HostAlias = 'local', [string] $Station, [switch] $AllowRestart, [string] $ConfigPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Run([string] $name, [string[]] $argv) {
    Write-Host "== $name $($argv -join ' ')"
    & pwsh -NoProfile -File (Join-Path $root 'scripts' $name) @argv
    Write-Host "   exit=$LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) { throw "$name failed" }
}
$common = @('-HostAlias', $HostAlias, '-Json'); if ($ConfigPath) { $common += @('-ConfigPath', $ConfigPath) }
Run 'inspect-host.ps1' ($common + @('-SkipDetails'))
Run 'list-stations.ps1' $common
if ($Station) {
    Run 'get-station-logs.ps1' ($common + @('-Station', $Station))
    if ($AllowRestart) { Run 'restart-station.ps1' ($common + @('-Station', $Station, '-Confirmed')) }
}
Run 'read-audit-log.ps1' @('-Days', '1', '-Json')
Write-Host 'live smoke ok'
