---
name: manage-daemon
description: Status, stop, start or restart the Niagara platform Windows service (niagarad). Changes state except for status: ask the user, then pass -Confirmed.
---

# Manage the platform daemon

```
pwsh scripts/manage-daemon.ps1 -HostAlias local -Action status|stop|start|restart [-ServiceName Niagara] -Confirmed -Json
```
Runs on the host itself (elevated session required for changes). Stopping the service stops every
station it manages; prefer `stop-station` for one station. The script waits for `niagarad.exe` to
exit before returning from `stop`/`restart`.
