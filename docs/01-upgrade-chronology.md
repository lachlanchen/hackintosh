# Upgrade Chronology

This chronology records the work from the first remote audit to the verified
Sequoia desktop. Times and machine identifiers are intentionally omitted.

## 1. Establish Remote Recovery

1. Verified the changed SSH host key with the operator before replacing the
   stale known-host entry.
2. Created separate SSH aliases for the macOS and Windows installations because
   both operating systems use the same physical NIC/IP at different times.
3. Installed an SSH public key on macOS and retained Windows SSH access as the
   firmware/EFI recovery path.
4. Confirmed FileVault was off and Screen Sharing was available.

## 2. Audit the Original System

1. Identified a Hackintosh spoofed as `iMac17,1`, not genuine Apple hardware.
2. Recorded the actual Dell/Skylake hardware, disk layout, APFS volume group,
   Ethernet kext, GPU acceleration, SIP state, and power policy.
3. Confirmed Monterey 12.7.6 had working HD530 acceleration, 1536 MB VRAM, and
   Metal support.
4. Confirmed the disk contained separate Windows and OpenCore EFI partitions
   plus one macOS APFS container.

## 3. Preserve Recovery Material

1. Copied the complete live EFI to ignored local private storage.
2. Generated a SHA-256 manifest for every EFI file and verified the manifest.
3. Retained additional rollback copies on the Mac EFI partition and macOS home.
4. Added a Windows PowerShell restore script so the EFI could be restored even
   if neither macOS volume booted.

## 4. Build and Test OpenCore 1.0.7

1. Downloaded official OpenCore and current signed kext releases.
2. Updated Lilu, VirtualSMC, WhateverGreen, AppleALC, RestrictEvents, AMFIPass,
   and RSRHelper while preserving board ACPI, USB, networking, and PlatformInfo.
3. Validated the candidate with OpenCore 1.0.7 `ocvalidate`.
4. Promoted the candidate to the live EFI and verified binary hashes.
5. The first reboot fell through to Windows because firmware still preferred
   Windows Boot Manager.
6. Used Windows SSH and a one-time BCD OpenCore entry to return to OpenCore.
7. Limited OpenCore scanning to internal APFS while the upgrade was in progress,
   preventing accidental automatic Windows selection.
8. Confirmed the new kext versions, Ethernet, and the original Monterey GPU
   baseline after the test boot.

## 5. Acquire and Verify Sequoia

1. Installed the signed/notarized Mist utility.
2. Downloaded Apple catalog product for macOS Sequoia 15.7.7.
3. Assembled `/Applications/Install macOS Sequoia.app`.
4. Confirmed build `24G720`.
5. Independently verified `SharedSupport.dmg` before installation.

## 6. Clone Before Upgrading

1. Added a second System/Data APFS volume group in the existing container.
2. Used `asr restore --useReplication` to clone the running Monterey system.
3. Renamed the clone `Sequoia-Dev`.
4. Updated Preboot and verified the clone contained the user account, SSH key,
   installer, and recovery tools.
5. Blessed the clone for one boot and confirmed `/` belonged to the clone's
   volume group before starting installation.

## 7. Install Sequoia

1. Ran `startosinstall` on the booted clone with explicit license acceptance and
   authenticated user confirmation.
2. Monitored payload verification, UpdateBrain restore, sealed-system staging,
   and each reboot.
3. Confirmed Sequoia 15.7.7 build `24G720` returned on the clone.
4. Confirmed Ethernet and SSH worked before changing graphics.

## 8. Failed OCLP Graphics Experiment

1. Sequoia initially had no HD530 acceleration because Apple removed native
   Skylake graphics support after Monterey.
2. Applied OCLP 2.4.1's Intel Skylake root patch.
3. The machine entered a boot panic loop.
4. Booted the untouched Monterey volume from OpenCore to recover.
5. Extracted and decoded `aapl,panic-info` from NVRAM.
6. The panic was an assertion in
   `AppleIntelSKLGraphicsFramebuffer::getUnifiedMemorySize()`, at
   `AppleIntelController.cpp:27500`.

## 9. Recover the Sealed Snapshot

1. Mounted the Sequoia base system volume writable from Monterey.
2. Used `bless --last-sealed-snapshot` to select the original Apple OS update
   snapshot rather than the OCLP-created snapshot.
3. Verified `bless --info` named the original sealed snapshot.
4. Preserved the failed snapshot temporarily for diagnosis.

## 10. Native Kaby Lake Graphics Fix

1. Followed WhateverGreen guidance for Skylake on macOS 13 and newer.
2. Changed HD530 identity from Skylake `0x1912` to Kaby Lake `0x5912`.
3. Changed the platform ID from `0x19120000` to `0x59120000`.
4. Retained the shared-EFI `-igfxsklaskbl` boot argument.
5. Validated the config with OpenCore 1.0.7.
6. Booted Monterey first and confirmed Kaby drivers, 1536 MB VRAM, and Metal.
7. Booted Sequoia's original sealed snapshot.
8. Confirmed native Sequoia Kaby drivers, 1536 MB VRAM, Metal 3, desktop login,
   Ethernet, SSH, and no new panic record.

## 11. Remove Unsupported Root-Patch Automation

1. Downloaded the 160 KiB official OCLP 2.4.1 uninstaller.
2. Verified its Developer ID chain and Apple notarization.
3. Removed OCLP auto-patch agents, update/RSR daemons, app, and privileged
   helper.
4. Reconfirmed the system volume remained sealed and accelerated.
5. Set Sequoia as the persistent startup volume while preserving Monterey.

## 12. Stabilize Unattended Development

1. Disabled system, display, and disk sleep plus standby, automatic power-off,
   and Power Nap with `pmset`.
2. Disabled the current user's screensaver idle timer.
3. Verified the effective AC policy after the change.
4. Recovered an already-black display by asserting remote user activity with
   `caffeinate -u -t 10`.
