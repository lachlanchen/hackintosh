# Security and Private Data

Do not report secrets or attach raw EFI/configuration archives to an issue.
Before sharing diagnostics, remove:

- SMBIOS serial, MLB, ROM, SystemUUID, and board identity
- IP/MAC addresses and SSH host keys
- Apple IDs, cookies, tokens, signing identities, and provisioning profiles
- panic blobs and logs that contain user paths or identifiers

For a boot failure, provide only the macOS/OpenCore versions, sanitized panic
headline and backtrace symbols, changed setting, expected rollback, and whether
the known-good recovery volume still boots.

