<# .SYNOPSIS  Status / stop / start / restart the Niagara platform service (Windows). Tier: host (confirm for changes). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [ValidateSet('status','stop','start','restart')] [string] $Action,
    [string] $ServiceName = 'Niagara',
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ action = $Action; service = $ServiceName }
$destructive = ($Action -ne 'status')
$ctx = Initialize-AgentScript -Op manage-daemon -HostAlias $HostAlias -Tier $(if ($destructive) { 'host' } else { 'read' }) -ConfigPath $ConfigPath -Destructive:$destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if ($ctx.host.transport -ne 'local') { Fail-AgentScript -Ctx $ctx -Message "manage-daemon must run on the host itself (transport=$($ctx.host.transport)); use scripts/remote.mjs" -ExitCode 2 -OpArgs $opArgs }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = "$Action service $ServiceName" }) -Status DRY_RUN -OpArgs $opArgs }
    $r = Set-NiagaraService -Action $Action -Name $ServiceName
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; service = $r.name; status = $r.status; action = $Action }) -OpArgs $opArgs -Verify @{ status = $r.status }
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
