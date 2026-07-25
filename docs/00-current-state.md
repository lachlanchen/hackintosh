# Current State

Status date: 2026-07-25

## Verified

- Hardware: Dell OptiPlex 7050, Intel Core i5-6500, Intel HD Graphics 530,
  16 GB memory.
- OpenCore: 1.0.7.
- Recovery system: macOS Monterey 12.7.6, build `21H1320`.
- Development system: macOS Sequoia 15.7.7, build `24G720`.
- Sequoia boots from its original Apple-sealed system snapshot.
- Sequoia graphics use `AppleIntelKBLGraphics` and
  `AppleIntelKBLGraphicsFramebuffer` 23.0.7.
- Sequoia reports 1536 MB dynamic VRAM and Metal 3.
- Monterey also boots and remains accelerated with the shared Kaby identity.
- Ethernet and SSH are functional after reboot.
- OCLP root-patch launch agents, daemons, app, and privileged helper were
  removed with the signed/notarized 2.4.1 uninstaller.
- The macOS APFS container is 240.2 GB and dynamically shared. At the verified
  checkpoint, 156.0 GB was unallocated inside the container.
- Windows remains on a separate GPT partition and retains its firmware boot
  manager.

## Boot-Critical Graphics Values

These values describe the sanitized intent, not a complete EFI:

| Property | Data |
| --- | --- |
| `AAPL,ig-platform-id` | `00001259` |
| `device-id` | `12590000` |
| `framebuffer-patch-enable` | `01000000` |
| `framebuffer-stolenmem` | `00003001` |
| `framebuffer-fbmem` | `00009000` |

`-igfxsklaskbl` is retained because the same EFI also boots Monterey. Current
WhateverGreen documentation says it is not required on macOS 13 or newer, but
it enforces Kaby Lake graphics drivers when the shared EFI boots older macOS.

## Deliberately Not Enabled

- OCLP graphics root patching
- automatic macOS installation
- Tahoe upgrade
- FileVault
- AirDrop, because no AWDL-capable Wi-Fi interface is present

## Pending

- Install and select universal Xcode 26.3.
- Install one compatible iOS Simulator runtime if required by the project.
- Clone GlassAgent and validate the iOS workspace.
- Optionally add a Broadcom BCM94360CD PCIe card for AirDrop, accepting that
  Sequoia requires a separately maintained legacy wireless patch.

