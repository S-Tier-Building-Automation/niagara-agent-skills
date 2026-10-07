# Credentials

Platform daemon credentials (the ones Workbench's Platform connection uses) are needed for every
`plat` subcommand. The library resolves them in this order and stops at the first hit:

1. The host's own `credentials` block in the config.
2. The global `credentials` block.
3. Environment variables `NIAGARA_PLAT_USER` / `NIAGARA_PLAT_PASSWORD`.
4. An interactive prompt (only in an interactive console, never with `-Json` or `-DryRun`).

If nothing yields a credential the script exits **5** (`NoCredential`).

## Provider scripts

`{"provider":"script","path":"~/.niagara-agent/providers/vault.ps1"}` runs the file as
`<path> --host <alias>`. It must print one JSON line `{"user":"...","password":"..."}` and exit
non-zero to refuse. `providers/op.example.ps1` shows a 1Password CLI provider; `providers/env.ps1`
the env form. Keep real providers outside the repository.

## How plat receives them

`Invoke-Plat` writes a one-line `plat script` file containing the command with `-usr:`/`-pwd:`,
restricts the file's ACL to the current user (`icacls` on Windows, `chmod 600` elsewhere), runs
`plat script -f:<file>`, and deletes the file in `finally`. The credential never appears on the
command line, in `Get-Process` output, in the audit log or in the dry-run plan (`-pwd:********`).

`plat script -f:` takes a Niagara file path, so the library passes `/C:/dir/file` on Windows (verified on 4.15.3.28). If a Niagara version's `plat script` does not accept per-line credentials, `Invoke-Plat
-CredentialMode argv` falls back to the classic form; set `"credentialMode":"argv"` on the host
in the config to make that the default for that host.

## Station credentials

The scripts never log into a station (Fox or HTTP). Station users, passwords and roles belong to the
station's own API or to Workbench; see `docs/limitations.md`.
