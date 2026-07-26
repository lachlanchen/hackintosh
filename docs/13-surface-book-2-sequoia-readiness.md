# Surface Book 2 Sequoia Readiness

Checked 2026-07-26. This is a sanitized audit of a second machine. It does not
replace the OptiPlex 7050 current-state record and intentionally omits network
addresses, credentials, APFS UUIDs, SMBIOS identifiers, and the EFI itself.

## Outcome

The research verdict was **go for a normal in-place upgrade**, after proving
OpenCore boot-variable routing. The routing proof and upgrade were completed
on 2026-07-26.

The Surface Book 2 now runs Sequoia 15.7.7 (`24G720`). It returned unattended
through the installer reboots and a separate final reboot. The existing
account, home, login keychain, browser profiles, Xcode data, Windows
partition, and Linux partitions remain present.

The known Surface-input uncertainty did not occur. BigSurface v6.5 and its
existing VoodooInput 1.1.3 load on Sequoia; the type cover and built-in
trackpad enumerate through the expected drivers. The prepared VoodooInput
1.1.5 candidate was therefore not installed.

## Audited state

| Area | Observed state |
| --- | --- |
| Hardware | Microsoft Surface Book 2, Intel Core i7-8650U, 16 GB RAM |
| Previous macOS | Sonoma 14.8.3 (`23J220`) |
| Current macOS | Sequoia 15.7.7 (`24G720`) |
| SMBIOS model | `MacBookPro16,3` |
| Graphics | Intel UHD Graphics 620, Kaby Lake `0x5916`, 1536 MB, Metal 3 |
| APFS capacity after upgrade | Approximately 133 GiB available at `/`; approximately 143 GB container free after Apple removed the temporary full installers |
| Other systems | Windows and Linux occupy separate partitions |
| FileVault | Off |
| Time Machine | No destination configured |
| macOS recovery boundary | One visible Sonoma System/Data volume group |

Storage cleanup is not required merely to download or install Sequoia. The
absence of a separate known-good macOS volume or Time Machine destination is a
recovery issue, not a capacity issue.

## Compatibility evidence

| Area | Evidence | Confidence and boundary |
| --- | --- | --- |
| Apple model support | The live SMBIOS is `MacBookPro16,3`. Apple identifies that exact model and says its newest compatible OS is Sequoia. Apple also lists the corresponding 2020 two-port MacBook Pro in the Sequoia compatibility list. | High for installer/model checks. This does not make the Microsoft hardware Apple-supported. |
| CPU and graphics | The i7-8650U and UHD 620 are Kaby Lake-generation paths. UHD 620 is already running as native device `0x5916`, with 1536 MB and Metal 3. WhateverGreen 1.6.7 added macOS 15 constants; the live version is 1.7.1. No OCLP graphics root patch is involved. | High. Preserve the current properties for the first Sequoia boot. |
| OpenCore | The live binary exactly matches published OpenCore-Mod build `1.0.6_79ea932f`. It is newer than the upstream OpenCore 1.0.2 macOS 15 CPU-patch fix. Every enabled kext entry has an open `MinKernel`/`MaxKernel` range. Matching `ocvalidate` reports only two pre-existing config issues. | High for loading Sequoia; boot-variable routing must still be tested. |
| Core kexts | Lilu 1.6.8, WhateverGreen 1.6.7, AppleALC 1.9.1, VirtualSMC 1.3.3, BlueToolFixup 2.6.9, and FeatureUnlock 1.1.6 introduced explicit macOS 15 support. Every live version is that release or newer. | High for graphics patching, audio, SMC/battery framework, and Bluetooth injection. |
| Surface integration | BigSurface v6.5 explicitly includes Surface Book 2 support. A Sequoia trackpad regression reported on related Surface Laptop 3/Book 3 hardware was fixed by replacing embedded VoodooInput 1.1.3 with official 1.1.5. A signed 1.1.5 candidate is staged but not installed. | Medium. This is the main uncertainty. USB Surface/Keychron/NuPhy keyboard and mouse devices plus SSH remain available if built-in input fails. |
| Wi-Fi and wired recovery | Both live Realtek Wi-Fi kext trees are byte-for-byte identical to the current trees in the third-party Wireless USB package that lists Sequoia support. The independent wired path uses Apple's `AppleUSBNCMControl`/`AppleUSBNCMData` driver and is reachable by key-based SSH. | Medium for USB Wi-Fi; high for wired recovery. No driver replacement is needed before upgrading. |
| Xcode | The installed Xcode is 16.2. Apple's support matrix explicitly allows Xcode 16.2 on Sonoma 14.5 through Sequoia 15.x. | High. Existing Xcode should continue to run after the OS upgrade. |
| User continuity | The intended operation is a normal in-place upgrade of the existing APFS System/Data volume group. It does not use `--eraseinstall`. Apple documents that reinstalling macOS keeps apps and personal data. | High for the normal upgrade model, but it is not a substitute for a full data backup. |
| Camera and sleep | No camera was visible on Sonoma. Sleep/wake was not exercised during the unattended upgrade. | Camera absence is a pre-existing limitation. Sleep/wake remains a separate physical test. |

No exact public report proves every feature on this exact Surface Book 2,
OpenCore configuration, and Sequoia 15.7.7 build. The evidence supports the
upgrade, but does not turn a Hackintosh into a guaranteed platform.

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

The immediate unattended-update problem was:

- `ShowPicker = true`
- `Timeout = 5`
- `RequestBootVarRouting = false`
- the effective automatic default selected Windows

The timeout was changed from `0` to `5` after preserving both a complete
private EFI backup and an on-EFI copy of the prior config. A controlled reboot
then selected Windows automatically, proving that timeout alone did not route
installer reboots.

The final transaction used an APFS-only bootstrap with
`RequestBootVarRouting = true`, initialized the current macOS startup target
with `bless`, and promoted a final config whose only functional difference
from the known-good config was `RequestBootVarRouting = true`. Sonoma returned
unattended before the installer. Sequoia then returned through the installer
and a clean post-upgrade reboot with the same final config.

## Completed boot-routing proof

Before launching the installer, the following sequence was completed:

1. stage the already validated APFS-only routed bootstrap;
2. reboot and confirm that the restricted bootstrap returns to Sonoma;
3. initialize the macOS startup choice through OpenCore with
   `sudo bless --mount / --setBoot --verbose`;
4. promote the final candidate whose only functional change is
   `RequestBootVarRouting = true`;
5. verify an unattended return to Sonoma;
6. retain the five-second timeout until Sequoia is fully verified.

The independently verified Windows `bootsequence` recovery remained available
but was not needed during this final routing sequence.

On Microsoft Surface hardware, holding Volume Up while powering on enters the
Surface UEFI. Use that only to reach the existing boot path; do not erase,
repartition, reset NVRAM, or change Windows boot files.

If the original no-timeout behavior is required, restore the preserved
pre-Sequoia config only after macOS is reachable and a separate boot test has
confirmed the desired default.

## Executed lightweight upgrade path

Do not combine an OpenCore update, kext update, SIP redesign, and macOS update
in one reboot chain.

After the unattended Sonoma boot was proven:

1. retain the current, byte-identified OpenCore-Mod and kext set for the first
   Sequoia test;
2. use the already verified Sequoia 15.7.7 full installer from Apple's
   `softwareupdate` catalog;
3. run a normal in-place upgrade of the existing Sonoma System/Data group;
4. boot and validate Sequoia graphics, keyboard, touch, battery, audio, USB,
   sleep/wake, network, SSH, and Windows visibility;
5. verify the routed default through installer reboots and a separate clean
   Sequoia reboot;
6. perform any OpenCore schema cleanup as a later, independently recoverable
   change.

The upgrade used Apple `startosinstall` with license acceptance, forced app
closure, and a short reboot delay. It did not use `--eraseinstall`, repartition
the disk, create an empty replacement account, update OpenCore, or broadly
update kexts. The prepared VoodooInput 1.1.5 bundle remains an inactive,
targeted fallback.

## Private artifacts

Machine-specific EFI files, checksum manifests, raw audit output, installer
payloads, credentials, and RPC diagnostics remain outside this repository.
They must never be committed.
