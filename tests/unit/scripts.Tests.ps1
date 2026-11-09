BeforeAll {
    $script:root = Join-Path $PSScriptRoot '..' '..'
    $script:tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("nas-scripts-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:tmpHome | Out-Null
    $script:cfgPath = Join-Path $script:tmpHome 'config.json'
    @{ niagaraHome = $script:tmpHome; hosts = @{ local = @{ hostord = 'ip:localhost'; allow = @('read', 'station', 'install', 'host'); stations = @('demo') }; ro = @{ hostord = 'ip:localhost'; allow = @('read') }; jace = @{ hostord = 'ip:192.0.2.10'; port = 5011; secure = $true; allow = @('read', 'station', 'install'); stations = @('bench') } } } |
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

Describe 'commission-jace' {
    BeforeAll {
        $script:jar = Join-Path $script:tmpHome 'STierAPI-rt.jar'
        Set-Content -LiteralPath $script:jar -Value 'not a real jar'
    }
    It 'exits 3 without -Confirmed' {
        $r = Invoke-Script 'commission-jace.ps1' @('-HostAlias', 'jace', '-Jar', $script:jar, '-ConfigPath', $script:cfgPath, '-Json')
        $r.exit | Should -Be 3
        $r.result.needsConfirm | Should -BeTrue
    }
    It 'refuses a host that is this machine' {
        $r = Invoke-Script 'commission-jace.ps1' @('-HostAlias', 'local', '-Jar', $script:jar, '-ConfigPath', $script:cfgPath, '-DryRun', '-SkipSignatureCheck', '-Json')
        $r.exit | Should -Be 2
    }
    It 'refuses a station outside the allowlist' {
        $r = Invoke-Script 'commission-jace.ps1' @('-HostAlias', 'jace', '-Jar', $script:jar, '-Station', 'other', '-ConfigPath', $script:cfgPath, '-DryRun', '-SkipSignatureCheck', '-Json')
        $r.exit | Should -Be 4
    }
    It 'exits 6 for a missing jar' {
        $r = Invoke-Script 'commission-jace.ps1' @('-HostAlias', 'jace', '-Jar', (Join-Path $script:tmpHome 'Missing-rt.jar'), '-ConfigPath', $script:cfgPath, '-DryRun', '-Json')
        $r.exit | Should -Be 6
    }
    It 'dry run lists every step with the password masked and changes nothing' {
        $r = Invoke-Script 'commission-jace.ps1' @('-HostAlias', 'jace', '-Jar', $script:jar, '-Station', 'bench', '-ConfigPath', $script:cfgPath, '-DryRun', '-SkipSignatureCheck', '-Json')
        $r.exit | Should -Be 0
        $r.result.dryRun | Should -BeTrue
        # The test JACE (192.0.2.10) is never reachable, so the plan must not claim to be clean.
        $r.result.ok | Should -BeFalse
        ($r.result.plan.unverified -join "`n") | Should -Match 'JACE not read'
        ($r.result.plan.unverified -join "`n") | Should -Match 'versions not compared'
        ($r.result.plan.unverified -join "`n") | Should -Not -Match 'Signature'
        $steps = $r.result.plan.steps -join "`n"
        $steps | Should -Match 'moduleinstall .*-h:ip:192\.0\.2\.10.*STierAPI-rt'
        $steps | Should -Match '-pwd:\*{8}'
        $steps | Should -Match 'stopstation bench'
        $steps | Should -Match 'startstation bench'
        $r.result.plan.jars[0].module | Should -Be 'STierAPI-rt'
        $r.result.plan.jars[0].sha256 | Should -Match '^[0-9a-f]{64}$'
        ($r.raw -join "`n") | Should -Not -Match '-pwd:pw\b'
        Test-Path -LiteralPath (Join-Path $script:tmpHome 'modules' 'STierAPI-rt.jar') | Should -BeFalse
    }
}

Describe 'invoke-nre' {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $script:nreRoot = Join-Path $script:tmpHome 'installs'
        function New-FakeInstall([string] $name, [string] $version) {
            $dir = Join-Path $script:nreRoot $name
            New-Item -ItemType Directory -Force -Path (Join-Path $dir 'bin'), (Join-Path $dir 'modules') | Out-Null
            $nre = Join-Path (Join-Path $dir 'bin') 'nre'
            Set-Content -LiteralPath $nre -Value @('#!/bin/sh', "echo 'Niagara Runtime Environment $version'", "echo 'INFO [10:12:01 07-Oct-26 UTC][sys.registry] Loading registry...'")
            if (-not $IsWindows) { & chmod 755 $nre }
            $zip = [System.IO.Compression.ZipFile]::Open((Join-Path (Join-Path $dir 'modules') 'baja.jar'), 'Create')
            try {
                $w = New-Object System.IO.StreamWriter($zip.CreateEntry('META-INF/module.xml').Open())
                try { $w.Write("<module name=`"baja`" vendorVersion=`"$version`"/>") } finally { $w.Dispose() }
            } finally { $zip.Dispose() }
            return $dir
        }
        $script:i415 = New-FakeInstall 'Niagara-4.15.3.28' '4.15.3.28'
        $script:i414 = New-FakeInstall 'Niagara-4.14.1.16' '4.14.1.16'
        $script:nreCfg = Join-Path $script:tmpHome 'nre-config.json'
        @{ niagaraHome = $script:i415; niagaraSearchRoots = @($script:nreRoot); hosts = @{ local = @{ hostord = 'ip:localhost'; allow = @('read') }; jace = @{ hostord = 'ip:192.0.2.10'; port = 5011; secure = $true; allow = @('read') }; box = @{ hostord = 'ip:localhost'; transport = 'ssh'; ssh = 'box'; allow = @('read') } } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:nreCfg
    }
    It 'lists the installs on this machine' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-Action', 'homes', '-ConfigPath', $script:nreCfg, '-Json')
        $r.exit | Should -Be 0
        $mine = @($r.result.homes | Where-Object { $_.path -like '*installs*' })
        @($mine | ForEach-Object { $_.version }) | Should -Be @('4.15.3.28', '4.14.1.16')
    }
    It 'dry run shows the install it picked for a named version and runs nothing' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-Action', 'version', '-NiagaraVersion', '4.14', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 0
        $r.result.dryRun | Should -BeTrue
        $r.result.selected.version | Should -Be '4.14.1.16'
        $r.result.argv[-1] | Should -Be '-version'
        ($r.raw -join "`n") | Should -Not -Match 'Loading registry'
    }
    It 'uses the configured niagaraHome when nothing is named' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.result.selected.version | Should -Be '4.15.3.28'
        $r.result.selected.because | Should -Match 'config'
    }
    It 'exits 6 when no install has the version' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-NiagaraVersion', '4.13', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 6
        $r.result.error | Should -Match 'NoMatchingNiagaraHome'
    }
    It 'refuses a module pattern with other characters' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-Action', 'modules', '-ModulePattern', 'a;b', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 2
    }
    It 'refuses an ssh host' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-HostAlias', 'box', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 2
    }
    It 'matching a host outside the allowlist exits 4' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-MatchHost', 'ghost', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 4
    }
    It 'dry run of a host match says it would read the host first' {
        $r = Invoke-Script 'invoke-nre.ps1' @('-MatchHost', 'jace', '-ConfigPath', $script:nreCfg, '-DryRun', '-Json')
        $r.exit | Should -Be 0
        $r.result.target.alias | Should -Be 'jace'
        $r.result.target.read | Should -Match 'plat details'
    }
    It 'runs the picked install''s own nre' -Skip:$IsWindows {
        $r = Invoke-Script 'invoke-nre.ps1' @('-Action', 'version', '-NiagaraVersion', '4.14', '-ConfigPath', $script:nreCfg, '-Json')
        $r.exit | Should -Be 0 -Because ($r.raw -join ' | ')
        $r.result.parsed.version | Should -Be '4.14.1.16'
        $r.result.selected.path | Should -Match 'Niagara-4\.14\.1\.16'
    }
}
