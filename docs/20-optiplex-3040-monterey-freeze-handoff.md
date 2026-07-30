# OptiPlex 3040 Monterey Freeze Handoff

Status date: 2026-07-30

Status: leading framebuffer cause identified; low-risk persistent controls
applied; native-graphics candidate staged but **not accepted or promoted**.
After the failed one-time firmware handoff, the physical picker returned on
2026-07-30 and the operator selected the prior normal `Monterey` entry. macOS,
key-only SSH, and UU returned. The candidate produced no new OpenCore log, its
custom picker entry is now removed, and the live config again passes matching
OpenCore 1.0.7 `ocvalidate`.

## Safety Boundary

- Keep the installed Monterey volume and its working OpenCore EFI unchanged
  until a separate candidate passes.
- Keep Windows 10 independently bootable.
- Do not reset NVRAM, rewrite Dell boot order, repartition, or overwrite an EFI
  while the current screen stage is unknown.
- Do not commit complete EFI trees, NVRAM, serials, partition GUIDs, network
  addresses, host keys, UU account data, or raw logs.
- Make one boot-critical change per acceptance cycle.

## Evidence

The installed system is Monterey 12.7.6 on an OptiPlex 3040 with an Intel
`i7-6700` and physical Skylake HD 530 device `0x1912`.

The live OpenCore 1.0.7 configuration instead injects:

- Kaby Lake device `0x5912`;
- platform data `00001259`;
- boot argument `-igfxsklaskbl`.

Monterey consequently loads `AppleIntelKBLGraphics` and
`AppleIntelKBLGraphicsFramebuffer`. Protected kernel history contains repeated
`TxnHang1`, `TxnHang2`, fake-VBL, skipped-flip, and gamma/flip events around
UU/VNC display transitions and GPU-enabled Codex launches. Codex repeatedly
triggered visible flashing.

There was no matching kernel panic, WindowServer crash, GPU-restart report,
swap pressure, memory shortage, SMART failure, or live storage I/O error.
Idle CPU returned above 98 percent and swap remained zero after Spotlight
settled. This makes the Kaby-spoofed framebuffer path the leading freeze and
flashing cause; Codex is a trigger, not proof that its signed bundle is
defective.

The official Codex app passed deep signature verification with identifier
`com.openai.codex` and OpenAI Team ID `2DC432GLL2`.

## Persistent Low-Risk Controls

The following changes are already persistent across restart:

- system, display, and disk sleep disabled;
- standby, power nap, and automatic power-off disabled;
- Wake-on-LAN, TCP keepalive, restart after freeze, and restart after power
  failure enabled;
- automatic major macOS download and installation disabled;
- critical and configuration-data updates retained;
- indexing disabled only on the slow data/staging volumes, each with
  `.metadata_never_index`;
- Monterey root/SSD indexing retained;
- per-user interactive-load guard installed;
- native UU boot daemon, Aqua agent, and conservative unattended watchdog
  verified.

The UU watchdog preserves credentials, TCC state, device identity, and active
sessions. It does not restart a healthy agent merely because one incidental
socket disappears.

## Native Monterey Candidate

The upstream basis is:

- [WhateverGreen Intel FAQ](https://github.com/acidanthera/WhateverGreen/blob/master/Manual/FAQ.IntelHD.en.md):
  Skylake is supported through macOS 12; the Kaby spoof is for macOS 13+.
- [Dortania desktop Skylake guide](https://dortania.github.io/OpenCore-Install-Guide/config.plist/skylake.html):
  native desktop HD 530 platform `00001219`, without a Kaby device-ID spoof.

The isolated candidate changes only:

1. platform `00001259` to native `00001219`;
2. removes injected Kaby `device-id`;
3. removes `-igfxsklaskbl`.

It retains the existing framebuffer memory patches, SMBIOS, ACPI, kexts,
OpenCore version, and every non-graphics setting. It lives as a separate
`EFI/OC` tree on the Windows SSD ESP. The live Mac EFI, Windows BCD, Microsoft
primary/fallback loaders, partitions, and saved picker default were not
overwritten. Matching OpenCore 1.0.7 `ocvalidate` passed before and after
staging.

Use:

- [`stage-optiplex-3040-monterey-native-graphics.sh`](../scripts/stage-optiplex-3040-monterey-native-graphics.sh)
  to audit or stage the isolated candidate;
- [`arm-optiplex-3040-monterey-native-picker.sh`](../scripts/arm-optiplex-3040-monterey-native-picker.sh)
  to audit, expose, or remove its non-default picker entry;
- [`cleanup-optiplex-3040-native-test-boot.ps1`](../scripts/cleanup-optiplex-3040-native-test-boot.ps1)
  to remove the temporary Windows firmware-test object after evidence
  collection.

`bless --nextonly` was attempted after backup and validation. This
OpenRuntime/firmware combination rejected it with `0xe00002e2`, and no
`efi-boot-next` variable appeared. Do not repeat that route as if it worked.

## Candidate Boot Timeline

1. The candidate and live source passed matching `ocvalidate`.
2. Both ESPs were remounted read-only and independent SHA-256 backups were
   copied off-machine.
3. A non-default `Monterey Native Graphics Test` picker entry was installed
   transactionally. The first restart timed out to Windows before selection;
   Windows SSH identity and OS version confirmed that no candidate test had
   occurred.
4. Windows verified the candidate ESP by model, first-partition geometry,
   marker, OpenCore hash, and config hash.
5. Windows exported BCD and firmware state, then armed a temporary
   firmware-manager `bootsequence` for the candidate loader.
6. After restart, the host did not return to the LAN within four minutes.
   Router ARP/DHCP, a full local subnet scan, both macOS and Windows SSH
   identities, and one Wake-on-LAN attempt found no live 3040.
7. The physical picker later returned. It showed the normal Monterey and
   Windows paths plus the explicit native test. The operator selected normal
   `Monterey`; macOS 12.7.6, key-only SSH, and UU returned.
8. The candidate ESP still had no `opencore-*.txt` log. Its marker, loader,
   config, hashes, current NVRAM, disk layout, and the latest normal OpenCore
   log were preserved under ignored private storage.
9. The custom native-test picker entry was removed transactionally. The live
   ESP was remounted read-only and the resulting config passed matching
   `ocvalidate`.

The native candidate was therefore **not promoted**. The result remains
inconclusive as a graphics test, but the missing candidate log is useful
negative evidence: there is no proof that this firmware handoff reached the
candidate OpenCore loader. Do not select or re-arm it until the handoff method
has been isolated independently from the graphics change.

## Recovered Picker State

- The saved OpenCore default resolves to Monterey's exact APFS Preboot volume
  group, `ShowPicker` remains enabled, and the timeout is five seconds.
- `Monterey Native Graphics Test` has been removed.
- `No Name` is the read-only 1.8 MB FAT12 virtual driver flash exported by an
  attached `aicsemi` USB peripheral. It is not macOS or a recovery system.
  Because the medium is read-only, do not try to write a visibility marker to
  it. Leave it alone or unplug that peripheral; do not broaden this recovery
  into an OpenCore scan-policy change.
- Choose `Monterey` for normal macOS and `Windows 10` for Windows. Do not use a
  generic `Windows` entry until its firmware source is audited.

The temporary firmware object may remain in display order after its one-time
sequence is consumed. Windows and Monterey remain ahead of it, but remove it
after evidence collection so a failed experiment does not remain in the
long-term firmware menu.

The Windows cleanup helper is prepared and manually reviewed, but it has not
run because recovery deliberately stayed in normal Monterey. At the next
planned Windows 10 boot, run it in `Audit` mode first and inspect the identified
entry before explicitly confirming `Cleanup`.

## Codex Mitigation Result

The untouched signed desktop app was first tested with Electron
`--disable-gpu`. The flags took effect: the main process showed
`--disable-gpu` and its Chromium graphics helper showed `--use-gl=disabled`.
This was not an acceptable fix. The main process continuously consumed
86-100 percent of one CPU core for more than five minutes and macOS generated
a `cpu_resource` diagnostic. The process was stopped, the experimental
launcher was removed, and the desktop app remains unmodified.

[`install-codex-cli-launcher-macos.sh`](../scripts/install-codex-cli-launcher-macos.sh)
implements the accepted fallback. It requires `codex` inside the user's nvm
tree, verifies that the matching package is exactly `@openai/codex`, and
creates an executable `Codex CLI.command` with a Desktop shortcut. Installation
also removes the rejected Electron launcher.

```bash
./install-codex-cli-launcher-macos.sh install
./install-codex-cli-launcher-macos.sh audit
```

The live installation verified `codex-cli 0.146.0`; that is an evidence
snapshot, not a version pin. Keep using the text-only CLI until a graphics
candidate passes physical display, UU, VNC, SSH, and protected-log acceptance.

A ten-minute recovery watch completed 20 ping/SSH checks without failure.
WindowServer stayed near idle, swap stayed zero, and the protected kernel-log
delta contained no new framebuffer transaction hang, fake VBL, skipped flip,
GPU restart/panic, watchdog timeout, or storage I/O error. The desktop app's
separate CPU failure still makes the CLI the accepted operating path.

## Tools and Method

- [`audit-optiplex-3040-stability.sh`](../scripts/audit-optiplex-3040-stability.sh):
  collect bounded, read-only system, graphics, storage, power, remote-service,
  and protected-log evidence.
- `system_profiler`, `ioreg`, `kextstat`/`kmutil`: physical GPU, injected
  identity, active framebuffer driver, display mode, and Metal state.
- `log show` with bounded kernel predicates: `TxnHang`, fake VBL, skipped
  flips, GPU restart/panic, watchdog, shutdown, and memory evidence.
- `top`, `ps`, `memory_pressure`, `sysctl vm.swapusage`: distinguish GPU
  trouble from CPU or memory exhaustion.
- `diskutil`, SMART status, APFS free-space checks, bounded live kernel stream:
  exclude active storage failure.
- `ocvalidate`, `plutil`, `PlistBuddy`: structured OpenCore validation and
  exact property edits.
- `codesign`: verify UU and Codex identifiers and Team IDs before automation.
- `bcdedit /export` and `bcdedit /enum firmware /v`: preserve and audit the
  Windows/UEFI handoff.
- read-only ESP mounts, SHA-256 manifests, transaction traps, and off-machine
  backups: make every boot edit reversible.
- router ARP/DHCP, subnet scan, host-key aliases, and bounded polling:
  distinguish Windows, macOS, changed address, and true network absence.

All machine-specific backups remain under ignored private storage and are not
part of this repository.
