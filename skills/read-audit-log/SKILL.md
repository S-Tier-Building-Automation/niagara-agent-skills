---
name: read-audit-log
description: Query the local JSONL audit log that every skill run writes (who, what, which host, status, duration).
---

# Read the audit log

```
pwsh scripts/read-audit-log.ps1 [-Days 7] [-HostAlias x] [-Op restart-station] [-Status FAILURE] -Json
```
Records live under `~/.niagara-agent/logs/audit-<date>.jsonl` (`NIAGARA_AGENT_HOME` overrides).
Credential values and raw argv are never recorded.
