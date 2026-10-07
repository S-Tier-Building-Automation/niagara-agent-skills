<# .SYNOPSIS  Ask the platform daemon to reboot its host (plat reboothost). Tier: host (confirm + -ConfirmHost). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [string] $ConfirmHost,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ confirmHost = $ConfirmHost }
$ctx = Initialize-AgentScript -Op reboot-host -HostAlias $HostAlias -Tier host -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if (-not $DryRun -and $ConfirmHost -ne $HostAlias) { Fail-AgentScript -Ctx $ctx -Message "reboot-host requires -ConfirmHost '$HostAlias' (double confirmation)" -ExitCode 2 -Status DENIED -OpArgs $opArgs }
    $cred = Get-OptionalCredential -Ctx $ctx
    $r = Invoke-Plat -HostInfo $ctx.host -Command reboothost -Tier host -Credential $cred -DryRun:$DryRun -TimeoutSec 120
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result $r -Status DRY_RUN -OpArgs $opArgs }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $r.ok; output = $r.lines; note = 'Wait for the daemon to return, then run list-stations / verify-health.' }) -Status $(if ($r.ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($r.ok) { 0 } else { 1 }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
