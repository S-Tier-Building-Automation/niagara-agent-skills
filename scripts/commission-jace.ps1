<# .SYNOPSIS  Commission modules onto a remote JACE with plat moduleinstall, then optionally restart its station. Shows a dry run of every step first. Tier: install (+ station for the restart) (confirm). #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $HostAlias,
    [Parameter(Mandatory)] [string[]] $Jar,
    [string] $Station,
    [int] $TimeoutSec = 300,
    [switch] $SkipSignatureCheck,
    [switch] $AllowVersionMismatch,
    [string] $ConfigPath,
    [switch] $Confirmed,
    [switch] $DryRun,
    [switch] $Json
)
. (Join-Path $PSScriptRoot '_common.ps1')

# What this does NOT do (see docs/limitations.md): install a Niagara dist (use install-dist),
# set TCP/IP, place or bind licences, import the signer's certificate into the JACE's trust store,
# or create station users. It only moves module jars onto the JACE and restarts the station.
$opArgs = @{ jars = ($Jar -join ','); station = $Station; allowVersionMismatch = [bool]$AllowVersionMismatch }
$ctx = Initialize-AgentScript -Op commission-jace -HostAlias $HostAlias -Tier install -ConfigPath $ConfigPath -Destructive -Confirmed:$Confirmed -DryRun:$DryRun -Json:$Json -OpArgs $opArgs
try {
    if ($ctx.host.hostord -match '^(ip|host):(localhost|127\.0\.0\.1|::1)$' -or $ctx.host.hostord -like 'local:*') {
        Fail-AgentScript -Ctx $ctx -Message "commission-jace targets a remote JACE; '$($ctx.host.alias)' is this machine ($($ctx.host.hostord)). Use install-modules for a local host." -ExitCode 2 -OpArgs $opArgs
    }
    if ($ctx.host.transport -ne 'local') {
        Fail-AgentScript -Ctx $ctx -Message 'commission-jace runs plat on this machine against the JACE; run it through run-remote on the machine that has Niagara instead of transport=ssh' -ExitCode 2 -OpArgs $opArgs
    }
    if ($Station) {
        Test-NiagaraArgument -Kind StationName -Value $Station | Out-Null
        if (-not (Test-NiagaraTier -HostInfo $ctx.host -Tier station)) {
            Fail-AgentScript -Ctx $ctx -Message "TierNotAllowed: restarting '$Station' needs the station tier on host '$($ctx.host.alias)'" -ExitCode 4 -Status DENIED -OpArgs $opArgs
        }
        if (@($ctx.host.stations).Count -gt 0 -and $ctx.host.stations -notcontains $Station) {
            Fail-AgentScript -Ctx $ctx -Message "Station '$Station' is not in the allowlisted stations for host '$($ctx.host.alias)'" -ExitCode 4 -Status DENIED -OpArgs $opArgs
        }
    }

    # 1. The jars: present, a valid module name, signed (Niagara 4.9+ refuses unsigned modules).
    $preflight = @(); $names = @()
    foreach ($j in $Jar) {
        Test-NiagaraArgument -Kind LocalPath -Value $j | Out-Null
        if (-not (Test-Path -LiteralPath $j)) { Fail-AgentScript -Ctx $ctx -Message "Jar not found: $j" -ExitCode 6 -OpArgs $opArgs }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($j)
        Test-NiagaraArgument -Kind ModuleName -Value $name | Out-Null
        $names += $name
        $item = [ordered]@{ jar = $j; module = $name; bytes = (Get-Item -LiteralPath $j).Length; sha256 = (Get-FileHash -LiteralPath $j -Algorithm SHA256).Hash.ToLowerInvariant(); signed = $null }
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

    # 2. Read the JACE (read tier: nothing changes). Credentials come from the provider chain and only
    #    ever reach plat through the temporary, ACL-restricted `plat script` file.
    $cred = $null; $credNote = $null
    try { $cred = Get-NiagaraCredential -HostInfo $ctx.host -Config $ctx.config -NonInteractive:$ctx.json }
    catch { if (-not $DryRun) { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 5 -Status DENIED -OpArgs $opArgs }; $credNote = 'JACE not read: no platform credentials (set NIAGARA_PLAT_USER and NIAGARA_PLAT_PASSWORD, or run without -Json to be prompted)' }

    $jace = $null; $stations = @(); $readError = $null
    if ($cred) {
        try {
            $details = Get-PlatDetails -HostInfo $ctx.host -Credential $cred
            $jace = [ordered]@{}
            foreach ($k in @('Host Name', 'Niagara Runtime', 'Daemon Version', 'Architecture', 'Operating System', 'Host ID', 'Platform TLS Support')) { if ($details.Contains($k)) { $jace[$k] = $details[$k] } }
            $stations = @(Get-PlatStations -HostInfo $ctx.host -Credential $cred)
        } catch { $readError = $_.Exception.Message }
    }
    if ($readError -and -not $DryRun) { Fail-AgentScript -Ctx $ctx -Message "Couldn't read the JACE: $readError" -ExitCode 7 -OpArgs $opArgs }
    if ($Station -and $jace -and -not ($stations | Where-Object { $_.name -eq $Station })) {
        Fail-AgentScript -Ctx $ctx -Message "Station '$Station' is not on $($ctx.host.alias) (found: $(@($stations | ForEach-Object { $_.name }) -join ', '))" -ExitCode 6 -OpArgs $opArgs
    }

    # 3. plat moduleinstall installs from THIS machine's software database, so its Niagara should be the
    #    JACE's major.minor; otherwise plat may try to bring core modules across versions.
    $localVersion = $null
    try { $localVersion = ConvertFrom-NiagaraVersion -Text ((Invoke-Nre -HostInfo $ctx.host -Arguments @('-version')).lines -join ' ') } catch { }
    $versions = Compare-NiagaraVersion -Local $localVersion -Remote $(if ($jace) { ConvertFrom-NiagaraVersion -Text $jace['Niagara Runtime'] } else { $null })
    $blocked = @()
    if ($versions.verdict -eq 'mismatch' -and -not $AllowVersionMismatch) { $blocked += "Niagara $($versions.local) here and $($versions.remote) on the JACE differ in major.minor; install from a matching Niagara or pass -AllowVersionMismatch" }
    if ($versions.verdict -eq 'unknown' -and -not $DryRun) { $blocked += "Couldn't compare Niagara versions (here: $($versions.local), JACE: $($versions.remote))" }

    $health = $null
    if ($ctx.host.healthUrl) { $health = Test-StationHealth -Url $ctx.host.healthUrl -SkipCertificateCheck }

    $modulesDir = if ($ctx.host.niagaraHome) { Join-Path $ctx.host.niagaraHome 'modules' } else { '<niagaraHome>\modules' }
    $install = Invoke-Plat -HostInfo $ctx.host -Command moduleinstall -Arguments $names -Tier install -Credential $cred -NoCredential:(-not $cred) -DryRun
    $steps = @()
    foreach ($p in $preflight) { $steps += "copy $($p.jar) to $modulesDir (any existing copy kept as .bak-<timestamp>)" }
    $steps += "plat $($install.argv -join ' ')"
    if ($Station) {
        $steps += "plat stopstation $Station on $($ctx.host.hostord), wait for stopped"
        $steps += "plat startstation $Station on $($ctx.host.hostord), wait for running"
        if ($ctx.host.healthUrl) { $steps += "GET $($ctx.host.healthUrl)" }
    } else { $steps += "no station restart (pass -Station <name>); the new modules load at the next station start" }
    $notes = @(
        'plat may also install modules these jars depend on, from this machine''s Niagara.',
        'A dev-signed jar needs its signer certificate in the JACE''s trust store first (Workbench > Platform > Certificate Management); this script does not change the JACE''s trust store.',
        'The station is down between stop and start.'
    )
    $plan = [pscustomobject]@{
        target = [pscustomobject]@{ alias = $ctx.host.alias; hostord = $ctx.host.hostord; port = $ctx.host.port; secure = $ctx.host.secure }
        jace = $(if ($jace) { [pscustomobject]$jace } else { $null })
        jaceNote = $(if ($credNote) { $credNote } elseif ($readError) { "JACE not read: $readError" } else { $null })
        stations = @($stations | ForEach-Object { [pscustomobject]@{ name = $_.name; status = $_.status } })
        niagara = $versions
        jars = $preflight
        steps = $steps
        healthBefore = $(if ($health) { [pscustomobject]@{ ok = $health.ok; status = $health.status } } else { $null })
        blocked = $blocked
        notes = $notes
    }
    if ($DryRun) { Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{ ok = ($blocked.Count -eq 0); dryRun = $true; plan = $plan }) -Status DRY_RUN -OpArgs $opArgs }
    if ($blocked.Count -gt 0) { Fail-AgentScript -Ctx $ctx -Message ($blocked -join '; ') -ExitCode 6 -OpArgs $opArgs }

    # 4. Apply: stage, install, restart, verify.
    $staged = @()
    foreach ($j in $Jar) {
        $dest = Join-Path $modulesDir ([System.IO.Path]::GetFileName($j))
        if ((Resolve-Path $j).Path -ne $dest) {
            if (Test-Path -LiteralPath $dest) { $bak = "$dest.bak-$(Get-Date -Format yyyyMMddHHmmss)"; Copy-Item -LiteralPath $dest -Destination $bak -Force; $staged += @{ backup = $bak } }
            Copy-Item -LiteralPath $j -Destination $dest -Force
        }
        $staged += @{ staged = $dest }
    }
    $r = Invoke-Plat -HostInfo $ctx.host -Command moduleinstall -Arguments $names -Tier install -Credential $cred -TimeoutSec 900
    if (-not $r.ok) { Fail-AgentScript -Ctx $ctx -Message "plat moduleinstall failed (exit $($r.exitCode)): $($r.lines -join ' | ')" -ExitCode 7 -OpArgs $opArgs }

    $after = $null; $healthAfter = $null
    if ($Station) {
        $stop = Invoke-Plat -HostInfo $ctx.host -Command stopstation -Arguments @($Station) -Tier station -Credential $cred -TimeoutSec $TimeoutSec
        if (-not $stop.ok) { Fail-AgentScript -Ctx $ctx -Message "Modules installed, but plat stopstation failed (exit $($stop.exitCode)); restart '$Station' yourself" -ExitCode 7 -OpArgs $opArgs }
        Wait-StationStatus -HostInfo $ctx.host -Name $Station -Expected stopped -TimeoutSec $TimeoutSec -Credential $cred | Out-Null
        $start = Invoke-Plat -HostInfo $ctx.host -Command startstation -Arguments @($Station) -Tier station -Credential $cred -TimeoutSec $TimeoutSec
        if (-not $start.ok) { Fail-AgentScript -Ctx $ctx -Message "Modules installed and '$Station' stopped, but plat startstation failed (exit $($start.exitCode)); start it yourself" -ExitCode 7 -OpArgs $opArgs }
        $after = Wait-StationStatus -HostInfo $ctx.host -Name $Station -Expected running -TimeoutSec $TimeoutSec -Credential $cred
        if ($ctx.host.healthUrl) {
            $deadline = (Get-Date).AddSeconds([Math]::Min($TimeoutSec, 180))
            do { $healthAfter = Test-StationHealth -Url $ctx.host.healthUrl -SkipCertificateCheck; if ($healthAfter.ok) { break }; Start-Sleep -Seconds 5 } while ((Get-Date) -lt $deadline)
        }
    }
    $verify = @{ modules = ($names -join ','); station = $(if ($after) { $after.status } else { 'not restarted' }); health = $(if ($healthAfter) { $healthAfter.status } else { 'skipped' }) }
    Complete-AgentScript -Ctx $ctx -Result ([pscustomobject]@{
        ok = $true; modules = $names; staged = $staged; output = $r.lines
        station = $(if ($after) { [pscustomobject]@{ name = $Station; status = $after.status } } else { $null })
        health = $(if ($healthAfter) { [pscustomobject]@{ ok = $healthAfter.ok; status = $healthAfter.status; body = $(if ($healthAfter.PSObject.Properties['body']) { $healthAfter.body } else { $null }) } } else { $null })
        note = $(if ($Station) { $null } else { 'Restart the station that loads these modules for the new code to take effect.' })
    }) -OpArgs $opArgs -Verify $verify
} catch [System.TimeoutException] { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -ExitCode 7 -OpArgs $opArgs
} catch { Fail-AgentScript -Ctx $ctx -Message $_.Exception.Message -OpArgs $opArgs }
