<# .SYNOPSIS  Install a Niagara distribution file (.dist) on a host with plat distinstall. Tier: install (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Dist,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ dist = $Dist }
$ctx = Initialize-AgentScript -Op install-dist -HostAlias $HostAlias -Tier install -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind LocalPath -Value $Dist | Out-Null
    if (-not (Test-Path -LiteralPath $Dist)) { Fail-AgentScript -Ctx $ctx -Message "Dist file not found: $Dist" -ExitCode 6 -OpArgs $opArgs }
    if ($Dist -notmatch '\.dist$') { Fail-AgentScript -Ctx $ctx -Message 'Expected a .dist file' -ExitCode 2 -OpArgs $opArgs }
    $cred = Get-OptionalCredential -Ctx $ctx
    $r = Invoke-Plat -HostInfo $ctx.host -Command distinstall -Arguments @((Resolve-Path -LiteralPath $Dist).Path) -Tier install -Credential $cred -DryRun:$DryRun -TimeoutSec 1800
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result $r -Status DRY_RUN -OpArgs $opArgs }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $r.ok; output = $r.lines; note = 'A dist install may reboot the host or restart the daemon; verify with inspect-host / list-stations.' }) -Status $(if ($r.ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($r.ok) { 0 } else { 1 }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
