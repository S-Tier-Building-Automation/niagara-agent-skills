# Pure parsers for plat.exe / nre.exe output. They take string arrays so they can be
# unit-tested against captured fixtures without a Niagara install.
Set-StrictMode -Version Latest

$script:NreNoisePattern = '^(INFO|WARNING|SEVERE|CONFIG|FINE|FINER|FINEST)\s*\[|^\s+at\s|Launching Niagara Runtime Environment'

function Split-NiagaraOutput {
    <#
    .SYNOPSIS
        Separates NRE boot/log chatter from the payload lines of a plat/nre run.
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $noise = New-Object System.Collections.Generic.List[string]
    $payload = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Lines)) {
        if ($null -eq $line) { continue }
        if ($line -match $script:NreNoisePattern) { $noise.Add($line) } else { $payload.Add($line) }
    }
    return [pscustomobject]@{ payload = $payload.ToArray(); noise = $noise.ToArray() }
}

function ConvertFrom-PlatStationStatus {
    param([string] $Raw)
    switch -Regex ($Raw) {
        '^running$' { return 'running' }
        '^(idle|stopped|disabled)$' { return 'stopped' }
        default { return 'unknown' }
    }
}

function ConvertFrom-PlatTable {
    <#
    .SYNOPSIS
        Parses a plat fixed-width table (header line, '----' rule, rows) into objects.
        Column boundaries come from the dashed rule, so headers with spaces ("Fox Port") work.
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $lines = @($Lines | Where-Object { $null -ne $_ -and $_.Trim() -ne '' })
    $ruleIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*-{3,}(\s+-{3,})*\s*$') { $ruleIndex = $i; break } }
    if ($ruleIndex -lt 1) { return @() }
    $header = $lines[$ruleIndex - 1]
    $rule = $lines[$ruleIndex]
    $columns = @()
    foreach ($m in [regex]::Matches($rule, '-+')) {
        $start = $m.Index
        $len = $m.Length
        $name = $header.Substring([Math]::Min($start, $header.Length), [Math]::Max(0, [Math]::Min($len, $header.Length - $start))).Trim()
        $columns += [pscustomobject]@{ name = $name; start = $start; length = $len }
    }
    $rows = @()
    for ($i = $ruleIndex + 1; $i -lt $lines.Count; $i++) {
        $row = $lines[$i]
        if ($row -match '^\s*-{3,}') { continue }
        $obj = [ordered]@{}
        for ($c = 0; $c -lt $columns.Count; $c++) {
            $col = $columns[$c]
            $isLast = ($c -eq $columns.Count - 1)
            if ($col.start -ge $row.Length) { $obj[$col.name] = ''; continue }
            $value = if ($isLast) { $row.Substring($col.start) } else { $row.Substring($col.start, [Math]::Min($col.length, $row.Length - $col.start)) }
            $obj[$col.name] = $value.Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function ConvertFrom-PlatListStations {
    <#
    .SYNOPSIS
        Parses `plat liststations` output into {name, status, rawStatus, foxPort, httpPort, autoStart, restartOnFailure}.
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $payload = (Split-NiagaraOutput -Lines $Lines).payload
    $rows = ConvertFrom-PlatTable -Lines $payload
    $out = @()
    foreach ($r in $rows) {
        $props = $r.PSObject.Properties
        $get = { param($n) $p = $props | Where-Object { $_.Name -eq $n } | Select-Object -First 1; if ($p) { $p.Value } else { '' } }
        $name = & $get 'Name'
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $rawStatus = (& $get 'Status')
        $fox = & $get 'Fox Port'; $http = & $get 'HTTP Port'
        $out += [pscustomobject]@{
            name             = $name
            status           = ConvertFrom-PlatStationStatus -Raw $rawStatus.ToLowerInvariant()
            rawStatus        = $rawStatus
            foxPort          = if ($fox -match '^\d+$') { [int]$fox } else { $null }
            httpPort         = if ($http -match '^\d+$') { [int]$http } else { $null }
            autoStart        = ((& $get 'Auto-Start') -match '^(true|yes)$')
            restartOnFailure = ((& $get 'Restart on Failure') -match '^(true|yes)$')
        }
    }
    return $out
}

function ConvertFrom-PlatKeyValue {
    <#
    .SYNOPSIS
        Parses "key: value" / "key = value" lines (plat details, nre -props) into an ordered hashtable.
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $payload = (Split-NiagaraOutput -Lines $Lines).payload
    $result = [ordered]@{}
    foreach ($line in $payload) {
        if ($line -match '^\s*([^:=]+?)\s*[:=]\s*(.*)$') {
            $key = $Matches[1].Trim(); $value = $Matches[2].Trim()
            if ($key -ne '') { $result[$key] = $value }
        }
    }
    return $result
}

function ConvertFrom-NreModules {
    <#
    .SYNOPSIS
        Parses `nre -modules:<pattern>` output into {name, version, vendor, raw}.
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $payload = (Split-NiagaraOutput -Lines $Lines).payload
    $out = @()
    foreach ($line in $payload) {
        $t = $line.Trim()
        if ($t -eq '' -or $t -match '^(usage|modules|-+)') { continue }
        $parts = $t -split '\s+'
        $name = $parts[0]
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9_]*(-rt|-wb|-ux|-se|-doc)?$') { continue }
        $version = if ($parts.Count -gt 1 -and $parts[1] -match '^\d') { $parts[1] } else { $null }
        $vendor = if ($parts.Count -gt 2) { ($parts[2..($parts.Count - 1)] -join ' ') } else { $null }
        $out += [pscustomobject]@{ name = $name; version = $version; vendor = $vendor; raw = $t }
    }
    return $out
}

function ConvertFrom-PlatUsage {
    <#
    .SYNOPSIS
        Extracts the flag names a `plat <cmd> -usage` text advertises (e.g. -ood, -follow, -overwrite).
    #>
    param([AllowEmptyCollection()] [string[]] $Lines)
    $flags = @()
    foreach ($line in @($Lines)) {
        if ($line -match '^\s{2}(-[A-Za-z?][A-Za-z0-9-]*)') { $flags += $Matches[1] }
    }
    return @($flags | Select-Object -Unique)
}
