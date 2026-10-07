<# .SYNOPSIS  Create ~/.niagara-agent/config.json from the example (never overwrites). #>
[CmdletBinding()]
param([string] $Path, [string] $NiagaraHome, [switch] $Json)
. (Join-Path $PSScriptRoot '_common.ps1')
if (-not $Path) { $Path = Join-Path (Get-NiagaraAgentHome) 'config.json' }
if (Test-Path -LiteralPath $Path) { Write-AgentResult -Json:$Json -ExitCode 2 -Result ([pscustomobject]@{ ok = $false; error = "Config already exists at $Path" }) }
$example = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'config' 'example.config.json') -Raw | ConvertFrom-Json
if ($NiagaraHome) { $example.niagaraHome = $NiagaraHome }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
$example | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
Write-AgentResult -Json:$Json -Result ([pscustomobject]@{ ok = $true; path = $Path; note = 'Edit the hosts allowlist and credential provider before running any skill.' })
