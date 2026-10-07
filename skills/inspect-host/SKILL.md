---
name: inspect-host
description: Report a Niagara host's identity: host ID, Niagara version, licences, installed modules (pattern) and platform details. Read-only.
---

# Inspect host

```
pwsh scripts/inspect-host.ps1 -HostAlias <alias> [-ModulePattern STier*] [-SkipDetails] -Json
```
Combines `nre -version -hostid -licenses -modules:<pattern>` (no credentials) with `plat details`
(needs daemon credentials; skip with `-SkipDetails`). Use it to answer "which Niagara version /
host ID / modules does this host have?" before installing anything.
