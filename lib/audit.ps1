# Append-only JSONL audit log of every script run. Never records credential values or raw argv.
Set-StrictMode -Version Latest

$script:RedactPatterns = @('(?i)-pwd:\S+', '(?i)password\s*[:=]\s*\S+', '(?i)(foxs?|https?)://[^/@\s]+@', '(?i)op://\S+')

function Get-NiagaraAgentHome {
    $override = [Environment]::GetEnvironmentVariable('NIAGARA_AGENT_HOME')
    if ($override) { return $override }
    return Join-Path ([Environment]::GetFolderPath('UserProfile')) '.niagara-agent'
}

function Protect-AuditText {
    param([AllowNull()] [string] $Text)
    if ($null -eq $Text) { return $null }
    $t = $Text
    foreach ($p in $script:RedactPatterns) { $t = [regex]::Replace($t, $p, '[REDACTED]') }
    return $t
}

function New-AuditTrace {
    return ([guid]::NewGuid().ToString('N'))
}

function Write-AuditRecord {
    <#
    .SYNOPSIS
        Writes one audit record. Status: STARTED|SUCCESS|FAILURE|DENIED|TIMEOUT|DRY_RUN|NEEDS_CONFIRM|ROLLED_BACK
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Op,
        [Parameter(Mandatory)] [string] $Status,
        [string] $Tier = 'read',
        [string] $HostAlias = '',
        [string] $HostOrd = '',
        [hashtable] $OpArgs = @{},
        [string] $TraceId = (New-AuditTrace),
        [bool] $DryRun = $false,
        [bool] $Confirmed = $false,
        [int] $ExitCode = 0,
        [long] $DurationMs = 0,
        [hashtable] $Preflight = @{},
        [hashtable] $Verify = @{},
        [string] $Detail = ''
    )
    $agentHome = Get-NiagaraAgentHome
    $dir = Join-Path $agentHome 'logs'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $file = Join-Path $dir ("audit-" + (Get-Date -Format 'yyyy-MM-dd') + ".jsonl")
    $safeArgs = @{}
    foreach ($k in $OpArgs.Keys) { $safeArgs[$k] = Protect-AuditText -Text ([string]$OpArgs[$k]) }
    $actor = [Environment]::GetEnvironmentVariable('NIAGARA_AGENT_ACTOR')
    if (-not $actor) { $actor = "$([Environment]::UserName)@$([Environment]::MachineName)" }
    $record = [ordered]@{
        ts         = (Get-Date).ToUniversalTime().ToString('o')
        traceId    = $TraceId
        actor      = $actor
        agent      = ([Environment]::GetEnvironmentVariable('NIAGARA_AGENT_NAME') ?? 'manual')
        op         = $Op
        tier       = $Tier
        hostAlias  = $HostAlias
        hostord    = $HostOrd
        args       = $safeArgs
        dryRun     = $DryRun
        confirmed  = $Confirmed
        status     = $Status
        exitCode   = $ExitCode
        durationMs = $DurationMs
        preflight  = $Preflight
        verify     = $Verify
        detail     = (Protect-AuditText -Text $Detail)
        libVersion = '0.1.0'
    }
    ($record | ConvertTo-Json -Compress -Depth 6) | Add-Content -LiteralPath $file -Encoding utf8
    return $record
}

function Read-AuditRecords {
    param([int] $Days = 7, [string] $HostAlias, [string] $Op, [string] $Status)
    $dir = Join-Path (Get-NiagaraAgentHome) 'logs'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $since = (Get-Date).AddDays(-$Days)
    $records = @()
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'audit-*.jsonl' | Where-Object { $_.LastWriteTime -ge $since }) {
        foreach ($line in Get-Content -LiteralPath $f.FullName) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $records += ($line | ConvertFrom-Json) } catch { }
        }
    }
    if ($HostAlias) { $records = $records | Where-Object { $_.hostAlias -eq $HostAlias } }
    if ($Op) { $records = $records | Where-Object { $_.op -eq $Op } }
    if ($Status) { $records = $records | Where-Object { $_.status -eq $Status } }
    return @($records)
}
