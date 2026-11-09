BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'plat.ps1')
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("nas-homes-" + [guid]::NewGuid().ToString('N'))
    function New-FakeInstall([string] $name, [string] $bajaVersion) {
        $dir = Join-Path $script:root $name
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'bin'), (Join-Path $dir 'modules') | Out-Null
        Set-Content -LiteralPath (Join-Path (Join-Path $dir 'bin') 'nre') -Value ''
        if ($bajaVersion) {
            $zip = [System.IO.Compression.ZipFile]::Open((Join-Path (Join-Path $dir 'modules') 'baja.jar'), 'Create')
            try {
                $w = New-Object System.IO.StreamWriter($zip.CreateEntry('META-INF/module.xml').Open())
                try { $w.Write("<module name=`"baja`" vendor=`"Tridium`" vendorVersion=`"$bajaVersion`"/>") } finally { $w.Dispose() }
            } finally { $zip.Dispose() }
        }
        return $dir
    }
    $script:n4153 = New-FakeInstall 'Niagara-4.15.3.28' '4.15.3.28'
    $script:vykon = New-FakeInstall 'Vykon-4.15' '4.15.1.16'
    $script:n414 = New-FakeInstall 'Niagara-4.14.1.16' $null
    $script:odd = New-FakeInstall 'Brand' $null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:root 'NotAnInstall') | Out-Null
    $script:cfg = [pscustomobject]@{ niagaraSearchRoots = @($script:root); hosts = @{} }
    function Find-Fake { @(Find-NiagaraHomes -Config $script:cfg | Where-Object { $_.path -like "*$(Split-Path -Leaf $script:root)*" }) }
}
AfterAll { Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Find-NiagaraHomes' {
    It 'finds every install under a search root, newest first, unknown versions last' {
        $h = Find-Fake
        @($h | ForEach-Object { Split-Path -Leaf $_.path }) | Should -Be @('Niagara-4.15.3.28', 'Vykon-4.15', 'Niagara-4.14.1.16', 'Brand')
    }
    It 'reads the version from baja.jar first, then the folder name' {
        $h = Find-Fake
        $h[0].version | Should -Be '4.15.3.28'
        $h[0].versionSource | Should -Be 'baja.jar'
        $h[1].version | Should -Be '4.15.1.16'
        $h[2].version | Should -Be '4.14.1.16'
        $h[2].versionSource | Should -Be 'folder name'
        $h[3].version | Should -BeNullOrEmpty
    }
    It 'points at each install''s own nre' {
        $h = Find-Fake
        Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $h[1].nre)) | Should -Be 'Vykon-4.15'
    }
    It 'lists an install named in the config once' {
        $cfg = [pscustomobject]@{ niagaraSearchRoots = @($script:root); niagaraHomes = @($script:vykon); hosts = @{} }
        @(Find-NiagaraHomes -Config $cfg | Where-Object { (Split-Path -Leaf $_.path) -eq 'Vykon-4.15' }).Count | Should -Be 1
    }
}

Describe 'Select-NiagaraHome' {
    BeforeAll { $script:h = Find-Fake }
    It 'picks the newest install of a named version' {
        (Split-Path -Leaf (Select-NiagaraHome -Homes $script:h -Version '4.15').path) | Should -Be 'Niagara-4.15.3.28'
        (Split-Path -Leaf (Select-NiagaraHome -Homes $script:h -Version '4.15.1').path) | Should -Be 'Vykon-4.15'
        (Split-Path -Leaf (Select-NiagaraHome -Homes $script:h -Version '4.14').path) | Should -Be 'Niagara-4.14.1.16'
    }
    It 'does not read 4.1 as a prefix of 4.15' {
        { Select-NiagaraHome -Homes $script:h -Version '4.1' } | Should -Throw '*NoMatchingNiagaraHome*'
    }
    It 'matches a target host by major.minor, preferring the same build' {
        $p = Select-NiagaraHome -Homes $script:h -MatchVersion '4.15.1.16'
        Split-Path -Leaf $p.path | Should -Be 'Vykon-4.15'
        $p.match | Should -Be 'match'
        $q = Select-NiagaraHome -Homes $script:h -MatchVersion '4.15.2.5'
        Split-Path -Leaf $q.path | Should -Be 'Niagara-4.15.3.28'
        $q.match | Should -Be 'patch-differs'
    }
    It 'refuses a target whose major.minor is not installed' {
        { Select-NiagaraHome -Homes $script:h -MatchVersion '4.10.0.1' } | Should -Throw '*NoMatchingNiagaraHome*4.10*'
    }
    It 'a named path wins and must be an install' {
        (Split-Path -Leaf (Select-NiagaraHome -Homes $script:h -Path $script:odd -Version '4.15').path) | Should -Be 'Brand'
        { Select-NiagaraHome -Homes $script:h -Path (Join-Path $script:root 'NotAnInstall') } | Should -Throw '*NoNiagaraHome*'
    }
    It 'uses the configured niagaraHome, else the newest install' {
        (Split-Path -Leaf (Select-NiagaraHome -Homes $script:h -Preferred $script:n414).path) | Should -Be 'Niagara-4.14.1.16'
        $p = Select-NiagaraHome -Homes $script:h
        Split-Path -Leaf $p.path | Should -Be 'Niagara-4.15.3.28'
        $p.reason | Should -Match 'newest of 4'
    }
    It 'throws when nothing is installed' {
        { Select-NiagaraHome -Homes @() } | Should -Throw '*NoNiagaraHome*'
    }
}

Describe 'Use-NiagaraHome' {
    It 'returns a copy and leaves the host record alone' {
        $hostRec = [pscustomobject]@{ alias = 'x'; niagaraHome = 'C:\old' }
        $c = Use-NiagaraHome -HostInfo $hostRec -Path 'C:\new'
        $c.niagaraHome | Should -Be 'C:\new'
        $hostRec.niagaraHome | Should -Be 'C:\old'
    }
}
