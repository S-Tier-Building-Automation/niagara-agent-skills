BeforeAll {
    . (Join-Path $PSScriptRoot '..' '..' 'lib' 'plat.ps1')
    $script:tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("nas-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:tmpHome | Out-Null
    $env:NIAGARA_AGENT_HOME = $script:tmpHome
    $script:cfgPath = Join-Path $script:tmpHome 'config.json'
    @{
        niagaraHome = $script:tmpHome
        hosts = @{
            local = @{ hostord = 'ip:localhost'; port = 5011; secure = $true; allow = @('read', 'station') }
            ro = @{ hostord = 'ip:192.0.2.9'; allow = @('read') }
        }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:cfgPath
}
AfterAll {
    Remove-Item -LiteralPath $script:tmpHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NIAGARA_AGENT_HOME -ErrorAction SilentlyContinue
}

Describe 'Get-NiagaraAgentConfig / Resolve-NiagaraHost' {
    It 'loads the config and resolves an allowlisted host' {
        $cfg = Get-NiagaraAgentConfig -Path $script:cfgPath
        $h = Resolve-NiagaraHost -Config $cfg -Alias local
        $h.alias | Should -Be 'local'
        $h.hostord | Should -Be 'ip:localhost'
        $h.port | Should -Be 5011
        $h.secure | Should -BeTrue
    }
    It 'fails closed for an unknown alias' {
        $cfg = Get-NiagaraAgentConfig -Path $script:cfgPath
        { Resolve-NiagaraHost -Config $cfg -Alias nope } | Should -Throw 'HostNotAllowlisted*'
    }
    It 'fails for a missing config file' {
        { Get-NiagaraAgentConfig -Path (Join-Path $script:tmpHome 'missing.json') } | Should -Throw
    }
}

Describe 'Invoke-Plat -DryRun' {
    BeforeAll {
        $cfg = Get-NiagaraAgentConfig -Path $script:cfgPath
        $script:local = Resolve-NiagaraHost -Config $cfg -Alias local
        $script:ro = Resolve-NiagaraHost -Config $cfg -Alias ro
        $script:cred = New-Object System.Management.Automation.PSCredential('ops', (ConvertTo-SecureString 'hunter2' -AsPlainText -Force))
    }
    It 'builds a masked argv and never shows the password' {
        $r = Invoke-Plat -HostInfo $script:local -Command liststations -Tier read -Credential $script:cred -DryRun
        $r.dryRun | Should -BeTrue
        ($r.argv -join ' ') | Should -Be 'liststations -h:ip:localhost -p:5011 -secure -noinput -usr:ops -pwd:********'
        ($r.argv -join ' ') | Should -Not -Match 'hunter2'
    }
    It 'refuses tiers the host does not allow' {
        { Invoke-Plat -HostInfo $script:ro -Command startstation -Arguments @('demo') -Tier station -Credential $script:cred -DryRun } | Should -Throw 'TierNotAllowed*'
    }
    It 'refuses arguments that look like flags' {
        { Invoke-Plat -HostInfo $script:local -Command liststations -Arguments @('-pwd:x') -Tier read -Credential $script:cred -DryRun } | Should -Throw '*looks like a flag*'
    }
    It 'refuses non-alphabetic command names' {
        { Invoke-Plat -HostInfo $script:local -Command 'list;rm' -Tier read -Credential $script:cred -DryRun } | Should -Throw '*Invalid plat command*'
    }
}

Describe 'Write-AuditRecord' {
    It 'writes a redacted JSONL record' {
        $rec = Write-AuditRecord -Op test-op -Status SUCCESS -Tier read -HostAlias local -HostOrd ip:localhost -OpArgs @{ note = 'x -pwd:secret y' } -Detail 'foxs://user:pw@host/'
        $rec.args.note | Should -Be 'x [REDACTED] y'
        $rec.detail | Should -Not -Match 'user:pw'
        $file = Get-ChildItem (Join-Path $script:tmpHome 'logs') -Filter 'audit-*.jsonl' | Select-Object -First 1
        $file | Should -Not -BeNullOrEmpty
        $last = Get-Content $file.FullName | Select-Object -Last 1 | ConvertFrom-Json
        $last.op | Should -Be 'test-op'
        $last.PSObject.Properties.Name | Should -Not -Contain 'password'
    }
    It 'is queryable by Read-AuditRecords' {
        $all = Read-AuditRecords -Days 1 -Op test-op
        @($all).Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'Get-NiagaraCredential' {
    It 'uses the env provider' {
        $env:NIAGARA_PLAT_USER = 'envuser'; $env:NIAGARA_PLAT_PASSWORD = 'envpass'
        try {
            $c = Get-NiagaraCredential -HostInfo ([pscustomobject]@{ alias = 'x' }) -NonInteractive
            $c.UserName | Should -Be 'envuser'
        } finally { Remove-Item Env:NIAGARA_PLAT_USER, Env:NIAGARA_PLAT_PASSWORD -ErrorAction SilentlyContinue }
    }
    It 'throws NoCredential when nothing is configured' {
        { Get-NiagaraCredential -HostInfo ([pscustomobject]@{ alias = 'x' }) -NonInteractive } | Should -Throw 'NoCredential*'
    }
    It 'runs a script provider' {
        $prov = Join-Path $script:tmpHome 'prov.ps1'
        Set-Content -LiteralPath $prov -Value 'param([Parameter(ValueFromRemainingArguments)] [string[]] $Rest); $a = $Rest[[array]::IndexOf($Rest, "--host") + 1]; @{ user = "p-$a"; password = "s" } | ConvertTo-Json -Compress'
        $h = [pscustomobject]@{ alias = 'jace'; credentials = [pscustomobject]@{ provider = 'script'; path = $prov } }
        (Get-NiagaraCredential -HostInfo $h -NonInteractive).UserName | Should -Be 'p-jace'
    }
}
