# Niagara versions

The wrappers call `plat <cmd> -usage` once per command per Niagara home and cache the advertised
flags under `~/.niagara-agent/cache/`. Scripts use `Test-PlatFlag` before adding optional flags
(`-follow` on `watchstation`, `-ood` on `moduleinstall`, `-r` on `fget`), so a flag that does not
exist on an older release is simply not sent.

| Version | Status | Notes |
|---|---|---|
| 4.15 | tested | fixtures under `tests/fixtures/*/4.15.3` captured from a real install |
| 4.10 - 4.14 | expected to work | same subcommand set; please add fixtures from your install |
| 4.0 - 4.9 | untested | `plat` existed but output formats may differ |
| AX (3.x) | unsupported | different tool set |

## Several versions on one machine

Each Niagara release has its own `nre`, `plat` and `modules\` folder. `lib/homes.ps1` finds the
installs (`Find-NiagaraHomes`), reads each version from `modules\baja.jar` (falling back to the
folder name), and `Select-NiagaraHome` picks one by path, by version prefix, or by the target
host's major.minor. `invoke-nre` and `commission-jace` use it; list extra installs with
`niagaraHomes` or `niagaraSearchRoots` in the config.

Capturing fixtures from your version (no credentials in the output):

```
plat liststations -usage > tests/fixtures/plat/<ver>/liststations-usage.txt
nre -version          > tests/fixtures/nre/<ver>/version.txt
```
Redact host IDs and hostnames before committing.
