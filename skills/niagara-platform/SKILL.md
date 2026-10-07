---
name: niagara-platform
description: Entry point: operate a Niagara 4 host (stations, modules, daemon, logs) through its own command-line tools with allowlists, confirmation gates and an audit trail. Use when the user asks to list/start/stop/restart stations, install modules, read station logs, check host health, or manage the Niagara service.
---

# Niagara platform operations

All work goes through the scripts in `scripts/` (dot-sourcing `lib/plat.ps1`). Never call `plat.exe`
or `nre.exe` yourself.

## Before anything
1. Config: `~/.niagara-agent/config.json` (or `$env:NIAGARA_AGENT_CONFIG`). If missing, run
   `pwsh scripts/config-init.ps1` and ask the user to fill in the host allowlist. A host that is not
   listed cannot be targeted (exit 4).
2. Credentials come from the provider chain (`providers/README.md`). Never ask the user to paste a
   password into chat; point them at `NIAGARA_PLAT_USER/PASSWORD` or a provider script.
3. Pick the skill by task:
   - stations: `list-stations`, `start-station`, `stop-station`, `restart-station`, `watch-station`, `tell-station`
   - host: `inspect-host`, `verify-health`, `manage-daemon`, `reboot-host`
   - software: `install-modules`
   - logs/audit: `get-station-logs`, `read-audit-log`
   - remote host: `run-remote`

## Tiers and confirmation
`read` never changes state. `station`, `install`, `bog` and `host` do: their scripts exit **3**
until run with `-Confirmed`. Always ask the user first, quoting the host alias and what will happen,
and prefer `-DryRun` to show the plan. `reboot-host` additionally needs `-ConfirmHost <alias>`.

## Output and reporting
Every script supports `-Json` (one `NIAGARA_AGENT_RESULT_JSON:{...}` line) and writes an audit
record. Report: what ran, on which host, the preflight/verify results, and the exit code.
Exit codes: 0 ok, 1 failed, 2 args, 3 needs confirm, 4 host not allowlisted, 5 no credential,
6 preflight failed, 7 verify failed (rollback attempted), 124 timeout.
