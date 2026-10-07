---
name: verify-health
description: HTTP health check of a host's configured healthUrl (status, latency, JSON body). Read-only; used as the verify step by other skills.
---

# Verify health

```
pwsh scripts/verify-health.ps1 -HostAlias <alias> [-Url https://host/stier/health] [-TimeoutSec 10] -Json
```
Exit 0 on HTTP 200, 1 otherwise. Self-signed certificates are tolerated (the probe is a liveness
check, not a trust decision).
