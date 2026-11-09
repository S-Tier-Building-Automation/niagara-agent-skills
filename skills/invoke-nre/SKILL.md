---
name: invoke-nre
description: Run nre (the Niagara Runtime Environment tool) from the right Niagara install on this machine, when several versions are installed side by side. Lists the installs, or reads the Niagara version, host ID, licences, installed modules or system properties. Read-only; it never starts a station, Workbench or any other program.
---

# Run nre from the right Niagara

```
pwsh scripts/invoke-nre.ps1 -Action homes -Json
pwsh scripts/invoke-nre.ps1 -Action version|hostid|licenses|modules|props [-ModulePattern STier*] -Json
    [-NiagaraVersion 4.15 | -NiagaraHome C:\Niagara\Niagara-4.15.3.28 | -MatchHost <alias>] [-HostAlias local] [-Probe] [-DryRun]
```

Every Niagara release ships its own `bin\nre.exe`, `bin\plat.exe` and `modules\` folder, and a
machine often has several (4.14 for one site, 4.15 for another, a branded build). This script finds
them and runs the one that fits the job.

`-Action homes` lists the installs, newest first: path, version and where the version came from
(`baja.jar` inside the install, or the folder name; `-Probe` also runs each `nre -version`).
It looks at the host's and config's `niagaraHome`, the config's `niagaraHomes`, `NIAGARA_HOME`, then
each folder under `niagaraSearchRoots`, `C:\Niagara`, `Program Files\Niagara` and `/opt/Niagara`.
Add a branded install's parent folder to `niagaraSearchRoots` if it lives elsewhere.

Which install runs nre (first rule that applies):

1. `-NiagaraHome <path>`: that install.
2. `-NiagaraVersion 4.15`: the newest installed 4.15.x (`4.15.1` narrows it further; `4.1` never matches 4.15).
3. `-MatchHost <alias>`: reads that host's runtime with `plat details` (needs its platform
   credentials, read tier) and picks an install with the same major.minor, preferring the same build.
   Exits 6 when this machine has no install of that major.minor.
4. The `niagaraHome` configured for `-HostAlias` (default `local`).
5. The only install, or the newest of several (the result says so; pass `-NiagaraVersion` to choose).

The result names the install it used and why (`selected.because`). `-DryRun` shows the install, the
exact nre command and the list of installs, and runs nothing.

Only the read switches are allowed (`-version`, `-hostid`, `-licenses`, `-modules:<pattern>`,
`-props`); anything that would launch a program through nre is refused. The host must be reached
locally (`transport: local`); for an SSH host run it there through `run-remote`.

`commission-jace` uses the same selection: when nothing is named it reads the JACE, then installs from
this machine's Niagara of the same major.minor, and its dry run reports which install it will use.
