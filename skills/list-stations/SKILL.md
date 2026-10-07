---
name: list-stations
description: List the stations a Niagara platform daemon manages, with status and ports (plat liststations). Read-only.
---

# List stations

```
pwsh scripts/list-stations.ps1 -HostAlias <alias> [-Name <station>] [-Running] -Json
```
Returns `{count, stations:[{name,status,rawStatus,foxPort,httpPort,autoStart,restartOnFailure}]}`.
`status` is normalised to `running` / `stopped` / `unknown`; `rawStatus` keeps the daemon's word
(`idle`, `disabled`, ...). Read tier: no confirmation.
