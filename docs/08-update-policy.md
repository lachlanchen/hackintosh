# Update Policy

## Validated Boundary

The validated operating system is macOS Sequoia 15.7.7 build `24G720`.
macOS Tahoe is not validated and is outside OCLP 2.4.1's supported target.

## Settings

- Automatic download may remain enabled.
- Automatic macOS installation must remain disabled.
- Never click a Tahoe upgrade without a new compatibility project.
- Disable or avoid any third-party auto-patcher that can modify the sealed
  system volume without an explicit checkpoint.

## Before Any macOS Update

1. Read OpenCore, Lilu, WhateverGreen, and RestrictEvents release notes.
2. Verify the update still has Intel and Kaby Lake graphics support.
3. Confirm free APFS space.
4. Copy and hash the live EFI.
5. Confirm Sequoia APFS Recovery starts from OpenCore's auxiliary picker.
6. Confirm Windows/OpenCore recovery works.
7. Create or preserve an APFS rollback snapshot and an independent data backup.
8. Install manually on Sequoia only.

## After Any macOS Update

1. Confirm build and root volume group.
2. Confirm system seal.
3. Confirm `AppleIntelKBLGraphics` and Metal.
4. Confirm Ethernet, audio, USB, sleep/wake, and cold boot.
5. Confirm Xcode and the iOS project still build.
6. Update the current-state document with date and evidence.
