---
name: watch-station
description: Stream a station's (or the daemon's) console live until a pattern matches or a timeout; the only way to see console output before a station stops. Read-only.
---

# Watch station console

```
pwsh scripts/watch-station.ps1 -HostAlias <alias> -Station <name> [-Until 'Station Started'] [-Grep 'SEVERE|WARNING'] [-TimeoutSec 120] [-LogTo file] -Json
pwsh scripts/watch-station.ps1 -HostAlias <alias> -Daemon
```
Uses `plat watchstation` (with `-follow` when the version supports it). Returns the matched line,
the captured lines and whether it timed out. Prefer this over reading `console.txt`, which is only
flushed when a station stops.
