---
name: backup-station
description: Copy a station's config.bog (or the whole station folder) from the host to a local, hashed backup folder with plat fget. Read-only.
---

# Backup station

```
pwsh scripts/backup-station.ps1 -HostAlias <alias> -Station <name> [-Destination <dir>] [-WholeStation] -Json
```
Default destination `~/.niagara-agent/backups/<station>/<timestamp>/`. The result lists every file
with size and sha256. Run it before any `install-modules` or config change.
