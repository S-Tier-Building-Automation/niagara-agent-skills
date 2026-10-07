<# .SYNOPSIS  Stop a station via the platform daemon and wait for it. Tier: station (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Station,
    [int] $TimeoutSec = 180,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ station = $Station; timeoutSec = $TimeoutSec }
$ctx = Initialize-AgentScript -Op stop-station -HostAlias $HostAlias -Tier station -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
    if (@($ctx.host.stations).Count -gt 0 -and $ctx.host.stations -notcontains $Station) {
        Fail-AgentScript -Ctx $ctx -Message "Station '$Station' is not in the allowlisted stations for host '$($ctx.host.alias)' ($($ctx.host.stations -join ','))" -ExitCode 4 -Status DENIED -OpArgs $opArgs
    }
    $cred = Get-OptionalCredential -Ctx $ctx
    $before = Get-PlatStations -HostInfo $ctx.host -Name $Station -Credential $cred -DryRun:$DryRun
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = $before.argv }) -Status DRY_RUN -OpArgs $opArgs }
    $st = $before | Where-Object { $_.name -eq $Station } | Select-Object -First 1
    if (-not $st) { Fail-AgentScript -Ctx $ctx -Message "Station '$Station' is not managed by the daemon on '$($ctx.host.alias)'" -ExitCode 6 -OpArgs $opArgs }
    if ($st.status -eq 'stopped') {
        Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; station = $Station; status = $st.status; changed = $false }) -OpArgs $opArgs -Verify @{ statusAfter = $st.status }
    }
    $r = Invoke-Plat -HostInfo $ctx.host -Command stopstation -Arguments @($Station) -Tier station -Credential $cred -TimeoutSec 300
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "plat stopstation failed (exit $($r.exitCode)): $($r.lines -join ' | ')" -OpArgs $opArgs }
    $after = Wait-StationStatus -HostInfo $ctx.host -Name $Station -Expected stopped -TimeoutSec $TimeoutSec -Credential $cred
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; station = $Station; status = $after.status; changed = $true; durationMs = $r.durationMs }) -OpArgs $opArgs -Verify @{ statusBefore = $st.status; statusAfter = $after.status }
} catch [System.TimeoutException] { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 7 -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
