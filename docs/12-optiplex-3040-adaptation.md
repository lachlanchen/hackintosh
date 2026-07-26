# OptiPlex 3040 Adaptation

Status date: 2026-07-26

Status: partial hardware and boot audit completed. The existing Ubuntu and
Windows 7 layout is recorded below; no Hackintosh candidate has been built.

## Boundary

Do not copy the OptiPlex 7050 EFI to an OptiPlex 3040. The machines may share
a Skylake CPU generation and HD Graphics 530, but that does not establish
compatible ACPI tables, chipset routing, USB ports, Ethernet, audio, storage,
firmware settings, or SMBIOS data.

Never copy the 7050's PlatformInfo values. Every machine needs unique
Apple-format identifiers generated locally and kept outside Git.

## Existing-OS Boot Boundary

The audited 3040 has a mixed firmware layout:

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

## Stage 3: External Boot Gates

Use the external candidate to prove, in order:

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
2. Install Sequoia into a separate APFS volume or a separate test disk.
3. Verify a native sealed system before optional device-specific work.
4. Verify Ethernet and SSH before changing graphics.
5. Promote an EFI to the internal partition only after repeated external cold
   boots.

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
