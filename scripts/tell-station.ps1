<# .SYNOPSIS  Send a console command to a running station (plat tellstation), e.g. "save". Tier: station (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Station,
    [Parameter(Mandatory)] [string] $Message,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ station = $Station; message = $Message }
$ctx = Initialize-AgentScript -Op tell-station -HostAlias $HostAlias -Tier station -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
    Test-NiagaraArgument -Kind Message -Value $Message | Out-Null
    $cred = Get-OptionalCredential -Ctx $ctx
    $r = Invoke-Plat -HostInfo $ctx.host -Command tellstation -Arguments @($Station, $Message) -Tier station -Credential $cred -DryRun:$DryRun -TimeoutSec 120
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result $r -Status DRY_RUN -OpArgs $opArgs }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $r.ok; station = $Station; output = $r.lines }) -Status $(if ($r.ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($r.ok) { 0 } else { 1 }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
