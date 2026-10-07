<# .SYNOPSIS  Query the local JSONL audit log written by every script. #>
[CmdletBinding()]
param([int] $Days = 7, [string] $HostAlias, [string] $Op, [string] $Status, [switch] $Json)
. (Join-Path $PSScriptRoot '_common.ps1')
$records = Read-AuditRecords -Days $Days -HostAlias $HostAlias -Op $Op -Status $Status
Write-AgentResult -Json:$Json -Result ([pscustomobject]@{ ok = $true; count = $records.Count; records = $records })
