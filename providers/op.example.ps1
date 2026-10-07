# Example provider: 1Password CLI. Copy, edit the item references, keep it OUTSIDE the repo.
# Provider contract: invoked as `<provider> --host <alias>`; prints one JSON line {"user","password"}; non-zero exit refuses.
param([Parameter(ValueFromRemainingArguments)] [string[]] $Rest)
$HostAlias = ''
for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq '--host' -and $i + 1 -lt $Rest.Count) { $HostAlias = $Rest[$i + 1] } }
$map = @{ 'local' = 'op://Vault/Niagara host/platform'; 'jace-1' = 'op://Vault/JACE 1/platform' }
if (-not $map.ContainsKey($HostAlias)) { exit 1 }
$ref = $map[$HostAlias]
$u = & op read "$ref/username" 2>$null; $p = & op read "$ref/password" 2>$null
if ($LASTEXITCODE -ne 0 -or -not $u -or -not $p) { exit 1 }
@{ user = $u; password = $p } | ConvertTo-Json -Compress
