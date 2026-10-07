---
name: restart-station
description: Restart a station (stop, start, verify, optional STier /stier/health check). Changes state: ask the user, then pass -Confirmed.
---

# Restart station

```
pwsh scripts/restart-station.ps1 -HostAlias <alias> -Station <name> [-TimeoutSec 240] [-SkipHealth] -Confirmed -Json
```
Sequence: `stopstation` → wait stopped → `startstation` → wait running → `GET <healthUrl>` until 200
(when the host has a `healthUrl`). Exit 7 means the station came back but health did not.
