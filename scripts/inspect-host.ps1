<# .SYNOPSIS  Host ID, Niagara version, licences, modules (pattern) and platform details. Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [string] $ModulePattern = '',
    [switch] $SkipDetails,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ modulePattern = $ModulePattern; skipDetails = [bool]$SkipDetails }
$ctx = Initialize-AgentScript -Op inspect-host -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = @('nre -version', '-hostid', '-licenses', "-modules:$ModulePattern", 'plat details') }) -Status DRY_RUN -OpArgs $opArgs }
    $version = (Invoke-Nre -HostInfo $ctx.host -Arguments @('-version')).lines -join ' '
    $hostId = (Invoke-Nre -HostInfo $ctx.host -Arguments @('-hostid')).lines -join ' '
    $licenses = (Invoke-Nre -HostInfo $ctx.host -Arguments @('-licenses')).lines
    $modules = Get-NreModules -HostInfo $ctx.host -Pattern $ModulePattern
    $details = $null
    if (-not $SkipDetails) {
        $cred = Get-OptionalCredential -Ctx $ctx
        try { $details = Get-PlatDetails -HostInfo $ctx.host -Credential $cred } catch { $details = @{ error = $_.Exception.Message } }
    }
    $result = [pscustomobject]@{ ok = $true; host = $ctx.host.alias; niagaraHome = $ctx.host.niagaraHome; version = $version.Trim(); hostId = $hostId.Trim(); licenses = @($licenses); modules = @($modules); details = $details }
    Complete-AgentScript -Ctx $ctx -Result $result -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
