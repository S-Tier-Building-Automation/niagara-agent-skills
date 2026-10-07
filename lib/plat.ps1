# Core library: configuration, host allowlist, plat.exe / nre.exe invocation, station helpers.
# Dot-source this file; it dot-sources the rest of lib/.
#
# Exit code contract for every script in scripts/:
#   0 ok · 1 operation failed · 2 bad arguments · 3 needs confirmation (-Confirmed missing)
#   4 host not allowlisted · 5 no credential · 6 preflight failed · 7 verify failed (rollback attempted) · 124 timeout
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LibRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'validators.ps1')
. (Join-Path $PSScriptRoot 'parsers.ps1')
. (Join-Path $PSScriptRoot 'credentials.ps1')
. (Join-Path $PSScriptRoot 'audit.ps1')

$script:ExitOk = 0; $script:ExitFailed = 1; $script:ExitArgs = 2; $script:ExitNeedsConfirm = 3
$script:ExitNotAllowlisted = 4; $script:ExitNoCredential = 5; $script:ExitPreflight = 6; $script:ExitVerify = 7; $script:ExitTimeout = 124

# ------------------------------------------------------------------ configuration

function Get-NiagaraAgentConfig {
    <#
    .SYNOPSIS
        Loads ~/.niagara-agent/config.json (or $env:NIAGARA_AGENT_CONFIG). Fails closed when hosts are missing.
    #>
    [CmdletBinding()]
    param([string] $Path)
    if (-not $Path) { $Path = [Environment]::GetEnvironmentVariable('NIAGARA_AGENT_CONFIG') }
    if (-not $Path) { $Path = Join-Path (Get-NiagaraAgentHome) 'config.json' }
    $Path = Resolve-NiagaraPath -Path $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No agent config at $Path. Copy config/example.config.json there (or set NIAGARA_AGENT_CONFIG) and list your hosts."
    }
    $cfg = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not $cfg.PSObject.Properties['hosts'] -or -not $cfg.hosts) { throw "Config $Path has no 'hosts' allowlist." }
    $cfg | Add-Member -NotePropertyName configPath -NotePropertyValue $Path -Force
    return $cfg
}

function Resolve-NiagaraHost {
    <#
    .SYNOPSIS
        Returns the allowlisted host record for an alias, with defaults filled in. Throws HostNotAllowlisted otherwise.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config, [Parameter(Mandatory)] [string] $Alias)
    Test-NiagaraArgument -Kind Alias -Value $Alias | Out-Null
    $prop = $Config.hosts.PSObject.Properties | Where-Object { $_.Name -eq $Alias } | Select-Object -First 1
    if (-not $prop) { throw [System.InvalidOperationException]::new("HostNotAllowlisted: '$Alias' is not in the hosts allowlist of $($Config.configPath)") }
    $h = $prop.Value
    $rec = [ordered]@{
        alias          = $Alias
        hostord        = if ($h.PSObject.Properties['hostord'] -and $h.hostord) { [string]$h.hostord } else { 'ip:localhost' }
        port           = if ($h.PSObject.Properties['port'] -and $h.port) { [int]$h.port } else { 0 }
        secure         = ($h.PSObject.Properties['secure'] -and [bool]$h.secure)
        transport      = if ($h.PSObject.Properties['transport'] -and $h.transport) { [string]$h.transport } else { 'local' }
        ssh            = if ($h.PSObject.Properties['ssh']) { [string]$h.ssh } else { $null }
        allow          = if ($h.PSObject.Properties['allow']) { @($h.allow) } else { @('read') }
        niagaraHome    = if ($h.PSObject.Properties['niagaraHome'] -and $h.niagaraHome) { [string]$h.niagaraHome } elseif ($Config.PSObject.Properties['niagaraHome']) { [string]$Config.niagaraHome } else { $null }
        daemonUserHome = if ($h.PSObject.Properties['daemonUserHome'] -and $h.daemonUserHome) { [string]$h.daemonUserHome } elseif ($Config.PSObject.Properties['daemonUserHome']) { [string]$Config.daemonUserHome } else { $null }
        healthUrl      = if ($h.PSObject.Properties['healthUrl']) { [string]$h.healthUrl } else { $null }
        stations       = if ($h.PSObject.Properties['stations']) { [string[]]@($h.stations) } else { [string[]]@() }
        credentials    = if ($h.PSObject.Properties['credentials']) { $h.credentials } else { $null }
        credentialMode = if ($h.PSObject.Properties['credentialMode'] -and $h.credentialMode -eq 'argv') { 'argv' } else { 'script' }
    }
    Test-NiagaraArgument -Kind HostOrd -Value $rec.hostord | Out-Null
    return [pscustomobject]$rec
}

function Get-NiagaraTool {
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [ValidateSet('plat', 'nre', 'station', 'console')] [string] $Name)
    $agentHome = $HostInfo.niagaraHome
    if (-not $agentHome) { throw "niagaraHome is not configured for host '$($HostInfo.alias)' (set it in the config)." }
    $exe = Join-Path (Join-Path $agentHome 'bin') ($Name + '.exe')
    if (Test-Path -LiteralPath $exe) { return $exe }
    $noExt = Join-Path (Join-Path $agentHome 'bin') $Name
    if (Test-Path -LiteralPath $noExt) { return $noExt }
    throw "$Name not found under $agentHome\bin"
}

# ------------------------------------------------------------------ process runner

function Invoke-NativeCapture {
    <#
    .SYNOPSIS
        Runs a native executable with an argv ARRAY (never a string), captures stdout+stderr, enforces a timeout.
    #>
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $ArgumentList = @(),
        [int] $TimeoutSec = 300,
        [hashtable] $Environment = @{},
        [scriptblock] $OnLine
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    foreach ($a in $ArgumentList) { [void]$psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($k in $Environment.Keys) { $psi.Environment[$k] = [string]$Environment[$k] }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $lines = New-Object System.Collections.Generic.List[string]
    $sync = [System.Object]::new()
    $handler = {
        param($src, $e)
        if ($null -ne $e.Data) {
            [System.Threading.Monitor]::Enter($sync)
            try { $lines.Add($e.Data) } finally { [System.Threading.Monitor]::Exit($sync) }
            if ($OnLine) { & $OnLine $e.Data }
        }
    }
    $proc.add_OutputDataReceived($handler)
    $proc.add_ErrorDataReceived($handler)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $timedOut = -not $proc.WaitForExit($TimeoutSec * 1000)
    if ($timedOut) {
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch { } }
        $proc.WaitForExit(5000) | Out-Null
    } else {
        $proc.WaitForExit()
    }
    $sw.Stop()
    return [pscustomobject]@{
        exitCode   = if ($timedOut) { $script:ExitTimeout } else { $proc.ExitCode }
        timedOut   = $timedOut
        lines      = $lines.ToArray()
        durationMs = $sw.ElapsedMilliseconds
    }
}

# ------------------------------------------------------------------ plat

function Get-PlatCommonFlags {
    param([Parameter(Mandatory)] $HostInfo)
    $flags = @("-h:$($HostInfo.hostord)")
    if ($HostInfo.port -gt 0) { $flags += "-p:$($HostInfo.port)" }
    if ($HostInfo.secure) { $flags += '-secure' }
    $flags += '-noinput'
    return $flags
}

function Invoke-Plat {
    <#
    .SYNOPSIS
        Runs one plat.exe subcommand against an allowlisted host.
    .DESCRIPTION
        Credentials never touch argv: with -CredentialMode script (default) the credentialed line goes into a
        temporary `plat script -f:<file>` whose ACL is restricted to the current user and which is deleted in
        finally. -CredentialMode argv is the documented fallback for versions whose `script` command does not
        accept -usr/-pwd per line. -DryRun prints the masked plan and spawns nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostInfo,
        [Parameter(Mandatory)] [string] $Command,
        [string[]] $Arguments = @(),
        [ValidateSet('read', 'station', 'install', 'bog', 'host')] [string] $Tier = 'read',
        [pscredential] $Credential,
        [switch] $NoCredential,
        [ValidateSet('script', 'argv', '')] [string] $CredentialMode = '',
        [int] $TimeoutSec = 300,
        [switch] $DryRun,
        [scriptblock] $OnLine
    )
    if (-not (Test-NiagaraTier -HostInfo $HostInfo -Tier $Tier)) {
        throw [System.InvalidOperationException]::new("TierNotAllowed: host '$($HostInfo.alias)' does not allow tier '$Tier' (allow=$($HostInfo.allow -join ','))")
    }
    if ($Command -notmatch '^[a-z]+$') { throw "Invalid plat command '$Command'" }
    if (-not $CredentialMode) { $CredentialMode = if ($HostInfo.PSObject.Properties['credentialMode'] -and $HostInfo.credentialMode) { [string]$HostInfo.credentialMode } else { 'script' } }
    foreach ($a in $Arguments) { if ($a.StartsWith('-')) { throw "Refusing plat argument that looks like a flag: $a" } }
    $plat = $null
    if ($DryRun) { try { $plat = Get-NiagaraTool -HostInfo $HostInfo -Name plat } catch { $plat = '<plat not found>' } }
    else { $plat = Get-NiagaraTool -HostInfo $HostInfo -Name plat }
    $common = Get-PlatCommonFlags -HostInfo $HostInfo
    $cred = $null
    if (-not $NoCredential) {
        $cred = $Credential
        if (-not $cred) { $cred = Get-NiagaraCredential -HostInfo $HostInfo -Config $null -NonInteractive:$DryRun }
    }
    $maskedArgv = @($Command) + $common + $(if ($cred) { @("-usr:$($cred.UserName)", '-pwd:********') } else { @() }) + $Arguments
    if ($DryRun) {
        return [pscustomobject]@{ ok = $true; dryRun = $true; exitCode = 0; command = $Command; hostAlias = $HostInfo.alias; argv = $maskedArgv; lines = @(); noise = @(); durationMs = 0 }
    }
    $tmp = $null
    try {
        $argv = @()
        if ($cred -and $CredentialMode -eq 'script') {
            $tmpDir = Join-Path (Get-NiagaraAgentHome) 'tmp'
            if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null }
            $tmp = Join-Path $tmpDir ([guid]::NewGuid().ToString('N') + '.plat')
            $plain = ConvertTo-PlainText -Secure $cred.Password
            try {
                $line = (@($Command) + $common + @("-usr:$($cred.UserName)", "-pwd:$plain") + $Arguments) -join ' '
                [System.IO.File]::WriteAllText($tmp, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
            } finally { $plain = $null }
            Protect-TempFile -Path $tmp
            $argv = @('script', "-f:$tmp")
        } elseif ($cred) {
            $plain = ConvertTo-PlainText -Secure $cred.Password
            $argv = @($Command) + $common + @("-usr:$($cred.UserName)", "-pwd:$plain") + $Arguments
        } else {
            $argv = @($Command) + $common + $Arguments
        }
        $run = Invoke-NativeCapture -FilePath $plat -ArgumentList $argv -TimeoutSec $TimeoutSec -OnLine $OnLine
        $split = Split-NiagaraOutput -Lines $run.lines
        $ok = ($run.exitCode -eq 0) -and -not ($split.payload -match '^(ERROR|SEVERE|Exception|java\.|Failed|FAILED)')
        return [pscustomobject]@{
            ok = [bool]$ok; dryRun = $false; exitCode = $run.exitCode; timedOut = $run.timedOut; command = $Command
            hostAlias = $HostInfo.alias; argv = $maskedArgv; lines = $split.payload; noise = $split.noise; durationMs = $run.durationMs
        }
    } finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Protect-TempFile {
    param([Parameter(Mandatory)] [string] $Path)
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $Path /inheritance:r /grant:r "${me}:(F)" | Out-Null
    } else {
        & chmod 600 $Path
    }
}

function Get-PlatUsage {
    <#
    .SYNOPSIS
        Returns the flags `plat <cmd> -usage` advertises on this host, cached per Niagara home.
    #>
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [string] $Command)
    $cacheDir = Join-Path (Get-NiagaraAgentHome) 'cache'
    if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    $key = ((($HostInfo.niagaraHome + '|' + $Command) -replace '[^A-Za-z0-9]', '_'))
    $cache = Join-Path $cacheDir "usage-$key.json"
    if (Test-Path -LiteralPath $cache) { return @((Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json)) }
    $plat = Get-NiagaraTool -HostInfo $HostInfo -Name plat
    $run = Invoke-NativeCapture -FilePath $plat -ArgumentList @($Command, '-usage') -TimeoutSec 120
    $flags = ConvertFrom-PlatUsage -Lines $run.lines
    ($flags | ConvertTo-Json -Compress) | Set-Content -LiteralPath $cache -Encoding utf8
    return @($flags)
}

function Test-PlatFlag {
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [string] $Command, [Parameter(Mandatory)] [string] $Flag)
    return ((Get-PlatUsage -HostInfo $HostInfo -Command $Command) -contains $Flag)
}

# ------------------------------------------------------------------ stations

function Get-PlatStations {
    param([Parameter(Mandatory)] $HostInfo, [string] $Name, [switch] $Running, [pscredential] $Credential, [switch] $DryRun)
    $platArgs = @()
    if ($Name) { Test-NiagaraArgument -Kind StationName -Value $Name | Out-Null; $platArgs += $Name }
    $r = Invoke-Plat -HostInfo $HostInfo -Command liststations -Arguments $platArgs -Tier read -Credential $Credential -DryRun:$DryRun -TimeoutSec 180
    if ($DryRun) { return $r }
    if (-not $r.ok) { throw "plat liststations failed (exit $($r.exitCode)): $($r.lines -join ' | ')" }
    $stations = @(ConvertFrom-PlatListStations -Lines $r.lines)
    if ($Running) { $stations = @($stations | Where-Object { $_.status -eq 'running' }) }
    return $stations
}

function Wait-StationStatus {
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [ValidateSet('running', 'stopped')] [string] $Expected,
          [int] $TimeoutSec = 180, [int] $PollSec = 5, [pscredential] $Credential)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = 'unknown'
    while ((Get-Date) -lt $deadline) {
        $st = Get-PlatStations -HostInfo $HostInfo -Name $Name -Credential $Credential | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($st) { $last = $st.status; if ($st.status -eq $Expected) { return $st } }
        Start-Sleep -Seconds $PollSec
    }
    throw [System.TimeoutException]::new("Station '$Name' did not reach '$Expected' within ${TimeoutSec}s (last: $last)")
}

function Get-PlatDetails {
    param([Parameter(Mandatory)] $HostInfo, [pscredential] $Credential, [switch] $DryRun)
    $r = Invoke-Plat -HostInfo $HostInfo -Command details -Tier read -Credential $Credential -DryRun:$DryRun -TimeoutSec 180
    if ($DryRun) { return $r }
    if (-not $r.ok) { throw "plat details failed (exit $($r.exitCode))" }
    return ConvertFrom-PlatKeyValue -Lines $r.lines
}

# ------------------------------------------------------------------ nre

function Invoke-Nre {
    <#
    .SYNOPSIS
        Runs nre.exe with a switch (-version, -hostid, -licenses, -modules:<pattern>, -props). No credentials needed.
    #>
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [string[]] $Arguments, [int] $TimeoutSec = 180)
    foreach ($a in $Arguments) { if ($a -notmatch '^-(version|hostid|licenses|props|modules:[A-Za-z0-9_*.-]*|@[^\s"]+)$') { throw "Refusing nre argument: $a" } }
    $nre = Get-NiagaraTool -HostInfo $HostInfo -Name nre
    $run = Invoke-NativeCapture -FilePath $nre -ArgumentList $Arguments -TimeoutSec $TimeoutSec
    $split = Split-NiagaraOutput -Lines $run.lines
    return [pscustomobject]@{ ok = ($run.exitCode -eq 0); exitCode = $run.exitCode; lines = $split.payload; noise = $split.noise; durationMs = $run.durationMs }
}

function Get-NreModules {
    param([Parameter(Mandatory)] $HostInfo, [string] $Pattern = '')
    $r = Invoke-Nre -HostInfo $HostInfo -Arguments @("-modules:$Pattern")
    return @(ConvertFrom-NreModules -Lines $r.lines)
}

# ------------------------------------------------------------------ service

function Test-Administrator {
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) { return $true }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-NiagaraService {
    param([Parameter(Mandatory)] [ValidateSet('status', 'stop', 'start', 'restart')] [string] $Action, [string] $Name = 'Niagara', [int] $TimeoutSec = 120)
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) { throw "Service control is implemented for Windows hosts only (use plat stop/start station elsewhere)." }
    $svc = Get-Service -Name $Name -ErrorAction Stop
    if ($Action -eq 'status') { return [pscustomobject]@{ name = $Name; status = [string]$svc.Status } }
    if (-not (Test-Administrator)) { throw "Service control requires an elevated (Administrator) session." }
    if ($Action -in @('stop', 'restart')) {
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Process -Name niagarad -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    }
    if ($Action -in @('start', 'restart')) { Start-Service -Name $Name -ErrorAction Stop }
    $svc = Get-Service -Name $Name
    return [pscustomobject]@{ name = $Name; status = [string]$svc.Status }
}

# ------------------------------------------------------------------ health

function Test-StationHealth {
    param([Parameter(Mandatory)] [string] $Url, [int] $TimeoutSec = 10, [switch] $SkipCertificateCheck)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $params = @{ Uri = $Url; TimeoutSec = $TimeoutSec; UseBasicParsing = $true; ErrorAction = 'Stop' }
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) { $params.SkipCertificateCheck = $true }
        $resp = Invoke-WebRequest @params
        $sw.Stop()
        $body = $null
        try { $body = $resp.Content | ConvertFrom-Json } catch { }
        return [pscustomobject]@{ ok = ($resp.StatusCode -eq 200); status = [int]$resp.StatusCode; latencyMs = $sw.ElapsedMilliseconds; body = $body }
    } catch {
        $sw.Stop()
        return [pscustomobject]@{ ok = $false; status = 0; latencyMs = $sw.ElapsedMilliseconds; error = $_.Exception.Message }
    }
}

# ------------------------------------------------------------------ script plumbing

function Write-AgentResult {
    <#
    .SYNOPSIS
        Emits the script result: JSON on one line when -Json, otherwise a readable summary. Always sets the exit code.
    #>
    param([Parameter(Mandatory)] $Result, [switch] $Json, [int] $ExitCode = 0)
    if ($Json) {
        Write-Output ('NIAGARA_AGENT_RESULT_JSON:' + ($Result | ConvertTo-Json -Compress -Depth 8))
    } else {
        $Result | ConvertTo-Json -Depth 8 | Write-Output
    }
    exit $ExitCode
}
