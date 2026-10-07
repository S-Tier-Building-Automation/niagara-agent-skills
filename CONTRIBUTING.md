# Contributing

- Keep it generic. No site names, hostnames, IPs, vault references, credentials or customer data.
  `npm run check:secrets` is the CI gate; it must stay green.
- Every script: `-Json`, `-DryRun`, `-ConfigPath`, exit codes from the README; state-changing ones
  gate on `-Confirmed` through `Initialize-AgentScript -Destructive`.
- Every new `plat` flag goes through `Test-PlatFlag`.
- Parsers are pure functions over string arrays; add a fixture under `tests/fixtures/` from a real
  install (redacted) and a Pester case.
- Run `npm test` (node:test + Pester) and `npm run lint` (PSScriptAnalyzer) before opening a PR.
- Conventional commit titles (`feat:`, `fix:`, `docs:`...).
