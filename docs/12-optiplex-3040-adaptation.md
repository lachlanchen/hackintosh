# OptiPlex 3040 Adaptation

Status date: 2026-07-27

Status: machine-specific Monterey/Sequoia candidate built, validated, and
staged on an internal recovery ESP. It has not passed its first OpenCore or
macOS boot.

## Boundary

Do not copy the OptiPlex 7050 EFI to an OptiPlex 3040. The machines may share
a Skylake CPU generation and HD Graphics 530, but that does not establish
compatible ACPI tables, chipset routing, USB ports, Ethernet, audio, storage,
firmware settings, or SMBIOS data.

Never copy the 7050's PlatformInfo values. Every machine needs unique
Apple-format identifiers generated locally and kept outside Git.

## Staged 2026-07-27 State

### Audited hardware

| Area | Verified 3040 fact |
| --- | --- |
| Model / board | Dell OptiPlex 3040, board `0TK4W4` |
| Firmware | Dell `1.20.1`, UEFI, Secure Boot disabled |
| CPU | Intel Core i7-6700, 4 cores / 8 threads |
| Graphics | Intel HD Graphics 530, PCI device `0x1912` |
| Physical display path | DisplayPort, Dell 1920 x 1080 panel |
| Ethernet | Realtek RTL8111/8168, PCI device `0x8168` |
| Audio | Realtek ALC255, codec device `0x0255` |
| USB controller | Intel Sunrise Point, PCI device `0xA12F` |
| Memory | 8 GB DDR3L-1600 in one of two slots |

Wi-Fi, Bluetooth, every physical USB port, audio layout, and ACPI device paths
still require macOS-side validation.

### Current storage and fallback

- Disk 0 is a 1 TB Toshiba GPT data disk. Its Windows 7 files and the `D:`,
  `E:`, and `F:` partitions remain unchanged.
- The end of `G:` was reduced by exactly 4 GiB. The new final partition is a
  FAT32 ESP labelled `MACRECOVERY`.
- Disk 1 is a 256 GB Samsung SSD. Windows 10 Pro 22H2 remains in its existing
  101.1 GiB system partition with Windows Recovery intact.
- The SSD's existing 136.7 GiB unallocated extent is reserved for macOS. No
  APFS partition has been created yet.
- Both GPTs report no structural problems. Private GPT, BCD, firmware-entry,
  and partition-geometry backups exist on the 3040 and the independent Ubuntu
  workstation.
- Windows Boot Manager remains the firmware and BCD default. A validated
  OpenCore `BOOTAPP` entry exists, but its one-time boot sequence is not armed.

The recovery staging transaction encountered a Windows PowerShell SSH output
error after `Format-Volume` had committed successfully. Exact postcondition
checks showed the intended `G:` size, a correctly placed 4 GiB ESP, healthy
FAT32, and a valid GPT. The staging script now recognizes intermediate states
and resumes from the last committed postcondition instead of repeating a
storage operation.

### Candidate composition

| Component | Version |
| --- | --- |
| OpenCore | 1.0.7 |
| Lilu | 1.7.2 |
| WhateverGreen | 1.7.0 |
| VirtualSMC / SMCProcessor | 1.3.7 |
| AppleALC | 1.9.7 |
| RestrictEvents | 1.1.6 |
| RealtekRTL8111 | 3.0.0 |

The candidate uses only generic `SSDT-EC-USBX` and `SSDT-PLUG` tables for its
first boot. It does not contain 7050 HPET, USB-reset, connector, Ethernet,
wireless, or input-device patches. It has no final USB map yet.

The HD 530 is presented as Kaby Lake device `0x5912` with platform data
`00001259`, device data `12590000`, and `-igfxsklaskbl`. This is the same
high-level strategy proven on the 7050, but the 3040 intentionally does not
inherit the 7050 connector table.

The generated private PlatformInfo uses `iMac17,1` and a unique serial, MLB,
ROM, and system UUID. The identity is reused on rebuild and remains outside
Git. Rebuilding the candidate twice produced byte-identical EFI trees and
manifests. OpenCore 1.0.7 `ocvalidate` reports no issues.

The Apple Monterey recovery payload identified as `694-54378` contains a
623.4 MiB `BaseSystem.dmg`. Its complete 63-chunk Apple chunklist verification
passed. The staged DMG SHA-256 is
`79314d33b881c896c1afbcff929ff798b33489c6c4362dc1b20aaed1b6831119`.

### Installation sequence

1. Arm only the next Windows Boot Manager start for the verified OpenCore
   `BOOTAPP`; do not change the normal default.
2. At the physical picker, verify keyboard and display, then select
   `macOS Base System`.
3. Confirm Recovery sees Ethernet and both internal disks before writing APFS.
4. Create macOS only in the Samsung SSD's 136.7 GiB unallocated extent.
5. Install and validate Monterey first because Skylake graphics are native
   through Monterey.
6. Complete Setup Assistant as `lachlan`, then run the staged bootstrap to
   install the dedicated SSH public key, enable Remote Login, and disable
   system sleep.
7. Build a board-specific USB map and verify graphics, Ethernet, audio,
   shutdown, restart, and cold boot.
8. Preserve Monterey, then perform a separate in-place Sequoia upgrade using
   the already staged Kaby graphics identity.

The first physical boot, Recovery, macOS installation, and Sequoia upgrade are
pending. Do not describe this candidate as working until those gates pass.

## Historical Existing-OS Boot Boundary

The 2026-07-26 audit found a mixed firmware layout:

- Ubuntu starts in UEFI mode from an EFI System Partition on the SSD.
- Windows 7 is on a separate MBR hard disk with an active NTFS system
  partition, Windows 7 MBR code, an NTFS `BOOTMGR` partition boot record,
  `bootmgr`, BCD stores, and both BIOS and EFI Windows loader files.
- Dell firmware exposes the Windows disk as a legacy BBS hard-disk entry.
- Secure Boot is disabled.

The former custom GRUB entry attempted to load
`\EFI\Microsoft\Boot\bootmgfw.efi`. That is not the reliable boot path for this
MBR Windows installation. An EFI GRUB process also cannot directly transfer
control to an MBR BIOS boot sector because firmware cannot switch execution
modes in place.

The private repair therefore leaves every Windows sector and file unchanged.
It installs a small local EFI application on Ubuntu's ESP. When selected from
GRUB, the application writes the one-time UEFI `BootNext` variable for the
exact Dell legacy hard-disk entry and requests a cold restart. Firmware then
starts the existing Windows 7 MBR path.

The installer verifies the physical model, exact disk identity, NTFS system
partition, Dell BBS description, UEFI mode, and disabled Secure Boot. Before
changing GRUB or the ESP, it preserves:

- the Windows disk MBR;
- the Windows partition boot record;
- the complete pre-change EFI tree;
- the prior custom GRUB file;
- the firmware boot-entry listing;
- a SHA-256 manifest.

On 2026-07-26 the helper compiled as an x86-64 EFI application, GRUB accepted
the generated configuration, and Dell firmware accepted the one-time legacy
`BootNext` request. The 3040 did not return on its Linux network address after
restart. Because the Windows 7 installation does not have a verified driver
for the Linux USB Wi-Fi adapter, physical display confirmation remains
required before marking the Windows boot complete.

If firmware renumbers the legacy entry, regenerate the helper from Ubuntu
after rediscovering the exact BBS entry. Never hard-code a boot number copied
from another machine.

## Stage 0: Recovery First

Before changing firmware or disks:

1. Confirm the exact 3040 form factor: Micro, Small Form Factor, or Tower.
2. Keep its existing operating system bootable.
3. Create tested installer and recovery USB media.
4. Export or photograph every BIOS page.
5. Back up every existing EFI System Partition and generate SHA-256 manifests.
6. Confirm a physical keyboard, display, firmware boot menu, and a second
   computer are available.
7. Test booting the recovery media without installing.

Stop if the original OS, firmware picker, or backup cannot be restored.

## Stage 1: Exact Hardware Inventory

Record facts rather than relying on the Dell model label:

| Area | Required evidence |
| --- | --- |
| Board | service model, form factor, BIOS revision, chipset |
| CPU | exact processor and integrated GPU |
| Graphics | PCI ID, connector layout, monitor type and resolution |
| Ethernet | PCI ID and controller model |
| Wi-Fi/Bluetooth | controller, USB/PCI path, replaceability |
| Audio | codec and controller PCI path |
| Storage | SATA/NVMe controllers, disk model, sector size, partition map |
| USB | controller plus a port-by-port USB 2/3 map |
| ACPI | clean DSDT/SSDT dump from this machine |
| Firmware | SATA mode, Secure Boot, CSM, DVMT, CFG Lock, VT-d, wake settings |

Useful read-only sources include Windows Device Manager and `msinfo32`, a
Linux live environment with `lspci -nn`, `lsusb -t`, `lsblk`, and an OpenCore
ACPI dump. Redact serial numbers, MAC addresses, disk UUIDs, and host identity
before adding any excerpt to this repository.

## Stage 2: Build a Machine-Specific Candidate

Start from the current Dortania Skylake desktop guide and the release versions
recorded in this repository. Recreate the candidate from source:

1. Add only ACPI tables required by the audited 3040 firmware.
2. Select the Ethernet and audio kexts from detected controller IDs.
3. Build a 3040-specific USB map. Do not reuse the 7050 map.
4. Configure storage and power behavior from the 3040 evidence.
5. Generate unique PlatformInfo privately.
6. Validate the completed plist with the matching `ocvalidate`.
7. Verify every enabled ACPI, kext, driver, and tool path resolves.
8. Place the candidate on external media first; leave the internal EFI
   unchanged.

If the audited GPU is Skylake HD530, the 7050's high-level native Kaby identity
strategy may be relevant for macOS 13 and later. Its framebuffer values are
still only a hypothesis until the 3040 connector layout and memory behavior
are verified. Do not apply OCLP graphics root patches as a shortcut.

## Stage 3: Recovery Boot Gates

No usable removable drive was present during the 2026-07-27 preparation. The
same gated candidate was therefore placed on a small dedicated internal ESP
after complete GPT/BCD backups. Windows remains independently bootable and the
OpenCore path is selected through a one-time BCD sequence.

Use the recovery candidate to prove, in order:

1. OpenCore picker and recovery entry.
2. Existing operating-system boot and rollback.
3. Installer or recovery boot without disk changes.
4. Internal storage visibility.
5. Graphics output and acceleration.
6. Ethernet.
7. USB keyboard plus every mapped port.
8. Audio.
9. Shutdown, reboot, and cold boot.

Make one boot-critical change per test. Preserve the previous known-good
external EFI after each successful gate.

## Stage 4: OS Strategy

Prefer the same recovery-preserving pattern used on the 7050:

1. Keep a known-good macOS or original-OS path.
2. Install Monterey first into the SSD's currently unallocated space.
3. Verify the native Skylake baseline before optional device-specific work.
4. Enable Ethernet and SSH, then build the machine's final USB map.
5. Upgrade the proven Monterey system to Sequoia without removing Monterey
   recovery until repeated cold boots pass.

Sequoia 15.7.7 plus Xcode 26.3 is this repository's current validated
development boundary. Tahoe and newer Xcode lines require a new compatibility,
recovery, graphics, and update-policy audit.

## Acceptance Record

Do not label the 3040 setup reusable or complete until its record includes:

- exact sanitized hardware inventory;
- BIOS version and settings;
- OpenCore and kext versions;
- `ocvalidate` result;
- external and internal EFI checksum manifests in private storage;
- cold-boot, recovery, graphics, Ethernet, USB, audio, and shutdown evidence;
- preserved original OS and restoration instructions;
- selected Xcode and SDK versions;
- known unsupported functions and update policy.

Only the process in this document is portable. The resulting EFI remains
machine-specific.
