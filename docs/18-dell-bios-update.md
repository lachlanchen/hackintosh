# Dell OptiPlex BIOS Update Workflow

This workflow updates firmware without treating an operating-system identity
as proof of the physical computer model. That distinction matters on a
Hackintosh because OpenCore deliberately presents an Apple SMBIOS identity to
macOS.

The procedure was prepared for an OptiPlex 7050 on 2026-07-26. It documents the
method, not a claim that the firmware was flashed.

## Establish the Physical Identity

Inventory from Windows or Dell's F2 setup before selecting a package:

```powershell
Get-WmiObject Win32_ComputerSystem | Format-List Manufacturer,Model
Get-WmiObject Win32_BIOS | Format-List SMBIOSBIOSVersion,SerialNumber
```

Require an exact `OptiPlex 7050` model match. Keep the service tag in a private
report; do not commit it. Also record the current BIOS version and photograph
the F2 pages.

Do not infer the service tag or installed Dell BIOS from a spoofed macOS SMBIOS.

## Pin the Firmware Artifacts

For the OptiPlex 7050, Dell's current package at the checked date is BIOS
1.27.0, release `KMHPC`. The package page requires an intermediate update to
1.7.6 when the installed BIOS is older than 1.7.6.

Keep these roles distinct:

| Artifact | Role |
| --- | --- |
| Dell BIOS EXE 1.7.6 | Mandatory bridge only for versions older than 1.7.6 |
| Dell BIOS EXE 1.27.0 | Current update after the bridge boundary is satisfied |
| `BIOS_IMG.rcv` | Model-specific emergency recovery image |
| Dell Command Configure | Export comparable BIOS settings before and after |

Record each SHA-256 from Dell's package page and verify the local file before
every launch or USB copy. Proprietary firmware packages and recovery images do
not belong in this repository.

## Capture a Before State

Run the inventory locally from an Administrator console:

```powershell
manage-bde -status C:
bcdedit /enum firmware
msinfo32 /report bios-msinfo-before.txt
```

With Dell Command Configure installed, export all replicable settings:

```powershell
& 'C:\Program Files\Dell\Command Configure\X86_64\cctk.exe' `
  '-o=bios-settings-before.ini'
```

The exact installation path can vary. The private helper checks both
`Program Files` trees and the x86/x64 layouts.

Photograph these F2 settings even when an export succeeds:

- UEFI boot mode and boot sequence
- OpenCore/macOS EFI entry and Windows Boot Manager
- SATA operation
- Secure Boot
- USB configuration
- virtualization and VT-d
- TPM/PTT
- wake and power behavior

## Select One Update

Use the parsed physical BIOS version:

| Installed version | Action |
| --- | --- |
| Earlier than 1.7.6 | Flash 1.7.6 only, boot fully, and verify |
| 1.7.6 through 1.26.x | Flash 1.27.0 |
| 1.27.0 or newer | Do not select an updater |

Never chain the bridge and current package into one unattended operation. A
successful full boot between firmware changes preserves a clear recovery
boundary.

## Flash Locally

Use a stable AC supply, local display, and wired keyboard. Close active work.
Do not start a BIOS flash when remote access is the only control path.

If BitLocker protection is enabled, suspend its protectors for the required
restarts before launching the update:

```powershell
manage-bde -protectors -disable C: -RebootCount 2
```

Launch Dell's signed updater interactively and read its reported model,
installed version, target version, and result. Do not interrupt power or force
a restart while firmware programming is active.

Dell also supports **BIOS Flash Update** from the F12 menu using a FAT32 USB
drive. This path is independent of the installed operating system. Select only
the package chosen by the version table above.

## Reconcile Firmware Defaults

A BIOS update or recovery can reset settings and firmware boot variables.
Before booting macOS, compare the F2 configuration with the saved report and
photographs:

- UEFI boot mode remains selected.
- SATA operation matches the working installation. This machine normally uses
  AHCI, but the captured before state is authoritative.
- Secure Boot remains disabled for the documented OpenCore configuration.
- OpenCore/macOS EFI and Windows Boot Manager exist and have the intended order.
- USB, VT-x/VT-d, TPM/PTT, and wake settings match the known-good state.

Do not reset NVRAM as a routine part of the update. If the update removes or
reorders the OpenCore firmware entry, use F12 to select the internal OpenCore
EFI or Windows recovery path, then restore only the missing boot entry.

At the OpenCore picker, boot the protected Monterey recovery system first.
Verify Ethernet, SSH, graphics acceleration, and Metal. Then boot Sequoia and
repeat the checks.

## Recovery USB

Keep the exact model's `BIOS_IMG.rcv` at the root of a FAT32 USB drive. For a
Dell desktop, attach a wired keyboard, power on, and immediately hold Ctrl+Esc
until the BIOS Recovery screen appears.

The recovery image must match the physical model. Do not reuse an image from
another OptiPlex generation. Recovery is for a failed update, not a shortcut
around preflight.

## Automation Boundary

Useful automation:

- verify exact SHA-256 values
- require an exact WMI model match
- parse the installed BIOS and select one permitted package
- capture BitLocker, firmware-entry, system, and BIOS-setting reports
- stage the kit when the target OS next becomes reachable
- require typed confirmation before opening the updater
- verify the reported version and export settings after reboot

Unsafe automation:

- selecting a firmware package from a hostname or spoofed macOS model
- silently suspending disk protection
- flashing through remote-only access
- auto-rebooting a workstation with active work
- applying both bridge and final updates without a verified boot
- overwriting EFI partitions or resetting NVRAM during a routine BIOS update
