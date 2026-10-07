<# .SYNOPSIS  Copy a station's config.bog (and optionally the whole station folder) from the host to a local backup folder with sha256. Tier: read. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $Station,
    [string] $Destination,
    [switch] $WholeStation,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ station = $Station; wholeStation = [bool]$WholeStation }
$ctx = Initialize-AgentScript -Op backup-station -HostAlias $HostAlias -Tier read -ConfigPath $ConfigPath -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
    $dest = if ($Destination) { $Destination } else { Join-Path (Get-NiagaraAgentHome) ("backups\$Station\" + (Get-Date -Format yyyyMMdd-HHmmss)) }
    Test-NiagaraArgument -Kind LocalPath -Value $dest | Out-Null
    $remote = if ($WholeStation) { "stations/$Station" } else { "stations/$Station/config.bog" }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = "plat fget $remote -> $dest" }) -Status DRY_RUN -OpArgs $opArgs }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $cred = Get-OptionalCredential -Ctx $ctx
    $fargs = @($remote, $dest); if ($WholeStation) { $fargs = @('-r') + $fargs }
    # plat fget <remotePath> <localDir>: the flag form (-r) is validated by the library against -usage before use.
    $r = Invoke-Plat -HostInfo $ctx.host -Command fget -Arguments @($remote, $dest) -Tier read -Credential $cred -TimeoutSec 900
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "plat fget failed (exit $($r.exitCode)): $($r.lines -join ' | ')" -OpArgs $opArgs }
    $files = @(Get-ChildItem -LiteralPath $dest -Recurse -File | ForEach-Object { [pscustomobject]@{ path = $_.FullName; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; station = $Station; destination = $dest; files = $files }) -OpArgs $opArgs -Verify @{ fileCount = $files.Count }
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
