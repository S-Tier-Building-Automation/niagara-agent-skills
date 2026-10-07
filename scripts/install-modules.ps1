<# .SYNOPSIS  Install/upgrade Niagara module jars on a host with plat moduleinstall after signature + lock preflight. Tier: install (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string[]] $Jar,
    [switch] $OutOfDate,
    [switch] $SkipSignatureCheck,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ jars = ($Jar -join ','); outOfDate = [bool]$OutOfDate }
$ctx = Initialize-AgentScript -Op install-modules -HostAlias $HostAlias -Tier install -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    $preflight = @()
    $names = @()
    foreach ($j in $Jar) {
        Test-NiagaraArgument -Kind LocalPath -Value $j | Out-Null
        if (-not (Test-Path -LiteralPath $j)) { Fail-AgentScript -Ctx $ctx -Message "Jar not found: $j" -ExitCode 6 -OpArgs $opArgs }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($j)
        Test-NiagaraArgument -Kind ModuleName -Value $name | Out-Null
        $names += $name
        $item = @{ jar = $j; module = $name; signed = $null }
        if (-not $SkipSignatureCheck) {
            $jarsigner = Get-Command jarsigner -ErrorAction SilentlyContinue
            if (-not $jarsigner -and $ctx.host.niagaraHome) { $candidate = Join-Path $ctx.host.niagaraHome 'jre\bin\jarsigner.exe'; if (Test-Path $candidate) { $jarsigner = $candidate } }
            if ($jarsigner) {
                $v = Invoke-NativeCapture -FilePath ([string]$jarsigner) -ArgumentList @('-verify', '-strict', $j) -TimeoutSec 120
                $item.signed = ($v.exitCode -eq 0)
                if (-not $item.signed) { Fail-AgentScript -Ctx $ctx -Message "jarsigner -verify -strict failed for $j (Niagara 4.9+ refuses unsigned or untrusted modules)" -ExitCode 6 -OpArgs $opArgs }
            } else { $item.signed = 'unchecked (jarsigner not found)' }
        }
        $preflight += [pscustomobject]$item
    }
    $before = @(Get-NreModules -HostInfo $ctx.host -Pattern '')
    $beforeMap = @{}; foreach ($m in $before) { $beforeMap[$m.name] = $m.version }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; preflight = $preflight; plan = "plat moduleinstall $(if ($OutOfDate) { '-ood ' })$($names -join ' ')"; installedBefore = @($names | ForEach-Object { @{ module = $_; version = $beforeMap[$_] } }) }) -Status DRY_RUN -OpArgs $opArgs }
    $cred = Get-OptionalCredential -Ctx $ctx
    # moduleinstall installs from the LOCAL software database: the jars must sit in <niagaraHome>\modules (or the sw folder) of the machine running plat.
    $modulesDir = Join-Path $ctx.host.niagaraHome 'modules'
    $staged = @()
    foreach ($j in $Jar) {
        $dest = Join-Path $modulesDir ([System.IO.Path]::GetFileName($j))
        if ((Resolve-Path $j).Path -ne $dest) {
            if (Test-Path -LiteralPath $dest) { $bak = "$dest.bak-$(Get-Date -Format yyyyMMddHHmmss)"; Copy-Item -LiteralPath $dest -Destination $bak -Force; $staged += @{ backup = $bak } }
            Copy-Item -LiteralPath $j -Destination $dest -Force
        }
        $staged += @{ staged = $dest }
    }
    $pargs = @(); if ($OutOfDate) { $pargs += '-ood' }
    $r = Invoke-Plat -HostInfo $ctx.host -Command moduleinstall -Arguments ($names) -Tier install -Credential $cred -TimeoutSec 900
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "plat moduleinstall failed (exit $($r.exitCode)): $($r.lines -join ' | ')" -ExitCode 7 -OpArgs $opArgs }
    $after = @(Get-NreModules -HostInfo $ctx.host -Pattern '')
    $afterMap = @{}; foreach ($m in $after) { $afterMap[$m.name] = $m.version }
    $verify = @{}; foreach ($n in $names) { $verify[$n] = "$($beforeMap[$n]) -> $($afterMap[$n])" }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; modules = $names; preflight = $preflight; staged = $staged; versions = $verify; output = $r.lines; note = 'Restart the station(s) that load these modules for the new code to take effect.' }) -OpArgs $opArgs -Verify $verify
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
