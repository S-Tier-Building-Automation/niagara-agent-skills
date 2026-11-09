# Changelog

## Unreleased

- `commission-jace`: install module jars on a remote JACE with `plat moduleinstall`, then optionally restart its station and poll its health URL. The dry run reads the JACE (details, stations), compares its Niagara version with this machine's, hashes and signature-checks each jar, and lists every plat command with the password masked. Refuses a local host, a station outside the allowlist, and a major.minor mismatch unless `-AllowVersionMismatch`.
- `ConvertFrom-NiagaraVersion` and `Compare-NiagaraVersion` parser helpers.

## 0.1.1 (2026-10-07)

- Fix: `Invoke-Plat` passed a Windows path to `plat script -f:`, which plat rejects (`Illegal char ':'`); it now uses the `/C:/dir/file` form. Verified live against Niagara 4.15.3.28 (credential script mode works).
- Docs: `credentialMode: script` is now verified on 4.15; the `argv` fallback stays available.

## 0.1.0 (2026-10-07)

- Initial public release: read / station / install / host tier scripts, credential provider chain,
  audit log, dry runs, remote execution over SSH, headless trust-store import, Pester + node tests.
