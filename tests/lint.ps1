# PSScriptAnalyzer over lib/, scripts/, providers/ (installs the module when missing).
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -AcceptLicense }
$root = Split-Path -Parent $PSScriptRoot
$exclude = @('PSAvoidUsingWriteHost', 'PSAvoidUsingConvertToSecureStringWithPlainText', 'PSUseShouldProcessForStateChangingFunctions', 'PSAvoidUsingPlainTextForPassword', 'PSUseSingularNouns', 'PSAvoidUsingPositionalParameters')
$results = @()
foreach ($d in 'lib', 'scripts', 'providers') {
    $results += Invoke-ScriptAnalyzer -Path (Join-Path $root $d) -Recurse -Severity Warning, Error -ExcludeRule $exclude
}
$results | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-String -Width 220 | Write-Output
if ($results | Where-Object Severity -eq 'Error') { exit 1 }
exit 0
