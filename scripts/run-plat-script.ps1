<# .SYNOPSIS  Run a reviewed multi-command plat script file (plat script -f:) against a host. Tier: host (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $ScriptPath,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ scriptPath = $ScriptPath }
$ctx = Initialize-AgentScript -Op run-plat-script -HostAlias $HostAlias -Tier host -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind LocalPath -Value $ScriptPath | Out-Null
    if (-not (Test-Path -LiteralPath $ScriptPath)) { Fail-AgentScript -Ctx $ctx -Message "Script not found: $ScriptPath" -ExitCode 6 -OpArgs $opArgs }
    $lines = @(Get-Content -LiteralPath $ScriptPath | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') })
    $commands = @($lines | ForEach-Object { ($_.Trim() -split '\s+')[0] })
    if ($lines | Where-Object { $_ -match '(?i)-(pwd|usr):' }) { Fail-AgentScript -Ctx $ctx -Message 'Script files must not embed -usr:/-pwd: (credentials are injected by the library)' -ExitCode 2 -OpArgs $opArgs }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; commands = $commands; lineCount = $lines.Count }) -Status DRY_RUN -OpArgs $opArgs }
    $cred = Get-OptionalCredential -Ctx $ctx
    $results = @()
    foreach ($l in $lines) {
        $parts = $l.Trim() -split '\s+'
        $cmd = $parts[0]; $rest = @($parts | Select-Object -Skip 1 | Where-Object { $_ -notmatch '^-(h|p|secure|noinput)' })
        $r = Invoke-Plat -HostInfo $ctx.host -Command $cmd -Arguments $rest -Tier host -Credential $cred -TimeoutSec 900
        $results += [pscustomobject]@{ command = $cmd; ok = $r.ok; exitCode = $r.exitCode; output = $r.lines }
        if (-not $r.ok) { break }
    }
    $ok = -not ($results | Where-Object { -not $_.ok })
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $ok; steps = $results }) -Status $(if ($ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($ok) { 0 } else { 1 }) -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
