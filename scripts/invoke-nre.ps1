<# .SYNOPSIS  Runs nre from the right Niagara install (each Niagara version ships its own): lists the installs, or reads version, host ID, licences, modules or system properties. Read-only: never starts a station, Workbench or any other program. Tier: read. #>
[CmdletBinding()]
param(
    [ValidateSet('homes', 'version', 'hostid', 'licenses', 'modules', 'props')] [string] $Action = 'version',
    [string] $HostAlias = 'local',
    [string] $NiagaraVersion,
    [string] $NiagaraHome,
    [string] $MatchHost,
    [string] $ModulePattern = '',
    [switch] $Probe,
    [int] $TimeoutSec = 180,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

# Which install runs nre (first that applies): -NiagaraHome, -NiagaraVersion (4.15 = newest 4.15.x),
# -MatchHost (same major.minor as that host's runtime, read with plat details), the host's niagaraHome,
# the only install, the newest install. See Select-NiagaraHome in lib/homes.ps1.
$opArgs = @{ action = $Action; niagaraVersion = $NiagaraVersion; niagaraHome = $NiagaraHome; matchHost = $MatchHost; modulePattern = $ModulePattern; probe = [bool]$Probe }
$ctx = Initialize-AgentScript -Op invoke-nre -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if ($ctx.host.transport -ne 'local') {
        Fail-AgentScript -Ctx $ctx -Message "nre runs on this machine; '$($ctx.host.alias)' is reached over $($ctx.host.transport). Run this script there with run-remote." -ExitCode 2 -OpArgs $opArgs
    }
    if ($ModulePattern -and $ModulePattern -notmatch '^[A-Za-z0-9_*.-]+$') { Fail-AgentScript -Ctx $ctx -Message "Invalid module pattern '$ModulePattern' (letters, digits, _ * . - only)" -ExitCode 2 -OpArgs $opArgs }
    if ($NiagaraVersion -and $NiagaraVersion -notmatch '^\d+(\.\d+){0,3}$') { Fail-AgentScript -Ctx $ctx -Message "Invalid Niagara version '$NiagaraVersion' (expected e.g. 4.15 or 4.15.3.28)" -ExitCode 2 -OpArgs $opArgs }
    if ($NiagaraHome) {
        try { Test-NiagaraArgument -Kind LocalPath -Value $NiagaraHome | Out-Null } catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 2 -OpArgs $opArgs }
    }

    $homes = @(Find-NiagaraHomes -Config $ctx.config -HostInfo $ctx.host -Probe:($Probe -and -not $DryRun))
    $homeList = @($homes | ForEach-Object { [pscustomobject]@{ path = $_.path; version = $_.version; versionSource = $_.versionSource; origin = $_.origin } })
    if ($Action -eq 'homes') {
        Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; action = 'homes'; count = $homeList.Count; homes = $homeList; dryRun = [bool]$DryRun }) -Status $(if ($DryRun) { 'DRY_RUN' } else { 'SUCCESS' }) -OpArgs $opArgs
    }

    # The target host's runtime, when the caller wants nre to match it (plat details is a read).
    $target = $null
    if ($MatchHost) {
        $mh = $null
        try { $mh = Resolve-NiagaraHost -Config $ctx.config -Alias $MatchHost }
        catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 4 -Status DENIED -OpArgs $opArgs }
        if (-not (Test-NiagaraTier -HostInfo $mh -Tier read)) { Fail-AgentScript -Ctx $ctx -Message "TierNotAllowed: host '$MatchHost' does not allow tier 'read'" -ExitCode 4 -Status DENIED -OpArgs $opArgs }
        $target = [ordered]@{ alias = $mh.alias; hostord = $mh.hostord; runtime = $null; read = $null }
        if ($DryRun) {
            $target.read = 'not read in a dry run: the real run reads its Niagara Runtime with plat details, then picks the install with the same major.minor'
        } else {
            $cred = $null
            try { $cred = Get-NiagaraCredential -HostInfo $mh -Config $ctx.config -NonInteractive:$ctx.json }
            catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 5 -Status DENIED -OpArgs $opArgs }
            $reader = $null
            try { $reader = Select-NiagaraHome -Homes $homes -Preferred $mh.niagaraHome }
            catch { Fail-AgentScript -Ctx $ctx -Message "No Niagara install here to read '$MatchHost' with: $($_.Exception.Message)" -ExitCode 6 -OpArgs $opArgs }
            $details = $null
            try { $details = Get-PlatDetails -HostInfo (Use-NiagaraHome -HostInfo $mh -Path $reader.path) -Credential $cred }
            catch { Fail-AgentScript -Ctx $ctx -Message "Couldn't read '$MatchHost': $($_.Exception.Message)" -ExitCode 1 -OpArgs $opArgs }
            $target.runtime = if ($details.Contains('Niagara Runtime')) { ConvertFrom-NiagaraVersion -Text ([string]$details['Niagara Runtime']) } else { $null }
            $target.read = "plat details with the Niagara at $($reader.path)"
            if (-not $target.runtime) { Fail-AgentScript -Ctx $ctx -Message "plat details on '$MatchHost' did not report a Niagara Runtime version" -ExitCode 1 -OpArgs $opArgs }
        }
    }

    $sel = $null
    try {
        $sel = Select-NiagaraHome -Homes $homes -Path $NiagaraHome -Version $NiagaraVersion -MatchVersion $(if ($target) { $target.runtime } else { $null }) -Preferred $ctx.host.niagaraHome
    } catch {
        $msg = $_.Exception.Message
        Fail-AgentScript -Ctx $ctx -Message $msg -ExitCode $(if ($msg -like 'Invalid*') { 2 } else { 6 }) -OpArgs $opArgs
    }

    $nreArgs = switch ($Action) {
        'version' { @('-version') }
        'hostid' { @('-hostid') }
        'licenses' { @('-licenses') }
        'modules' { @("-modules:$ModulePattern") }
        'props' { @('-props') }
    }
    $selected = [pscustomobject]@{ path = $sel.path; version = $sel.version; versionSource = $sel.versionSource; because = $sel.reason; match = $sel.match; nre = $sel.nre }
    if ($DryRun) {
        Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{
                ok = $true; dryRun = $true; action = $Action; selected = $selected; target = $(if ($target) { [pscustomobject]$target } else { $null })
                argv = @($sel.nre) + $nreArgs; homes = $homeList
                note = 'nre only reads here; nothing on this machine or any station changes.'
            }) -Status DRY_RUN -OpArgs $opArgs
    }

    $r = Invoke-Nre -HostInfo (Use-NiagaraHome -HostInfo $ctx.host -Path $sel.path) -Arguments $nreArgs -TimeoutSec $TimeoutSec
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "nre $($nreArgs -join ' ') failed (exit $($r.exitCode)): $(@($r.lines | Select-Object -Last 5) -join ' | ')" -ExitCode 1 -OpArgs $opArgs }
    $parsed = switch ($Action) {
        'version' { [pscustomobject]@{ version = (ConvertFrom-NiagaraVersion -Text ($r.lines -join ' ')) } }
        'hostid' { [pscustomobject]@{ hostId = (($r.lines | Where-Object { $_.Trim() }) | Select-Object -Last 1) } }
        'modules' { @(ConvertFrom-NreModules -Lines $r.lines) }
        default { $null }
    }
    $verify = @{ niagaraHome = $sel.path; niagaraVersion = [string]$sel.version }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{
            ok = $true; action = $Action; selected = $selected; target = $(if ($target) { [pscustomobject]$target } else { $null })
            output = @($r.lines); parsed = $parsed; durationMs = $r.durationMs
        }) -OpArgs $opArgs -Verify $verify
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
