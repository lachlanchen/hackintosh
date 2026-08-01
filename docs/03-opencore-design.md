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

The current graphical picker uses the GoldenGate resource set, remains visible
for five seconds, and hides auxiliary entries by default. Sequoia is the
persistent startup disk. Windows Boot Manager remains independently preserved
and visible without becoming the default.

## Naming

The installed macOS volume is named `Sequoia-Dev`. The former `Mac` Monterey
volume group was retired after Sequoia acceptance and no longer appears in
APFS Preboot or Recovery metadata.

OpenCore may also show APFS Recovery. Never identify an entry by icon position
alone; use the volume label and verify the root volume after SSH returns.
