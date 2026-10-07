BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'validators.ps1')
}

Describe 'Test-NiagaraArgument' {
    It 'accepts a plain station name' { Test-NiagaraArgument -Kind StationName -Value 'Building_A-1' | Should -BeTrue }
    It 'rejects values that look like flags' { { Test-NiagaraArgument -Kind StationName -Value '-usr:x' } | Should -Throw '*must not start with*' }
    It 'rejects whitespace in station names' { { Test-NiagaraArgument -Kind StationName -Value 'a b' } | Should -Throw }
    It 'rejects double quotes' { { Test-NiagaraArgument -Kind Message -Value 'save"' } | Should -Throw '*double quote*' }
    It 'rejects control characters' { { Test-NiagaraArgument -Kind Message -Value "save`n-pwd:x" } | Should -Throw '*control*' }
    It 'rejects empty values' { { Test-NiagaraArgument -Kind ModuleName -Value '' } | Should -Throw '*empty*' }
    It 'requires an ORD scheme for hosts' {
        Test-NiagaraArgument -Kind HostOrd -Value 'ip:192.0.2.10' | Should -BeTrue
        { Test-NiagaraArgument -Kind HostOrd -Value '192.0.2.10' } | Should -Throw '*expected ip:*'
    }
    It 'rejects path traversal' {
        { Test-NiagaraArgument -Kind RemotePath -Value 'stations/../etc' } | Should -Throw '*..*'
        Test-NiagaraArgument -Kind RemotePath -Value 'stations/demo/console.txt' | Should -BeTrue
    }
    It 'validates module names' {
        Test-NiagaraArgument -Kind ModuleName -Value 'myModule-rt' | Should -BeTrue
        { Test-NiagaraArgument -Kind ModuleName -Value 'my module' } | Should -Throw
    }
}

Describe 'Test-NiagaraTier' {
    It 'allows configured tiers only' {
        $h = [pscustomobject]@{ alias = 'x'; allow = @('read', 'station') }
        Test-NiagaraTier -HostInfo $h -Tier read | Should -BeTrue
        Test-NiagaraTier -HostInfo $h -Tier install | Should -BeFalse
    }
    It 'denies everything when allow is absent' {
        Test-NiagaraTier -HostInfo ([pscustomobject]@{ alias = 'x' }) -Tier read | Should -BeFalse
    }
}
