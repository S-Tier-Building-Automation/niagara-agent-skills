# Credential providers. The library never stores or logs credential values; it resolves them
# through a pluggable chain and hands a PSCredential to Invoke-Plat, which materialises the
# plaintext only inside the temporary `plat script` file (ACL-restricted, deleted in finally).
#
# Provider contract (providers/README.md):
#   env     -> NIAGARA_PLAT_USER / NIAGARA_PLAT_PASSWORD
#   script  -> run `<path> --host <alias>`; stdout is one JSON line {"user":"...","password":"..."};
#              non-zero exit refuses. (providers/op.example.ps1 shows a 1Password CLI variant.)
#   prompt  -> interactive Read-HostInfo (only when a console is attached and -NonInteractive is not set)
Set-StrictMode -Version Latest

function Get-NiagaraCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostInfo,
        $Config,
        [switch] $NonInteractive
    )
    $providers = @()
    if ($HostInfo.PSObject.Properties['credentials'] -and $HostInfo.credentials) { $providers += $HostInfo.credentials }
    if ($Config -and $Config.PSObject.Properties['credentials'] -and $Config.credentials) { $providers += $Config.credentials }
    $providers += [pscustomobject]@{ provider = 'env' }
    if (-not $NonInteractive) { $providers += [pscustomobject]@{ provider = 'prompt' } }

    foreach ($p in $providers) {
        $kind = if ($p.PSObject.Properties['provider']) { [string]$p.provider } else { 'env' }
        $cred = $null
        switch ($kind) {
            'env' { $cred = Get-CredentialFromEnv }
            'script' { $cred = Get-CredentialFromScript -Provider $p -HostAlias $HostInfo.alias }
            'prompt' { $cred = Get-CredentialFromPrompt -HostAlias $HostInfo.alias }
            default { Write-Verbose "Unknown credential provider '$kind' skipped" }
        }
        if ($cred) {
            Test-NiagaraArgument -Kind Credential -Value $cred.UserName | Out-Null
            return $cred
        }
    }
    throw [System.InvalidOperationException]::new("NoCredential: no provider supplied platform credentials for host '$($HostInfo.alias)'. Set NIAGARA_PLAT_USER/NIAGARA_PLAT_PASSWORD, configure a credential provider script, or run interactively.")
}

function Get-CredentialFromEnv {
    $u = [Environment]::GetEnvironmentVariable('NIAGARA_PLAT_USER')
    $p = [Environment]::GetEnvironmentVariable('NIAGARA_PLAT_PASSWORD')
    if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($p)) { return $null }
    $secure = ConvertTo-SecureString -String $p -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($u, $secure)
}

function Get-CredentialFromScript {
    param($Provider, [string] $HostAlias)
    if (-not $Provider.PSObject.Properties['path'] -or [string]::IsNullOrWhiteSpace($Provider.path)) { return $null }
    $path = Resolve-NiagaraPath -Path $Provider.path
    if (-not (Test-Path -LiteralPath $path)) { throw "Credential provider script not found: $path" }
    $global:LASTEXITCODE = 0
    $json = & $path --host $HostAlias 2>$null | Select-Object -Last 1
    if ($global:LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }
    $obj = $json | ConvertFrom-Json
    if (-not $obj.user -or -not $obj.password) { return $null }
    $secure = ConvertTo-SecureString -String ([string]$obj.password) -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential([string]$obj.user, $secure)
}

function Get-CredentialFromPrompt {
    param([string] $HostAlias)
    if (-not [Environment]::UserInteractive) { return $null }
    try {
        $u = Read-Host "Platform daemon user for $HostAlias"
        if ([string]::IsNullOrWhiteSpace($u)) { return $null }
        $p = Read-Host "Platform daemon password for $u@$HostAlias" -AsSecureString
        return New-Object System.Management.Automation.PSCredential($u, $p)
    } catch { return $null }
}

function ConvertTo-PlainText {
    # Only Invoke-Plat calls this, immediately before writing the temp script file.
    param([Parameter(Mandatory)] [securestring] $Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Resolve-NiagaraPath {
    param([string] $Path)
    if ($Path.StartsWith('~')) { return Join-Path ([Environment]::GetFolderPath('UserProfile')) $Path.Substring(1).TrimStart('/', '\') }
    return $Path
}
