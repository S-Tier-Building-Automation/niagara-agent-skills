---
name: reboot-host
description: Ask the platform daemon to reboot its host (plat reboothost). Highly disruptive: requires -Confirmed and -ConfirmHost <alias>.
---

# Reboot host

```
pwsh scripts/reboot-host.ps1 -HostAlias <alias> -Confirmed -ConfirmHost <alias> -Json
```
Double confirmation by design. Tell the user every station on the host will go down and that the
daemon needs several minutes to return; then verify with `list-stations` / `verify-health`.
