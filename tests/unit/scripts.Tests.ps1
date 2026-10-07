BeforeAll {
    $script:root = Join-Path $PSScriptRoot '..' '..'
    $script:tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("nas-scripts-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:tmpHome | Out-Null
    $script:cfgPath = Join-Path $script:tmpHome 'config.json'
    @{ niagaraHome = $script:tmpHome; hosts = @{ local = @{ hostord = 'ip:localhost'; allow = @('read', 'station', 'install', 'host'); stations = @('demo') }; ro = @{ hostord = 'ip:localhost'; allow = @('read') } } } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:cfgPath
    function Invoke-Script([string] $name, [string[]] $argv) {
        $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $script:root 'scripts' $name) @argv 2>&1
        $code = $LASTEXITCODE
        $json = ($out | Where-Object { "$_" -like 'NIAGARA_AGENT_RESULT_JSON:*' } | Select-Object -Last 1)
        $obj = if ($json) { ("$json".Substring('NIAGARA_AGENT_RESULT_JSON:'.Length)) | ConvertFrom-Json } else { $null }
        return [pscustomobject]@{ exit = $code; result = $obj; raw = $out }
    }
    $env:NIAGARA_AGENT_HOME = $script:tmpHome
    $env:NIAGARA_PLAT_USER = 'ops'; $env:NIAGARA_PLAT_PASSWORD = 'pw'
}
AfterAll {
    Remove-Item -LiteralPath $script:tmpHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NIAGARA_AGENT_HOME, Env:NIAGARA_PLAT_USER, Env:NIAGARA_PLAT_PASSWORD -ErrorAction SilentlyContinue
}

Describe 'confirmation and allowlist gates' {
    It 'start-station exits 3 without -Confirmed' {
        $r = Invoke-Script 'start-station.ps1' @('-HostAlias', 'local', '-Station', 'demo', '-ConfigPath', $script:cfgPath, '-Json')
        $r.exit | Should -Be 3
        $r.result.needsConfirm | Should -BeTrue
    }
    It 'stop-station exits 4 on a read-only host' {
        $r = Invoke-Script 'stop-station.ps1' @('-HostAlias', 'ro', '-Station', 'demo', '-ConfigPath', $script:cfgPath, '-Confirmed', '-Json')
        $r.exit | Should -Be 4
    }
    It 'list-stations exits 4 for an unknown alias' {
        $r = Invoke-Script 'list-stations.ps1' @('-HostAlias', 'ghost', '-ConfigPath', $script:cfgPath, '-Json')
        $r.exit | Should -Be 4
    }
    It 'reboot-host requires -ConfirmHost to match' {
        $r = Invoke-Script 'reboot-host.ps1' @('-HostAlias', 'local', '-ConfigPath', $script:cfgPath, '-Confirmed', '-ConfirmHost', 'other', '-Json')
        $r.exit | Should -Be 2
    }
    It 'start-station -DryRun on a station outside the stations allowlist exits 4' {
        $r = Invoke-Script 'start-station.ps1' @('-HostAlias', 'local', '-Station', 'nope', '-ConfigPath', $script:cfgPath, '-DryRun', '-Json')
        $r.exit | Should -Be 4
    }
    It 'list-stations -DryRun returns a masked plan without plat installed' {
        $r = Invoke-Script 'list-stations.ps1' @('-HostAlias', 'local', '-ConfigPath', $script:cfgPath, '-DryRun', '-Json')
        $r.exit | Should -Be 0
        ($r.result.argv -join ' ') | Should -Match '-pwd:\*{8}'
        ($r.raw -join "`n") | Should -Not -Match '-pwd:pw\b'
    }
    It 'read-audit-log sees the records the gates wrote' {
        $r = Invoke-Script 'read-audit-log.ps1' @('-Days', '1', '-Status', 'NEEDS_CONFIRM', '-Json')
        $r.exit | Should -Be 0
        $r.result.count | Should -BeGreaterOrEqual 1
    }
}
