---
name: install-modules
description: Install or upgrade Niagara module jars on a host with plat moduleinstall after a signature and lock preflight, then verify with nre -modules. Changes state: ask the user, then pass -Confirmed.
---

# Install modules

```
pwsh scripts/install-modules.ps1 -HostAlias <alias> -Jar C:\path\Module-rt.jar[,...] [-OutOfDate] -Confirmed -Json
```
Preflight: the jar exists, `jarsigner -verify -strict` passes (Niagara 4.9+ refuses unsigned or
untrusted modules; `-SkipSignatureCheck` only for dev builds you trust), module versions before.
The jar is staged into `<niagaraHome>\modules` (previous copy backed up as `.bak-<timestamp>`),
`plat moduleinstall` runs, and the versions after are reported. Restart the stations that load the
module afterwards (`restart-station`). Run with `-DryRun` first and show the user the plan.
