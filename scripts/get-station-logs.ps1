<# .SYNOPSIS  Fetch a station's console.txt (and recent logs) from the host with plat fget. Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Station,
    [string] $Destination,
    [switch] $Recurse,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ station = $Station; destination = $Destination; recurse = [bool]$Recurse }
$ctx = Initialize-AgentScript -Op get-station-logs -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
    if (-not $Destination) { $Destination = Join-Path (Get-NiagaraAgentHome) (Join-Path 'logs' (Join-Path $ctx.host.alias ($Station + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))) }
    Test-NiagaraArgument -Kind LocalPath -Value $Destination | Out-Null
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $cred = Get-OptionalCredential -Ctx $ctx
    $remote = "stations/$Station/console.txt"
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = "plat fget $remote $Destination" }) -Status DRY_RUN -OpArgs $opArgs }
    # plat fget <srcPath>* <destPath>; -overwrite:all is a flag so it must precede positional args via the usage-checked path
    $r = Invoke-Plat -HostInfo $ctx.host -Command fget -Arguments @($remote, $Destination) -Tier read -Credential $cred -TimeoutSec 300
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "plat fget failed (exit $($r.exitCode)): $($r.lines -join ' | ')" -OpArgs $opArgs }
    $files = @(Get-ChildItem -LiteralPath $Destination -Recurse:$Recurse -File | ForEach-Object { $_.FullName })
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; station = $Station; destination = $Destination; files = $files; note = 'console.txt is only flushed when the station stops; use watch-station for a live stream.' }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
