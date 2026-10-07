---
name: run-remote
description: Run any skill script on a remote Niagara host over SSH (ships lib + script, streams output, returns the JSON result and exit code).
---

# Run a skill on a remote host

```
node scripts/remote.mjs --host <ssh-alias> [--shell pwsh|powershell] [--forward-env NIAGARA_PLAT_USER,NIAGARA_PLAT_PASSWORD] -- restart-station.ps1 -HostAlias local -Station demo -Confirmed -Json
```
The library and the named script are sent over stdin to a temporary folder on the remote host, run
there with the forwarded arguments, and deleted afterwards. Credentials are resolved on the remote
host by its own provider unless `--forward-env` sends them inside the stdin payload (never argv).
The remote `-Host` alias refers to the remote host's own config; `local` is the usual choice.
