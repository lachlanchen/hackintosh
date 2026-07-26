# Recovery Scripts

These helpers are intentionally narrow. They do not discover or modify a
machine's EFI automatically, do not contain machine identity, and do not reboot
an operating system.

## OpenCore config transactions

| Script | Host | Purpose |
| --- | --- | --- |
| `stage-opencore-config.sh` | macOS | Promote a candidate config with hash gates and rollback |
| `restore-opencore-config.sh` | macOS | Restore a known-good config with hash gates and rollback |
| `stage-opencore-config.ps1` | Windows | Promote a candidate through the Windows system EFI |
| `restore-opencore-config.ps1` | Windows | Restore a known-good config through the Windows system EFI |
| `verify-macos-installer.sh` | macOS | Verify a full installer without launching it |

The macOS scripts require an explicit EFI device. Example shape:

```bash
sudo ./scripts/stage-opencore-config.sh \
  <efi-device> \
  /private/path/to/candidate.plist \
  <candidate-sha256> \
  <current-live-sha256> \
  config.plist.known-good \
  config.plist.before-candidate
```

Restore shape:

```bash
sudo ./scripts/restore-opencore-config.sh \
  <efi-device> \
  <current-candidate-sha256> \
  <known-good-sha256> \
  config.plist.known-good \
  config.plist.used-candidate
```

The PowerShell scripts mount the Windows **system EFI partition** with
`mountvol /S`. This is appropriate only when that partition contains the
intended `EFI\OC\OpenCore.efi` and live `config.plist`. The expected live hash
is a second guard against selecting the wrong EFI, not a substitute for
checking the disk layout.

Run PowerShell from an elevated console:

```powershell
.\scripts\stage-opencore-config.ps1 `
  -SourceConfig C:\Private\candidate.plist `
  -ExpectedSourceSha256 <candidate-sha256> `
  -ExpectedLiveSha256 <current-live-sha256> `
  -BackupName config.plist.known-good `
  -PreservedLiveName config.plist.before-candidate
```

## Refusal behavior

The transaction helpers stop without promotion when:

- a hash is malformed or unexpected;
- a source, live, backup, or OpenCore binary is missing;
- a rollback filename is unsafe or already exists;
- the candidate changes during staging;
- the target does not look like an OpenCore EFI;
- final verification fails.

When final verification fails, the prior live config is moved back into place.
The script unmounts an EFI only when it mounted that EFI itself.

## Full-installer verification

Verify the exact target version and build before any installation:

```bash
./scripts/verify-macos-installer.sh \
  "/Applications/Install macOS Sequoia.app" \
  15.7.7 \
  24G720
```

The script mounts `SharedSupport.dmg` read-only and detaches it on exit. It
requires the expected version/build in internal MobileAsset metadata, verifies
the complete disk image and critical Apple executables, records the payload
SHA-256, and prints the installer's real `startosinstall --usage`.

Some Apple InstallAssistant wrappers use obsolete custom resource-envelope
rules and fail whole-app strict verification. The script reports that result
but still requires the independent disk-image, metadata, and critical-binary
checks. It never re-signs or modifies Apple's installer.

## Validation

Before committing changes:

```bash
bash -n scripts/*.sh
git diff --check
```

The Bash helpers are kept compatible with the Bash 3.2 shipped by Sonoma and
were syntax-checked there without mounting or changing an EFI. Both PowerShell
helpers were parsed successfully by Windows PowerShell 5.1 without mounting or
changing an EFI.

## Other scripts

- `audit-macos.sh` captures a read-only OS, APFS, graphics, network, developer
  tool, and power baseline.
- `decode-apple-panic.pl` decodes packed panic data preserved from NVRAM.

Read the matching recovery document before running any write-capable helper.
