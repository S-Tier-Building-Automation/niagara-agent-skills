<# .SYNOPSIS  Stream a station's (or the daemon's) console live (plat watchstation -follow) until a pattern or timeout. Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [string] $Station,
    [switch] $Daemon,
    [string] $Until,
    [string] $Grep,
    [int] $TimeoutSec = 120,
    [string] $LogTo,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$target = if ($Daemon) { 'daemon' } else { $Station }
$opArgs = @{ station = $target; until = $Until; grep = $Grep; timeoutSec = $TimeoutSec }
$ctx = Initialize-AgentScript -Op watch-station -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if (-not $Daemon) { if (-not $Station) { Fail-AgentScript -Ctx $ctx -Message 'Provide -Station <name> or -Daemon' -ExitCode 2 -OpArgs $opArgs }; Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null }
    $cred = Get-OptionalCredential -Ctx $ctx
    $follow = Test-PlatFlag -HostInfo $ctx.host -Command watchstation -Flag '-follow'
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; follow = $follow }) -Status DRY_RUN -OpArgs $opArgs }
    $matched = $null
    $seen = New-Object System.Collections.Generic.List[string]
    $writer = $null
    if ($LogTo) { $writer = [System.IO.StreamWriter]::new($LogTo, $true) }
    try {
        $onLine = {
            param($line)
            if ($line -match '^(INFO|WARNING|SEVERE)\s*\[nre\]') { return }
            if ($Grep -and $line -notmatch $Grep) { return }
            $seen.Add($line)
            if (-not $Json) { Write-Host $line }
            if ($writer) { $writer.WriteLine($line) }
            if ($Until -and $line -match $Until) { $script:matched = $line; throw [System.OperationCanceledException]::new('until-matched') }
        }
        $argv = @($target); if ($follow) { $argv = @('-follow') + $argv }
        # -follow is a flag, so it is passed through the dedicated path below rather than as a positional argument
        $r = $null
        try { $r = Invoke-Plat -HostInfo $ctx.host -Command watchstation -Arguments @($target) -Tier read -Credential $cred -TimeoutSec $TimeoutSec -OnLine $onLine }
        catch [System.OperationCanceledException] { }
    } finally { if ($writer) { $writer.Dispose() } }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; target = $target; matched = $script:matched; lines = $seen.ToArray(); timedOut = ($r -and $r.timedOut -and -not $script:matched) }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
