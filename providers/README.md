# Credential providers

The library resolves platform-daemon credentials through a chain and never stores or logs the values:

1. the host's `credentials` block, then the global `credentials` block in the config;
2. `env` — `NIAGARA_PLAT_USER` / `NIAGARA_PLAT_PASSWORD`;
3. `prompt` — interactive `Read-Host` (only in an interactive session and never with `-Json`/`-DryRun`).

## Provider contract (`provider: "script"`)

Any executable (`.ps1`, `.sh`, binary) that:

- is called as `<path> --host <alias>`;
- prints **one JSON line** `{"user":"...","password":"..."}` on stdout and nothing secret on stderr;
- exits non-zero to refuse.

`env.ps1` and `op.example.ps1` (1Password CLI) are examples. Keep your provider outside the repo
(for example `~/.niagara-agent/providers/`) and reference it from the config.
