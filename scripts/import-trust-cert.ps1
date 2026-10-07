<# .SYNOPSIS  Import a certificate (PEM) into the Niagara USER trust store headlessly under the NRE. Tier: install (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string] $CertPath,
    [string] $Alias = 'agent-import',
    [string] $UserHome,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

$opArgs = @{ certPath = $CertPath; alias = $Alias }
$ctx = Initialize-AgentScript -Op import-trust-cert -HostAlias $HostAlias -Tier install -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    Test-NiagaraArgument -Kind LocalPath -Value $CertPath | Out-Null
    Test-NiagaraArgument -Kind Alias -Value $Alias | Out-Null
    if ($ctx.host.transport -ne 'local') { Fail-AgentScript -Ctx $ctx -Message 'import-trust-cert runs on the host itself; use run-remote for a remote host' -ExitCode 2 -OpArgs $opArgs }
    if (-not (Test-Path -LiteralPath $CertPath)) { Fail-AgentScript -Ctx $ctx -Message "Certificate not found: $CertPath" -ExitCode 6 -OpArgs $opArgs }
    $nh = $ctx.host.niagaraHome
    $uh = if ($UserHome) { $UserHome } else { $ctx.host.daemonUserHome }
    if (-not $nh -or -not $uh) { Fail-AgentScript -Ctx $ctx -Message 'niagaraHome and daemonUserHome must be configured' -ExitCode 2 -OpArgs $opArgs }
    $plan = "javac java/TrustImport.java; $nh\jre\bin\java -Dniagara.home=$nh -Dniagara.user.home=$uh TrustImport $CertPath $Alias"
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $true; dryRun = $true; plan = $plan }) -Status DRY_RUN -OpArgs $opArgs }
    $java = Join-Path $nh 'jre\bin\java.exe'; $javac = Join-Path $nh 'jre\bin\javac.exe'
    if (-not (Test-Path $javac)) { $javac = (Get-Command javac -ErrorAction SilentlyContinue).Source }
    if (-not $javac) { Fail-AgentScript -Ctx $ctx -Message 'javac not found (the Niagara JRE has none; install a JDK 8 and put javac on PATH)' -ExitCode 6 -OpArgs $opArgs }
    $out = Join-Path (Get-NiagaraAgentHome) 'tmp\trustimport'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $cp = "$nh\bin\ext\nre.jar;$nh\modules\baja.jar"
    $c = Invoke-NativeCapture -FilePath $javac -ArgumentList @('-cp', $cp, '-d', $out, (Join-Path (Split-Path -Parent $PSScriptRoot) 'java\TrustImport.java')) -TimeoutSec 120
    if ($c.exitCode -ne 0) { Fail-AgentScript -Ctx $ctx -Message "TrustImport compile failed: $($c.lines -join ' | ')" -ExitCode 6 -OpArgs $opArgs }
    # bcfips jars are FIPS-only; alongside bcstd they duplicate the BC provider (the NRE launcher excludes them too).
    $ext = (Get-ChildItem "$nh\bin\ext" -Recurse -Filter '*.jar' | Where-Object { $_.FullName -notmatch 'bcfips' } | ForEach-Object { $_.FullName }) -join ';'
    $env:PATH = "$nh\jre\bin;$nh\bin;$env:PATH"
    $r = Invoke-NativeCapture -FilePath $java -ArgumentList @('-Dniagara.platform.provider=com.tridium.nre.platform.NativePlatformProviderTridium', '-Dniagara.security.manager.disable', "-Dniagara.home=$nh", "-Dniagara.user.home=$uh", '-cp', "$cp;$ext;$out", 'TrustImport', $CertPath, $Alias) -TimeoutSec 180
    $ok = ($r.exitCode -eq 0)
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = $ok; alias = $Alias; output = (Split-NiagaraOutput -Lines $r.lines).payload }) -Status $(if ($ok) { 'SUCCESS' } else { 'FAILURE' }) -ExitCode $(if ($ok) { 0 } else { 1 }) -OpArgs $opArgs -Verify @{ exitCode = $r.exitCode }
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
