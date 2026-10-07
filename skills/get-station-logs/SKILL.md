---
name: get-station-logs
description: Fetch a station's console.txt and recent logs from the host to a local folder (plat fget). Read-only.
---

# Get station logs

```
pwsh scripts/get-station-logs.ps1 -HostAlias <alias> -Station <name> [-Destination <dir>] -Json
```
Copies `stations/<name>/console.txt` from the host. Remember the flush rule: the file is written
when the station stops; use `watch-station` for live output.
