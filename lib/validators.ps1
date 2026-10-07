# Argument validators for everything that reaches plat.exe / nre.exe argv.
# Modelled on the validators STier Connect uses before spawning plat (argument-injection guard):
# nothing may start with '-', contain whitespace, control characters, or a double quote.
Set-StrictMode -Version Latest

function Test-NiagaraArgument {
    <#
    .SYNOPSIS
        Validates one token before it is passed to plat.exe / nre.exe. Throws on failure.
    .PARAMETER Kind
        StationName | HostOrd | Credential | ModuleName | RemotePath | LocalPath | Message | Alias
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('StationName', 'HostOrd', 'Credential', 'ModuleName', 'RemotePath', 'LocalPath', 'Message', 'Alias')] [string] $Kind,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )
    if ([string]::IsNullOrEmpty($Value)) { throw "Invalid $Kind`: must not be empty" }
    if ($Value.StartsWith('-')) { throw "Invalid $Kind`: must not start with '-' (got '$Value')" }
    if ($Value.IndexOf('"') -ge 0) { throw "Invalid $Kind`: must not contain a double quote" }
    foreach ($c in $Value.ToCharArray()) {
        if ([char]::IsControl($c)) { throw "Invalid $Kind`: must not contain control characters" }
    }
    switch ($Kind) {
        'StationName' {
            if ($Value -notmatch '^[A-Za-z0-9_][A-Za-z0-9_-]*$') { throw "Invalid station name: only letters, digits, '_' and '-' are allowed (got '$Value')" }
        }
        'HostOrd' {
            if ($Value -match '\s') { throw "Invalid host ORD: must not contain whitespace" }
            if ($Value -notmatch '^(ip|host|local):') { throw "Invalid host ORD: expected ip:<host>, host:<name> or local: (got '$Value')" }
        }
        'Credential' {
            if ($Value -match '\s') { throw "Invalid credential: must not contain whitespace" }
        }
        'ModuleName' {
            if ($Value -notmatch '^[A-Za-z][A-Za-z0-9_]*(-rt|-wb|-ux|-se|-doc)?$') { throw "Invalid module name (got '$Value')" }
        }
        'RemotePath' {
            if ($Value -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid remote path: '..' segments are not allowed" }
        }
        'LocalPath' {
            if ($Value -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid local path: '..' segments are not allowed" }
        }
        'Alias' {
            if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "Invalid alias (got '$Value')" }
        }
        'Message' { }
    }
    return $true
}

function Test-NiagaraTier {
    <#
    .SYNOPSIS
        Returns $true when the host record allows the given operation tier.
    #>
    param([Parameter(Mandatory)] $HostInfo, [Parameter(Mandatory)] [ValidateSet('read', 'station', 'install', 'bog', 'host')] [string] $Tier)
    $allow = @()
    if ($HostInfo.PSObject.Properties['allow']) { $allow = @($HostInfo.allow) }
    return ($allow -contains $Tier)
}
