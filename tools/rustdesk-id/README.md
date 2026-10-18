# Bounded RustDesk identity reader

This branch contains one read-only helper for the existing OPS Machine Substrate / Black receiver owner.

## Purpose

Retrieve the current RustDesk ID from an **exact, already-admitted RustDesk 1.5.0 executable** by invoking the documented `--get-id` command. The result can support the normal public-server ID route as an alternative to waiting exclusively on direct-IP readiness.

## Boundaries

- No password is read, set, stored, or printed.
- No RustDesk configuration, account, service, startup item, firewall rule, Tailscale setting, or listener is changed.
- The caller must supply the exact expected file size, SHA-256, architecture, and receipt directory.
- Only the official 1.5.0 ARM64/x64 executable names are accepted.
- The helper refuses architecture/hash/size mismatch and elevated local execution.
- The helper preserves pre-existing same-binary processes and removes only query-created residue.
- A returned ID is private machine-routing data. Use `-RedactId` outside the private owner.
- Successful source/CI checks do not prove Black execution, receiver readiness, consent, connection, or control.

## Black candidate

The existing V6 package pins the official ARM64 artifact:

- file: `rustdesk-1.5.0-aarch64.exe`
- bytes: `23857008`
- SHA-256: `b660dbd7fd5ba4723447bb642dd95063f3a2abad76f5544d024f3b1c029dd87e`
- architecture: `Arm64`

Example private-owner invocation after current host/owner admission:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\Read-OPS-RustDeskIdentity.ps1 `
  -RustDeskPath '<exact admitted path>' `
  -ExpectedSha256 'b660dbd7fd5ba4723447bb642dd95063f3a2abad76f5544d024f3b1c029dd87e' `
  -ExpectedBytes 23857008 `
  -ExpectedArchitecture Arm64 `
  -ReceiptDirectory 'C:\MachineOps\receipts\rustdesk-identity-20261018'
```

This is a bounded identity read, not an unattended-access setup or a connection acceptance.
