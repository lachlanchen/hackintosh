# Surface Book 2 Sequoia Readiness

Checked 2026-07-26. This is a sanitized audit of a second machine. It does not
replace the OptiPlex 7050 current-state record and intentionally omits network
addresses, credentials, APFS UUIDs, SMBIOS identifiers, and the EFI itself.

## Outcome

The Surface Book 2 has enough storage for Sequoia, and its native Kaby Lake
graphics path is a plausible Sequoia path. The latest full installer offered by
Apple to the running system is macOS Sequoia 15.7.7 (`24G720`).

The upgrade was **not started**. A controlled unattended reboot proved that the
current OpenCore default is Windows, not macOS. Starting a multi-reboot macOS
installer in that state would strand the installation at the first restart.

## Audited state

| Area | Observed state |
| --- | --- |
| Hardware | Microsoft Surface Book 2, Intel Core i7-8650U, 16 GB RAM |
| Current macOS | Sonoma 14.8.3 (`23J220`) |
| Target offered by Apple | Sequoia 15.7.7 (`24G720`), approximately 14.6 GiB |
| SMBIOS model | `MacBookPro16,3` |
| Graphics | Intel UHD Graphics 620, Kaby Lake `0x5916`, 1536 MB, Metal 3 |
| APFS capacity | Approximately 121 GiB available; approximately 130 GB container free |
| Other systems | Windows and Linux occupy separate partitions |
| FileVault | Off |
| Time Machine | No destination configured |
| macOS recovery boundary | One visible Sonoma System/Data volume group |

Storage cleanup is not required merely to download or install Sequoia. The
absence of a separate known-good macOS volume or Time Machine destination is a
recovery issue, not a capacity issue.

## Bootloader and kext audit

The live EFI was mounted read-only, copied to private storage outside Git, and
verified file-for-file with SHA-256:

- 1,030 files
- approximately 147 MiB
- complete EFI, including OpenCore, Windows, Linux, and fallback boot files
- source and backup checksums matched for every file

The active `OpenCore.efi` exactly matches
OpenCore-Mod `1.0.6_79ea932f`, published 2025-08-17. The Surface integration
binary exactly matches BigSurface v6.5, the latest published BigSurface release.

Important versions include:

| Component | Version |
| --- | --- |
| OpenCore-Mod | 1.0.6, commit `79ea932f` |
| BigSurface | 1.1.0 bundle from v6.5 |
| Lilu | 1.7.2 |
| WhateverGreen | 1.7.1 |
| AppleALC | 1.9.7 |
| VirtualSMC | 1.3.8 |
| CPUFriend | 1.3.1 |
| BlueToolFixup | 2.6.9 |
| FeatureUnlock | 1.1.9 |

The active graphics properties present UHD 620 as native Kaby Lake device
`0x5916` with platform ID `0x59160000`. This avoids the unsupported OCLP
graphics-root-patch path. Do not apply OCLP graphics root patches to this EFI.

## Existing configuration caveats

The matching OpenCore-Mod 1.0.6 validator reports two pre-existing issues:

1. `Misc -> Boot -> SkipCustomEntryCheck` is absent from the older config.
2. `csr-active-config` uses a non-canonical two-byte value.

The system currently boots Sonoma with this configuration. These warnings
should be repaired in a separately tested EFI revision, not combined blindly
with the first Sequoia boot.

The more immediate unattended-update problem was:

- `ShowPicker = true`
- `Timeout = 0`, which disables automatic picker selection
- `RequestBootVarRouting = false`
- the effective automatic default selected Windows

Only `Timeout` was changed from `0` to `5`, after preserving both a complete
private EFI backup and an on-EFI copy of the prior config. The staged file was
XML-validated and SHA-256 checked before and after placement. A controlled
reboot then selected Windows automatically. This proved that a timeout alone
does not make macOS the default.

No installer was downloaded or launched after that result.

## Required recovery before an upgrade

An operator at the machine should:

1. enter the existing OpenCore picker and boot Sonoma;
2. select the Sonoma entry with `Ctrl+Enter` so OpenCore records it as default;
3. reboot twice without touching the keyboard;
4. verify that Sonoma and Remote Login return after both boots;
5. retain the five-second timeout until the complete upgrade is verified.

On Microsoft Surface hardware, holding Volume Up while powering on enters the
Surface UEFI. Use that only to reach the existing boot path; do not erase,
repartition, reset NVRAM, or change Windows boot files.

If the original no-timeout behavior is required, restore the preserved
pre-Sequoia config only after macOS is reachable and a separate boot test has
confirmed the desired default.

## Recommended lightweight upgrade path

Do not combine an OpenCore update, kext update, SIP redesign, and macOS update
in one reboot chain.

After the unattended Sonoma boot is proven:

1. retain the current, byte-identified OpenCore-Mod and kext set for the first
   Sequoia test;
2. download the exact Sequoia 15.7.7 full installer from Apple's
   `softwareupdate` catalog;
3. prefer a new APFS test volume sharing the existing container, rather than
   overwriting the only bootable macOS volume;
4. boot and validate Sequoia graphics, keyboard, touch, battery, audio, USB,
   sleep/wake, network, SSH, and Windows visibility;
5. make Sequoia the default only after two unattended reboot tests;
6. perform any OpenCore schema cleanup as a later, independently recoverable
   change.

A direct in-place upgrade is technically possible with the available free
space, but it is not the recovery-safe choice while the machine has no Time
Machine destination and only one known-good macOS volume group.

## Private artifacts

Machine-specific EFI files, checksum manifests, raw audit output, installer
payloads, credentials, and RPC diagnostics remain outside this repository.
They must never be committed.
