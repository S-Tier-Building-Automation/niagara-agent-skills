# Remote hosts

Run a script on another machine without installing anything there:

```
node scripts/remote.mjs --host sup-a --forward-env NIAGARA_PLAT_USER,NIAGARA_PLAT_PASSWORD -- restart-station.ps1 -HostAlias local -Station demo -Confirmed -Json
```

`remote.mjs` tars `lib/`, `scripts/_common.ps1` and the named script into a JSON payload, sends it
over `ssh <alias>` **on stdin**, and runs an encoded PowerShell bootstrap that unpacks into a temp
folder, runs the script, propagates the exit code and deletes the folder. Nothing secret is on the
remote command line.

- `--shell powershell` for hosts without PowerShell 7.
- `--forward-env A,B` sends the named local variables inside the payload. Without it the remote
  host resolves credentials with its own provider chain.
- `-HostAlias` refers to the **remote** host's config (`~/.niagara-agent/config.json` there);
  `local` is the normal choice. The remote config is the allowlist that counts.
- Requires `ssh` on the client, an SSH server on the host and non-interactive auth (`BatchMode=yes`).
