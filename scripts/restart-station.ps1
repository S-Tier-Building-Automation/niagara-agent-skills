<# .SYNOPSIS  Stop, then start a station and verify (optionally its STier /stier/health). Tier: station (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Station,
    [int] $TimeoutSec = 240,
    [switch] $SkipHealth,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ station = $Station; timeoutSec = $TimeoutSec }
$ctx = Initialize-AgentScript -Op restart-station -HostAlias $HostAlias -Tier station -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
    if (@($ctx.host.stations).Count -gt 0 -and $ctx.host.stations -notcontains $Station) {
        Fail-AgentScript -Ctx $ctx -Message "Station '$Station' is not in the allowlisted stations for host '$($ctx.host.alias)'" -ExitCode 4 -Status DENIED -OpArgs $opArgs
    }
    $cred = Get-OptionalCredential -Ctx $ctx
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = @("plat stopstation $Station", "wait stopped", "plat startstation $Station", "wait running", "GET $($ctx.host.healthUrl)") }) -Status DRY_RUN -OpArgs $opArgs }
    $stop = Invoke-Plat -HostInfo $ctx.host -Command stopstation -Arguments @($Station) -Tier station -Credential $cred -TimeoutSec 300
    if (-not $stop.ok) { Fail-AgentScript -Ctx $ctx -Message "plat stopstation failed (exit $($stop.exitCode))" -OpArgs $opArgs }
    Wait-StationStatus -HostInfo $ctx.host -Name $Station -Expected stopped -TimeoutSec $TimeoutSec -Credential $cred | Out-Null
    $start = Invoke-Plat -HostInfo $ctx.host -Command startstation -Arguments @($Station) -Tier station -Credential $cred -TimeoutSec 300
    if (-not $start.ok) { Fail-AgentScript -Ctx $ctx -Message "plat startstation failed (exit $($start.exitCode))" -ExitCode 7 -OpArgs $opArgs }
    $after = Wait-StationStatus -HostInfo $ctx.host -Name $Station -Expected running -TimeoutSec $TimeoutSec -Credential $cred
    $health = $null
    if (-not $SkipHealth -and $ctx.host.healthUrl) {
        $deadline = (Get-Date).AddSeconds([Math]::Min($TimeoutSec, 120))
        do { $health = Test-StationHealth -Url $ctx.host.healthUrl -SkipCertificateCheck; if ($health.ok) { break }; Start-Sleep -Seconds 5 } while ((Get-Date) -lt $deadline)
        if (-not $health.ok) { Fail-AgentScript -Ctx $ctx -Message "Station restarted but $($ctx.host.healthUrl) did not answer 200: $($health.error)" -ExitCode 7 -OpArgs $opArgs }
    }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; station = $Station; status = $after.status; health = $health }) -OpArgs $opArgs -Verify @{ statusAfter = $after.status; health = $(if ($health) { $health.status } else { 'skipped' }) }
} catch [System.TimeoutException] { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 7 -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
