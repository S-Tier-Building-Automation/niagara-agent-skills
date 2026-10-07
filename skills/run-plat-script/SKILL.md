---
name: run-plat-script
description: Run a reviewed multi-line plat script file (one plat subcommand per line, credentials injected by the library). Host tier: ask the user, then pass -Confirmed.
---

# Run a plat script

```
pwsh scripts/run-plat-script.ps1 -HostAlias <alias> -ScriptPath .\maintenance.plat -DryRun
pwsh scripts/run-plat-script.ps1 -HostAlias <alias> -ScriptPath .\maintenance.plat -Confirmed -Json
```
Lines must not contain `-usr:`/`-pwd:`; each line runs through the same validators as single
commands and stops at the first failure. Show the user the `-DryRun` command list before confirming.
