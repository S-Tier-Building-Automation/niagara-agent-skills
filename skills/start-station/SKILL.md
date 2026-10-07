---
name: start-station
description: Start a station through the platform daemon and wait until it is running. Changes state: ask the user, then pass -Confirmed.
---

# Start station

```
pwsh scripts/start-station.ps1 -HostAlias <alias> -Station <name> [-TimeoutSec 180] -Confirmed -Json
```
Ask the user: "Start station `<name>` on `<alias>` (`<hostord>`)? ". Without `-Confirmed` the script
exits 3 with the plan. Preflight checks the station exists (and is in the host's `stations`
allowlist when one is configured); verify polls `liststations` until `running`.
