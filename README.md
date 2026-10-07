# niagara-agent-skills

Agent skills that let an AI assistant (Claude Code, Codex, or anything that can run a shell) operate a
**Niagara 4** host through the tools Tridium already ships: `plat.exe` (platform daemon client),
`nre.exe` (runtime environment) and the Windows service. Everything is wrapped in scripts with a host
allowlist, per-action confirmation, preflight/verify steps, dry runs and an append-only audit log.

What you get:

| Skill | Tier | What it does |
|---|---|---|
| `list-stations`, `inspect-host`, `verify-health`, `watch-station`, `get-station-logs`, `backup-station`, `read-audit-log` | read | never changes state |
| `start-station`, `stop-station`, `restart-station`, `tell-station` | station | daemon-level station control with status polling |
| `install-modules`, `install-dist`, `import-trust-cert` | install | signed-jar preflight, `plat moduleinstall`/`distinstall`, headless trust-store import |
| `manage-daemon`, `reboot-host`, `run-plat-script` | host | service control, host reboot (double confirmation), reviewed plat scripts |
| `run-remote` | - | runs any of the above on a remote host over SSH |

The `niagara-platform` skill is the router: it tells the agent which skill to use, when to ask for
confirmation, and how to report.

## Requirements

- A licensed Niagara 4 installation on the machine that runs the scripts (4.10 to 4.15 tested
  against 4.15; see `docs/versions.md`). This repo ships **no Tridium software or documentation**.
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1 on the host. Node 18+ only for `remote.mjs` and the tests.
- Platform daemon credentials for each host you allowlist (`docs/credentials.md`).

## Quick start

```powershell
git clone https://github.com/S-Tier-Building-Automation/niagara-agent-skills
cd niagara-agent-skills
pwsh scripts/config-init.ps1          # writes ~/.niagara-agent/config.json from config/example.config.json
# edit the file: niagaraHome, hosts { alias -> hostord, allow tiers, stations }
$env:NIAGARA_PLAT_USER = 'platform-user'; $env:NIAGARA_PLAT_PASSWORD = '...'   # or a provider script
pwsh scripts/list-stations.ps1 -HostAlias local -Json
pwsh scripts/restart-station.ps1 -HostAlias local -Station demo -DryRun
pwsh scripts/restart-station.ps1 -HostAlias local -Station demo -Confirmed
```

### As a Claude Code plugin

```
/plugin marketplace add S-Tier-Building-Automation/niagara-agent-skills
/plugin install niagara-agent-skills@niagara-agent-skills
```

### As a Codex plugin

Add this repository to your `.agents/plugins/marketplace.json` (the repo ships one) or point Codex
at the `.codex-plugin/plugin.json`.

## How it is safe

See `docs/safety-model.md`. In short: hosts and tiers are allowlisted in a config you own; every
state-changing script exits 3 until re-run with `-Confirmed`; credentials come from a provider chain
and never touch argv or logs (plat is driven through a temporary, ACL-restricted script file);
every run writes a redacted JSONL audit record; destructive scripts preflight, verify and report.

## Exit codes

`0` ok, `1` failed, `2` bad arguments, `3` needs confirmation, `4` host/station not allowlisted,
`5` no credential, `6` preflight failed, `7` verify failed, `124` timeout.

## Layout

```
skills/<name>/SKILL.md   what the agent reads
scripts/<name>.ps1       what the agent runs (all support -Json, -DryRun; destructive ones -Confirmed)
scripts/remote.mjs       run a script on a remote host over SSH
lib/*.ps1                plat/nre wrappers, parsers, validators, credentials, audit
providers/               credential provider contract + examples
config/                  example config + JSON schema
java/TrustImport.java    headless user-trust-store import run under the NRE
tests/                   Pester + node:test suites, fixtures captured from real plat/nre output
docs/                    safety model, credentials, remote use, versions, limitations
```

## Contributing

Issues and PRs welcome (`CONTRIBUTING.md`). Keep it generic: no site names, hostnames, vault paths
or credentials; CI greps for them. Niagara and Tridium are trademarks of Tridium, Inc.; this project
is independent (`NOTICE`).

License: Apache-2.0.
