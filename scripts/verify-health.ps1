<# .SYNOPSIS  HTTP health probe of the host's configured healthUrl (or -Url). Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [string] $Url,
    [int] $TimeoutSec = 10,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ url = $Url }
$ctx = Initialize-AgentScript -Op verify-health -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    $target = if ($Url) { $Url } else { $ctx.host.healthUrl }
    if (-not $target) { Fail-AgentScript -Ctx $ctx -Message "No healthUrl configured for host '$($ctx.host.alias)' and no -Url given" -ExitCode 2 -OpArgs $opArgs }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; url = $target }) -Status DRY_RUN -OpArgs $opArgs }
    $h = Test-StationHealth -Url $target -TimeoutSec $TimeoutSec -SkipCertificateCheck
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $h.ok; url = $target; status = $h.status; latencyMs = $h.latencyMs; body = $h.body; error = $(if ($h.PSObject.Properties['error']) { $h.error } else { $null }) }) -Status $(if ($h.ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($h.ok) { 0 } else { 1 }) -OpArgs $opArgs -Verify @{ status = $h.status }
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
