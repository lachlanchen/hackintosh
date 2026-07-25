# OpenCore Design

## Verified Component Set

| Component | Version |
| --- | --- |
| OpenCore | 1.0.7 |
| Lilu | 1.7.2 |
| WhateverGreen | 1.7.0 |
| VirtualSMC / SMCProcessor | 1.3.7 |
| AppleALC | 1.9.7 |
| RestrictEvents | 1.1.6 |
| IntelMausi | 1.0.8 |

AMFIPass and RSRHelper were initially added for the OCLP root-patch experiment.
They are no longer part of the desired final design and should be removed only
after a separately validated EFI candidate proves Sequoia still boots.

## Invariants

- Preserve board-specific ACPI, USB mapping, audio, Ethernet, and PlatformInfo.
- Keep Lilu before all Lilu plugins.
- Keep WhateverGreen after Lilu.
- Validate every candidate with the matching `ocvalidate` release.
- Verify every enabled ACPI, driver, kext, and tool path exists.
- Generate and verify a complete SHA-256 manifest before promotion.
- Keep the previous live EFI in both private Linux storage and a recoverable
  on-disk location.

## Picker and Windows

During installation, `ScanPolicy` was limited to internal APFS so OpenCore would
not select Windows automatically. Windows Boot Manager remains in firmware.

Restoring a Windows picker entry is a separate change. Before enabling it:

1. Make Sequoia the persistent startup disk.
2. Confirm OpenCore's launcher entry survives a cold boot.
3. Add or expose Windows without changing the default selection.
4. Test a one-time Windows boot and a one-time return to Sequoia.

## Naming

The two macOS volumes are deliberately named:

- `Mac` for the protected Monterey recovery system
- `Sequoia-Dev` for the development system

OpenCore may also show APFS Recovery. Never identify an entry by icon position
alone; use the volume label and verify the root volume after SSH returns.

