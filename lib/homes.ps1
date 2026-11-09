# Niagara installs on this machine: discovery, version detection and per-version selection.
# Every Niagara release ships its own bin\nre.exe, bin\plat.exe and modules\ (its software database),
# so the right tool for a job is the one from the install whose version matches the job: the
# version the caller names, or the major.minor of the host it works on.
Set-StrictMode -Version Latest

function Test-NiagaraOnWindows {
    return ($env:OS -eq 'Windows_NT') -or ((Test-Path variable:IsWindows) -and $IsWindows)
}

function Test-NiagaraHomeDir {
    <#
    .SYNOPSIS
        $true when the folder is a Niagara install: it has bin\nre.exe (or bin/nre).
    #>
    param([AllowEmptyString()] [AllowNull()] [string] $Path)
    if (-not $Path) { return $false }
    $bin = Join-Path $Path 'bin'
    return (Test-Path -LiteralPath (Join-Path $bin 'nre.exe')) -or (Test-Path -LiteralPath (Join-Path $bin 'nre'))
}

function ConvertTo-NiagaraVersionObject {
    param([AllowEmptyString()] [AllowNull()] [string] $Version)
    if (-not $Version -or $Version -notmatch '^\d+(\.\d+){1,3}$') { return $null }
    return [version]$Version
}

function Test-NiagaraVersionPrefix {
    <#
    .SYNOPSIS
        $true when Version starts with Prefix component by component: 4.15.3.28 matches 4, 4.15, 4.15.3 and 4.15.3.28, not 4.1.
    #>
    param([AllowEmptyString()] [AllowNull()] [string] $Version, [Parameter(Mandatory)] [string] $Prefix)
    if (-not $Version) { return $false }
    $v = $Version.Split('.'); $p = $Prefix.Split('.')
    if ($p.Count -gt $v.Count) { return $false }
    for ($i = 0; $i -lt $p.Count; $i++) { if ([int]$v[$i] -ne [int]$p[$i]) { return $false } }
    return $true
}

function Get-NiagaraHomeVersion {
    <#
    .SYNOPSIS
        Reads an install's version without running it: vendorVersion in modules\baja.jar's META-INF/module.xml,
        else the folder name (Niagara-4.15.3.28, Vykon-4.14). Returns $null when neither says.
    #>
    param([Parameter(Mandatory)] [string] $Path)
    $baja = Join-Path (Join-Path $Path 'modules') 'baja.jar'
    if (Test-Path -LiteralPath $baja) {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zip = [System.IO.Compression.ZipFile]::OpenRead($baja)
            try {
                $entry = $zip.GetEntry('META-INF/module.xml')
                if ($entry) {
                    $reader = New-Object System.IO.StreamReader($entry.Open())
                    try { $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
                    if ($xml -match 'vendorVersion\s*=\s*"(\d+\.\d+\.\d+(?:\.\d+)?)"') {
                        return [pscustomobject]@{ version = $Matches[1]; source = 'baja.jar' }
                    }
                }
            } finally { $zip.Dispose() }
        } catch { }
    }
    $leaf = Split-Path -Leaf $Path
    if ($leaf -match '(\d+\.\d+(?:\.\d+){0,2})') { return [pscustomobject]@{ version = $Matches[1]; source = 'folder name' } }
    return $null
}

function Get-NiagaraSearchRoot {
    <#
    .SYNOPSIS
        Folders whose children may be Niagara installs: niagaraSearchRoots from the config, then the usual install folders.
    #>
    param($Config)
    $roots = @()
    if ($Config -and $Config.PSObject.Properties['niagaraSearchRoots']) {
        foreach ($r in @($Config.niagaraSearchRoots)) { if ($r) { $roots += (Resolve-NiagaraPath -Path ([string]$r)) } }
    }
    if (Test-NiagaraOnWindows) {
        $roots += 'C:\Niagara'
        foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) { if ($pf) { $roots += (Join-Path $pf 'Niagara') } }
    } else {
        $roots += @('/opt/Niagara', '/opt/niagara')
    }
    return $roots
}

function New-NiagaraHomeRecord {
    param([Parameter(Mandatory)] [string] $Path, [string] $Origin = 'search')
    $bin = Join-Path $Path 'bin'
    $nre = if (Test-Path -LiteralPath (Join-Path $bin 'nre.exe')) { Join-Path $bin 'nre.exe' } else { Join-Path $bin 'nre' }
    $plat = if (Test-Path -LiteralPath (Join-Path $bin 'plat.exe')) { Join-Path $bin 'plat.exe' } elseif (Test-Path -LiteralPath (Join-Path $bin 'plat')) { Join-Path $bin 'plat' } else { $null }
    $v = Get-NiagaraHomeVersion -Path $Path
    return [pscustomobject]@{
        path          = $Path
        version       = $(if ($v) { $v.version } else { $null })
        versionSource = $(if ($v) { $v.source } else { $null })
        nre           = $nre
        plat          = $plat
        origin        = $Origin
    }
}

function Find-NiagaraHomes {
    <#
    .SYNOPSIS
        Lists the Niagara installs on this machine, newest version first.
    .DESCRIPTION
        Looks at, in order: the host's niagaraHome, the config's niagaraHome and niagaraHomes, $env:NIAGARA_HOME,
        then each child of every search root (niagaraSearchRoots, C:\Niagara, Program Files\Niagara, /opt/Niagara).
        Reads each version from the install itself without running it. -Probe also runs `nre -version` in each
        install (one JVM start per install) and reports what it says.
    #>
    [CmdletBinding()]
    param($Config, $HostInfo, [string[]] $ExtraPath = @(), [switch] $Probe, [int] $ProbeTimeoutSec = 120)
    $candidates = @()
    if ($HostInfo -and $HostInfo.PSObject.Properties['niagaraHome'] -and $HostInfo.niagaraHome) { $candidates += , @([string]$HostInfo.niagaraHome, 'host niagaraHome') }
    if ($Config -and $Config.PSObject.Properties['niagaraHome'] -and $Config.niagaraHome) { $candidates += , @([string]$Config.niagaraHome, 'config niagaraHome') }
    if ($Config -and $Config.PSObject.Properties['niagaraHomes']) { foreach ($p in @($Config.niagaraHomes)) { if ($p) { $candidates += , @([string]$p, 'config niagaraHomes') } } }
    foreach ($p in $ExtraPath) { if ($p) { $candidates += , @($p, 'named') } }
    $envHome = [Environment]::GetEnvironmentVariable('NIAGARA_HOME')
    if ($envHome) { $candidates += , @($envHome, 'NIAGARA_HOME') }
    foreach ($root in (Get-NiagaraSearchRoot -Config $Config)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $candidates += , @($root, 'search')
        foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) { $candidates += , @($d.FullName, 'search') }
    }
    $seen = @{}
    $homes = @()
    foreach ($c in $candidates) {
        $path = Resolve-NiagaraPath -Path $c[0]
        try { $path = [System.IO.Path]::GetFullPath($path).TrimEnd('\', '/') } catch { continue }
        $key = if (Test-NiagaraOnWindows) { $path.ToLowerInvariant() } else { $path }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (-not (Test-NiagaraHomeDir -Path $path)) { continue }
        $rec = New-NiagaraHomeRecord -Path $path -Origin $c[1]
        if ($Probe) {
            $probe = $null
            try {
                $run = Invoke-NativeCapture -FilePath $rec.nre -ArgumentList @('-version') -TimeoutSec $ProbeTimeoutSec
                $probe = ConvertFrom-NiagaraVersion -Text ((Split-NiagaraOutput -Lines $run.lines).payload -join ' ')
            } catch { }
            $rec | Add-Member -NotePropertyName nreVersion -NotePropertyValue $probe
            if ($probe) { $rec.version = $probe; $rec.versionSource = 'nre -version' }
        }
        $homes += $rec
    }
    $known = @($homes | Where-Object { $_.version } | Sort-Object -Property @{ Expression = { ConvertTo-NiagaraVersionObject -Version $_.version } } -Descending)
    $unknown = @($homes | Where-Object { -not $_.version })
    return @($known + $unknown)
}

function Select-NiagaraHome {
    <#
    .SYNOPSIS
        Picks the install to run a Niagara tool from, and says why.
    .DESCRIPTION
        First rule that applies wins:
          -Path          that install (it must have bin\nre)
          -Version       the newest install whose version starts with it (4.15 picks 4.15.3.28 over 4.15.1.16)
          -MatchVersion  an install with the same major.minor as the target host's runtime, preferring the same
                         build, then the same patch, then the newest; throws NoMatchingNiagaraHome when there is none
          -Preferred     the configured niagaraHome, when it is an install
          otherwise      the only install, or the newest of several (with a note to pass -Version)
        An install whose version could not be read is only ever picked by -Path or -Preferred.
    #>
    param(
        [AllowEmptyCollection()] [object[]] $Homes = @(),
        [string] $Path,
        [string] $Version,
        [string] $MatchVersion,
        [string] $Preferred
    )
    $all = @($Homes | Where-Object { $_ })
    $installed = (@($all | ForEach-Object { if ($_.version) { "$($_.version) at $($_.path)" } else { "unknown version at $($_.path)" } }) -join '; ')
    if (-not $installed) { $installed = 'none found' }
    function Get-Pick($rec, [string] $reason, $match = $null) {
        $o = $rec.PSObject.Copy()
        $o | Add-Member -NotePropertyName reason -NotePropertyValue $reason -Force
        $o | Add-Member -NotePropertyName match -NotePropertyValue $match -Force
        $o | Add-Member -NotePropertyName installs -NotePropertyValue $all.Count -Force
        return $o
    }
    function Find-ByPath([string] $p) {
        $full = [System.IO.Path]::GetFullPath((Resolve-NiagaraPath -Path $p)).TrimEnd('\', '/')
        $hit = $all | Where-Object { if (Test-NiagaraOnWindows) { $_.path -ieq $full } else { $_.path -ceq $full } } | Select-Object -First 1
        if ($hit) { return $hit }
        if (Test-NiagaraHomeDir -Path $full) { return (New-NiagaraHomeRecord -Path $full -Origin 'named') }
        return $null
    }
    if ($Path) {
        $hit = Find-ByPath $Path
        if (-not $hit) { throw "NoNiagaraHome: $Path is not a Niagara install (no bin\nre)" }
        return (Get-Pick $hit 'the install you named')
    }
    if ($Version) {
        if ($Version -notmatch '^\d+(\.\d+){0,3}$') { throw "Invalid Niagara version '$Version' (expected e.g. 4.15 or 4.15.3.28)" }
        $hit = @($all | Where-Object { Test-NiagaraVersionPrefix -Version $_.version -Prefix $Version }) | Select-Object -First 1
        if (-not $hit) { throw "NoMatchingNiagaraHome: no installed Niagara is $Version (installed: $installed)" }
        return (Get-Pick $hit "the newest install of Niagara $Version")
    }
    if ($MatchVersion) {
        $t = $MatchVersion.Split('.')
        if ($t.Count -lt 2) { throw "Invalid target version '$MatchVersion'" }
        $minor = "$($t[0]).$($t[1])"
        $same = @($all | Where-Object { Test-NiagaraVersionPrefix -Version $_.version -Prefix $minor })
        if (-not $same) { throw "NoMatchingNiagaraHome: the target runs Niagara $MatchVersion and no installed Niagara is $minor (installed: $installed)" }
        $exact = $same | Where-Object { $_.version -eq $MatchVersion } | Select-Object -First 1
        if ($exact) { return (Get-Pick $exact "the same Niagara build as the target ($MatchVersion)" 'match') }
        if ($t.Count -ge 3) {
            $patch = $same | Where-Object { Test-NiagaraVersionPrefix -Version $_.version -Prefix ("$minor.$($t[2])") } | Select-Object -First 1
            if ($patch) { return (Get-Pick $patch "the same Niagara patch as the target ($MatchVersion)" 'match') }
        }
        return (Get-Pick $same[0] "the newest Niagara $minor; the target runs $MatchVersion" 'patch-differs')
    }
    if ($Preferred) {
        $hit = Find-ByPath $Preferred
        if ($hit) { return (Get-Pick $hit 'the niagaraHome in the config') }
    }
    $known = @($all | Where-Object { $_.version })
    if ($all.Count -eq 0) { throw 'NoNiagaraHome: no Niagara install found. Set niagaraHome, niagaraHomes or niagaraSearchRoots in the config, or pass -NiagaraHome.' }
    if ($all.Count -eq 1) { return (Get-Pick $all[0] 'the only Niagara install on this machine') }
    if ($known.Count -eq 0) { throw "NoMatchingNiagaraHome: several installs and none has a readable version (installed: $installed); pass -NiagaraHome" }
    return (Get-Pick $known[0] "the newest of $($all.Count) installs; pass -NiagaraVersion to pick another")
}

function Use-NiagaraHome {
    <#
    .SYNOPSIS
        Returns a copy of a host record that runs its Niagara tools (plat, nre) from the given install.
    #>
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [string] $Path)
    $copy = $HostInfo.PSObject.Copy()
    $copy.niagaraHome = $Path
    return $copy
}
