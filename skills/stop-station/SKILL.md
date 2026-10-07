---
name: stop-station
description: Stop a station through the platform daemon and wait until it is stopped. Changes state: ask the user, then pass -Confirmed.
---

# Stop station

```
pwsh scripts/stop-station.ps1 -HostAlias <alias> -Station <name> [-TimeoutSec 120] -Confirmed -Json
```
Ask the user before running: stopping a station interrupts control. Verify polls until `stopped`.
After a stop, `console.txt` is flushed, so `get-station-logs` returns the complete log.
