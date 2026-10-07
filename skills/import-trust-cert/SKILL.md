---
name: import-trust-cert
description: Import a PEM certificate into the Niagara user trust store headlessly (no Workbench) so dev-signed modules load. Changes state: ask the user, then pass -Confirmed.
---

# Import a trust certificate

```
pwsh scripts/import-trust-cert.ps1 -HostAlias local -CertPath C:\certs\signer.pem -Alias my-signer -Confirmed -Json
```
Runs on the host itself (use `run-remote` otherwise). Compiles `java/TrustImport.java` with a JDK 8
`javac` and runs it under the Niagara JRE with the NRE security provider, so no store password is
needed. Restart the station afterwards for module verification to pick up the new anchor.
