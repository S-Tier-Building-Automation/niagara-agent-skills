---
name: install-dist
description: Install a Niagara distribution (.dist) file on a host with plat distinstall. Changes state and may restart the daemon: ask the user, then pass -Confirmed.
---

# Install dist

```
pwsh scripts/install-dist.ps1 -HostAlias <alias> -Dist C:\path\file.dist -Confirmed -Json
```
Dist installs can replace runtime files and restart the daemon or host. Ask explicitly, run `-DryRun`
first, and verify afterwards with `inspect-host` and `list-stations`.
