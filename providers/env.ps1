# Example provider: environment variables.
# Provider contract: invoked as `<provider> --host <alias>`; prints one JSON line {"user","password"}; non-zero exit refuses.
param([Parameter(ValueFromRemainingArguments)] [string[]] $Rest)
$HostAlias = ''
for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq '--host' -and $i + 1 -lt $Rest.Count) { $HostAlias = $Rest[$i + 1] } }
$u = $env:NIAGARA_PLAT_USER; $p = $env:NIAGARA_PLAT_PASSWORD
if (-not $u -or -not $p) { exit 1 }
@{ user = $u; password = $p } | ConvertTo-Json -Compress
