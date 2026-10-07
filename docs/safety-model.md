# Safety model

An agent that can restart stations and install modules on a building controller needs more than a
prompt saying "be careful". The scripts enforce the following, independent of the agent:

| # | Condition | Mechanism |
|---|---|---|
| 1 | **Credential custodian is not the agent** | `lib/credentials.ps1` resolves platform credentials through a provider chain (config provider -> env -> prompt). The agent sees only a success status. Plaintext exists only inside the temporary `plat script -f:` file, ACL-restricted to the current user and deleted in `finally`. |
| 2 | **Separate process, validated argv** | Every token that reaches `plat.exe`/`nre.exe` passes `Test-NiagaraArgument` (no leading `-`, no quotes, no control chars, per-kind regex). Commands are a `[a-z]+` allowlist. |
| 3 | **Least privilege per host** | `~/.niagara-agent/config.json` lists hosts explicitly with allowed tiers (`read`, `station`, `install`, `bog`, `host`) and optionally which stations may be touched. Unknown host or tier: exit 4, nothing runs. |
| 4 | **Per-action confirmation** | State-changing scripts exit 3 (`NEEDS_CONFIRM`) until re-run with `-Confirmed`. `reboot-host` also needs `-ConfirmHost <alias>`. `-DryRun` prints the masked plan without spawning anything. |
| 5 | **Audit** | `lib/audit.ps1` appends a redacted JSONL record (`STARTED`, `SUCCESS`, `FAILURE`, `DENIED`, `NEEDS_CONFIRM`, `DRY_RUN`, `TIMEOUT`) with actor, trace id, host, tier, args, preflight and verify data to `~/.niagara-agent/logs/`. Credential values and raw argv are never recorded. |
| 6 | **Preflight, verify, rollback** | `install-modules` verifies jar signatures and records versions before/after; station scripts poll `liststations` until the expected state and (optionally) an HTTP health URL; `backup-station` hashes what it copied. Exit 6 = preflight failed, 7 = verify failed. |
| 7 | **Named owner** | The config carries an `owner`; audit records carry the actor. Who may run what is a human decision recorded in the config, not inferred by the agent. |

## What the agent is told

`skills/niagara-platform/SKILL.md` instructs the agent to quote the host alias and the action in its
confirmation question, to prefer `-DryRun` first, never to ask the user for a password in chat, and
to report exit codes honestly. The scripts enforce the same rules even if the agent ignores them.

## Threats considered

- **Argument injection** through station names, module names, messages, paths: validators.
- **Credential leakage** through process listings, shell history, logs, chat: no argv credentials,
  redacted audit, masked dry-run plans, `-Json` output never includes secrets.
- **Wrong host**: aliases resolve only through the allowlist; the ORD is printed in every confirmation.
- **Runaway automation**: confirmation per action, timeouts (`124`), single-command scripts; no
  scheduler or loop lives in this repo.
- **Untrusted module code**: `install-modules` refuses unsigned jars unless `-SkipSignatureCheck` is passed explicitly.
