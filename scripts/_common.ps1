# Shared bootstrap for every script in scripts/: loads the library, config and host, and
# provides the confirmation gate + audit/exit helpers.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib' 'plat.ps1')

function Initialize-AgentScript {
    <#
    .SYNOPSIS
        Resolves config + host and returns a context object for the script.
    #>
    param(
        [Parameter(Mandatory)] [string] $Op,
        [Parameter(Mandatory)] [string] $HostAlias,
        [Parameter(Mandatory)] [ValidateSet('read', 'station', 'install', 'bog', 'host')] [string] $Tier,
        [string] $ConfigPath,
        [switch] $Destructive,
        [switch] $Confirmed,
        [switch] $DryRun,
        [switch] $Json,
        [hashtable] $OpArgs = @{}
    )
    $ctx = [ordered]@{ op = $Op; tier = $Tier; traceId = (New-AuditTrace); json = [bool]$Json; dryRun = [bool]$DryRun; started = Get-Date }
    try {
        $ctx.config = Get-NiagaraAgentConfig -Path $ConfigPath
        $ctx.host = Resolve-NiagaraHost -Config $ctx.config -Alias $HostAlias
    } catch {
        $msg = $_.Exception.Message
        Write-AuditRecord -Op $Op -Status DENIED -Tier $Tier -HostAlias $HostAlias -OpArgs $OpArgs -TraceId $ctx.traceId -Detail $msg | Out-Null
        Write-AgentResult -Json:$Json -ExitCode $(if ($msg -like 'HostNotAllowlisted*') { 4 } else { 2 }) -Result ([pscustomobject]@{ ok = $false; error = $msg })
    }
    if (-not (Test-NiagaraTier -HostInfo $ctx.host -Tier $Tier)) {
        $msg = "TierNotAllowed: host '$HostAlias' does not allow tier '$Tier' (allow=$($ctx.host.allow -join ','))"
        Write-AuditRecord -Op $Op -Status DENIED -Tier $Tier -HostAlias $HostAlias -HostOrd $ctx.host.hostord -OpArgs $OpArgs -TraceId $ctx.traceId -Detail $msg | Out-Null
        Write-AgentResult -Json:$Json -ExitCode 4 -Result ([pscustomobject]@{ ok = $false; error = $msg })
    }
    if ($Destructive -and -not $Confirmed -and -not $DryRun) {
        $msg = "NEEDS_CONFIRM: '$Op' on host '$HostAlias' ($($ctx.host.hostord)) changes state. Ask the user, then re-run with -Confirmed (or preview with -DryRun)."
        Write-AuditRecord -Op $Op -Status NEEDS_CONFIRM -Tier $Tier -HostAlias $HostAlias -HostOrd $ctx.host.hostord -OpArgs $OpArgs -TraceId $ctx.traceId -Detail $msg | Out-Null
        Write-AgentResult -Json:$Json -ExitCode 3 -Result ([pscustomobject]@{ ok = $false; needsConfirm = $true; error = $msg; args = $OpArgs })
    }
    Write-AuditRecord -Op $Op -Status STARTED -Tier $Tier -HostAlias $HostAlias -HostOrd $ctx.host.hostord -OpArgs $OpArgs -TraceId $ctx.traceId -DryRun $DryRun -Confirmed $Confirmed | Out-Null
    return [pscustomobject]$ctx
}

function Complete-AgentScript {
    param([Parameter(Mandatory)] $Ctx, [Parameter(Mandatory)] $Result, [string] $Status = 'SUCCESS', [int] $ExitCode = 0, [hashtable] $OpArgs = @{}, [hashtable] $Verify = @{}, [string] $Detail = '')
    $ms = [long]((Get-Date) - $Ctx.started).TotalMilliseconds
    Write-AuditRecord -Op $Ctx.op -Status $Status -Tier $Ctx.tier -HostAlias $Ctx.host.alias -HostOrd $Ctx.host.hostord -OpArgs $OpArgs -TraceId $Ctx.traceId -DryRun $Ctx.dryRun -ExitCode $ExitCode -DurationMs $ms -Verify $Verify -Detail $Detail | Out-Null
    Write-AgentResult -Json:$Ctx.json -ExitCode $ExitCode -Result $Result
}

function Fail-AgentScript {
    param([Parameter(Mandatory)] $Ctx, [Parameter(Mandatory)] [string] $Message, [int] $ExitCode = 1, [string] $Status = 'FAILURE', [hashtable] $OpArgs = @{})
    Complete-AgentScript -Ctx $Ctx -Result ([pscustomobject]@{ ok = $false; error = $Message; traceId = $Ctx.traceId }) -Status $Status -ExitCode $ExitCode -OpArgs $OpArgs -Detail $Message
}

function Get-OptionalCredential {
    param([Parameter(Mandatory)] $Ctx)
    try { return Get-NiagaraCredential -HostInfo $Ctx.host -Config $Ctx.config -NonInteractive:($Ctx.json -or $Ctx.dryRun) }
    catch { Fail-AgentScript -Ctx $Ctx -Message $_.Exception.Message -ExitCode 5 -Status DENIED }
}
