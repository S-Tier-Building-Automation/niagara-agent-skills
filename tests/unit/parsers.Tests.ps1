BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'parsers.ps1')
    $script:fx = Join-Path $PSScriptRoot '..' 'fixtures'
    function Get-Fixture([string] $rel) { Get-Content -LiteralPath (Join-Path $script:fx $rel) }
}

Describe 'Split-NiagaraOutput' {
    It 'separates NRE INFO chatter from payload' {
        $r = Split-NiagaraOutput -Lines (Get-Fixture 'plat/4.15.3/liststations.txt')
        $r.noise.Count | Should -Be 2
        $r.payload[0] | Should -Match '^Name\s+Status'
    }
    It 'tolerates empty input' {
        $r = Split-NiagaraOutput -Lines @()
        @($r.payload).Count | Should -Be 0
    }
}

Describe 'ConvertFrom-PlatListStations' {
    It 'parses the 4.15 station table with column offsets' {
        $s = @(ConvertFrom-PlatListStations -Lines (Get-Fixture 'plat/4.15.3/liststations.txt'))
        $s.Count | Should -Be 3
        $s[0].name | Should -Be 'demo'
        $s[0].status | Should -Be 'running'
        $s[0].httpPort | Should -Be 80
        $s[0].foxPort | Should -BeNullOrEmpty
        $s[0].autoStart | Should -BeFalse
        $s[0].restartOnFailure | Should -BeTrue
        $s[1].rawStatus | Should -Be 'idle'
        $s[1].status | Should -Be 'stopped'
        $s[2].rawStatus | Should -Be 'disabled'
        $s[2].restartOnFailure | Should -BeFalse
    }
    It 'returns an empty list for a header-only table' {
        @(ConvertFrom-PlatListStations -Lines (Get-Fixture 'plat/4.15.3/liststations-empty.txt')).Count | Should -Be 0
    }
    It 'maps unknown status words to unknown' {
        $lines = @('Name   Status    Fox Port HTTP Port Auto-Start Restart on Failure', '------ --------- -------- --------- ---------- ------------------', 'x      starting  n/a      n/a       true       true')
        $s = @(ConvertFrom-PlatListStations -Lines $lines)
        $s[0].status | Should -Be 'unknown'
        $s[0].autoStart | Should -BeTrue
    }
}

Describe 'ConvertFrom-PlatKeyValue' {
    It 'parses plat details into a map' {
        $d = ConvertFrom-PlatKeyValue -Lines (Get-Fixture 'plat/4.15.3/details.txt')
        $d['Daemon Version'] | Should -Be '4.15.3.28'
        $d['Daemon HTTPS Port'] | Should -Be '5011'
        $d['System Home'] | Should -Be 'C:\Niagara\Niagara-4.15.3.28'
        $d.Keys | Should -Not -Contain 'INFO [10:12:01 07-Oct-26 UTC][sys.registry] Loading registry...'
    }
}

Describe 'ConvertFrom-NreModules' {
    It 'parses nre -modules output' {
        $m = @(ConvertFrom-NreModules -Lines (Get-Fixture 'nre/4.15.3/modules.txt'))
        $m.Count | Should -Be 4
        $m[0].name | Should -Be 'baja'
        $m[0].version | Should -Be '4.15.3.28'
        $m[0].vendor | Should -Be 'Tridium'
        $m[1].name | Should -Be 'bajaScript-rt'
    }
}

Describe 'ConvertFrom-PlatUsage' {
    It 'extracts advertised flags' {
        $f = ConvertFrom-PlatUsage -Lines (Get-Fixture 'plat/4.15.3/watchstation-usage.txt')
        $f | Should -Contain '-follow'
        $f | Should -Contain '-f'
        $f | Should -Contain '-secure'
        $f | Should -Not -Contain '-ood'
    }
    It 'sees -ood only on moduleinstall' {
        (ConvertFrom-PlatUsage -Lines (Get-Fixture 'plat/4.15.3/moduleinstall-usage.txt')) | Should -Contain '-ood'
        (ConvertFrom-PlatUsage -Lines (Get-Fixture 'plat/4.15.3/liststations-usage.txt')) | Should -Not -Contain '-ood'
    }
}
