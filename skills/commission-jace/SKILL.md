---
name: commission-jace
description: Put module jars (for example a freshly built STierAPI-rt.jar) onto a remote JACE with plat moduleinstall from this machine's Niagara, then optionally restart the JACE's station and check its health URL. Shows a dry run of every step first. Changes state: ask the user, then pass -Confirmed.
---

# Commission a JACE

```
pwsh scripts/commission-jace.ps1 -HostAlias <jace alias> -Jar C:\path\STierAPI-rt.jar[,...] [-Station <name>] [-NiagaraVersion 4.15] -DryRun
pwsh scripts/commission-jace.ps1 -HostAlias <jace alias> -Jar C:\path\STierAPI-rt.jar[,...] [-Station <name>] -Confirmed -Json
```

Run it on a machine with Niagara (4.15 for a 4.15 JACE) that can reach the JACE's platform daemon
(port 5011 with `secure: true`). The JACE must be in the host allowlist with a remote `hostord`
(`ip:<address>`), `allow` including `install` (and `station` to restart), and its station in `stations`.

The dry run reads the JACE (`plat details`, `plat liststations`; nothing changes) and reports:
the JACE's Niagara version against this machine's, each jar's module name, size, SHA-256 and
signature check, the exact plat commands with the password masked, the stations on the JACE, the
health URL before, and anything that would block the install. Show the user that plan and get
their yes before `-Confirmed`.

With `-Confirmed` it copies the jars into `<niagaraHome>\modules` (existing copies kept as
`.bak-<timestamp>`), runs `plat moduleinstall`, and with `-Station` stops and starts that station,
waiting for each state, then polls `healthUrl`.

With several Niagara versions installed, it reads the JACE with the configured `niagaraHome`, then
uses the install with the JACE's major.minor (the plan's `niagaraHome` says which and why).
`-NiagaraVersion` or `-NiagaraHome` pick one yourself; see `invoke-nre`.

It refuses a local host (use `install-modules`), a station outside the allowlist, an unsigned jar
(unless `-SkipSignatureCheck`), and a JACE on a different Niagara major.minor than this machine
(unless `-AllowVersionMismatch`), because plat installs from this machine's software database and
may bring dependent modules with it.

It does not install a Niagara dist (`install-dist`), set TCP/IP, place licences, create users, or
import the signer's certificate into the JACE's trust store: a dev-signed jar needs that done first
in Workbench (Platform > Certificate Management).

Credentials come from the provider chain (`NIAGARA_PLAT_USER` / `NIAGARA_PLAT_PASSWORD`, a provider
script, or the interactive prompt). They reach plat only through the temporary, ACL-restricted
`plat script` file and never appear in output or the audit log.
