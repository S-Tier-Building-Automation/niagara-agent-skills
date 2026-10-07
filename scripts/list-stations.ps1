<# .SYNOPSIS  List the stations the platform daemon manages (plat liststations). Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [string] $Name,
    [switch] $Running,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ name = $Name; running = [bool]$Running }
$ctx = Initialize-AgentScript -Op list-stations -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
$cred = Get-OptionalCredential -Ctx $ctx
try {
    $r = Get-PlatStations -HostInfo $ctx.host -Name $Name -Running:$Running -Credential $cred -DryRun:$DryRun
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result $r -Status DRY_RUN -OpArgs $opArgs }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; host = $ctx.host.alias; count = @($r).Count; stations = @($r) }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
