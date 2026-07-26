# Surface Book 2 Upgrade and Recovery Runbook

This document records the reusable engineering method developed while preparing
a Surface Book 2 Hackintosh for an unattended Sonoma-to-Sequoia upgrade. It is
deliberately sanitized: machine addresses, credentials, SSH host keys, disk
UUIDs, SMBIOS identity, EFI contents, and exact private backup paths are not
included.

The machine-specific chronology and evidence belong in private operator
storage. This runbook describes decisions, invariants, scripts, tools, tests,
failed approaches, and recovery order that can be reused safely.

## Current verification boundary

As of 2026-07-26:

| Item | State |
| --- | --- |
| Sonoma 14.8.3 boot | Verified |
| Windows fallback boot and remote access | Verified |
| Complete EFI backup with file manifest | Verified |
| Windows boot-configuration backup | Verified |
| One-time APFS-only OpenCore bootstrap | Verified |
| Final routed OpenCore config | Verified through Sonoma, installer, and Sequoia reboots |
| Sequoia 15.7.7 installer | Verified and completed successfully |
| Sonoma 14.8.3 recovery installer | Verified before upgrade; removed by Apple's post-install cleanup |
| VoodooInput 1.1.5 Surface fallback | Staged, not installed because existing input works |
| Optional separate Sonoma recovery system | Not required for normal upgrade |
| Main system upgraded in place to Sequoia | Verified, including a separate clean reboot |
| Final picker cleanup | Intentionally deferred; not required for reliable boot |

Never promote a pending item to “verified” merely because a file was prepared.
A boot-critical change is verified only after the intended OS returns,
independent recovery remains available, and a second reboot reproduces the
result.

## Safety invariant

At every step, at least one remotely reachable installed operating system must
remain outside the change being tested.

For this machine the recovery order is:

1. current macOS over SSH;
2. OpenCore picker;
3. Windows over SSH or RDP;
4. the verified EFI backup and Windows restore path;
5. the verified Sonoma installer or Apple Recovery;
6. an optional separate recovery volume or external installer.

Do not erase, repartition, reset NVRAM, remove Windows boot files, or update
OpenCore and macOS together while an earlier recovery path remains usable.

## Starting architecture

The relevant design is:

- Surface Book 2 with Kaby Lake UHD 620 graphics;
- Sonoma 14.8.3 on one APFS System/Data volume group;
- Windows and Linux on separate GPT partitions;
- one large APFS container with dynamically shared free space;
- OpenCore-Mod 1.0.6 and BigSurface v6.5;
- FileVault off during the recovery work;
- SSH and Screen Sharing enabled on macOS;
- SSH and RDP enabled on Windows.

The live UHD 620 properties already use the native Kaby Lake path. Do not apply
OCLP graphics root patches to this machine.

## Compatibility verdict before installation

The pre-install research supports a normal Sonoma-to-Sequoia upgrade with
moderate-to-high overall confidence:

| Layer | Result |
| --- | --- |
| SMBIOS | `MacBookPro16,3` is an Apple-listed Sequoia model |
| Graphics | Native Kaby Lake UHD 620 `0x5916`, Metal 3, current WhateverGreen with macOS 15 support |
| Core kexts | Live Lilu, WhateverGreen, AppleALC, VirtualSMC, BlueToolFixup, and FeatureUnlock meet or exceed their first explicit macOS 15 releases |
| OpenCore | Current 1.0.6 development build postdates the upstream macOS 15 CPU fix; matching validation introduces no new candidate errors |
| Xcode | Installed Xcode 16.2 is explicitly supported on Sequoia 15.x |
| Network | Exact Realtek Wi-Fi kext trees match the maintained Sequoia-listed package; independent Apple USB-NCM Ethernet works over SSH |
| Surface input | BigSurface supports Book 2, but its embedded VoodooInput 1.1.3 may need the prepared official 1.1.5 replacement |

The research did not find an exact maintainer-qualified report for Surface
Book 2 plus Sequoia 15.7.7. Therefore physical trackpad/touch behavior was the
principal uncertainty. The completed upgrade confirmed that BigSurface and
VoodooInput 1.1.3 load and expose the expected type-cover, touch-screen, and
multitouch devices. The narrow VoodooInput candidate remains a fallback rather
than a pre-emptive change.

The upgrade did not start while `RequestBootVarRouting` was false and the
automatic picker choice was Windows. That was correctly treated as a
restart-routing blocker, not a Sequoia hardware blocker.

## 1. Establish independent remote paths

When macOS and Windows use the same network interface and address, keep their
SSH identities separate:

```sshconfig
Host surface-macos
    HostName <surface-address>
    User <mac-user>
    IdentityFile ~/.ssh/<mac-key>
    HostKeyAlias surface-macos

Host surface-windows
    HostName <surface-address>
    User <windows-user>
    IdentityFile ~/.ssh/<windows-key>
    HostKeyAlias surface-windows
    UserKnownHostsFile ~/.ssh/known_hosts_surface_windows
```

Verify both directions where possible:

```bash
ssh -o BatchMode=yes surface-macos 'sw_vers'
ssh -o BatchMode=yes surface-windows 'cmd /c ver'
```

On Windows, confirm OpenSSH and RDP survive a real reboot before using Windows
as unattended fallback. On macOS, confirm Remote Login, Screen Sharing, power,
battery, and FileVault state.

If passwordless sudo is required for unattended recovery, add a narrowly
documented local sudoers drop-in, validate it with `visudo`, and test it from a
fresh SSH connection. Never place the password in a script, shell history, Git,
or documentation.

## 2. Preserve boot material before changing it

Preserve two independent layers:

1. the complete EFI directory with a SHA-256 manifest for every file;
2. the Windows BCD/firmware boot configuration.

For the EFI, mount read-only for the initial acquisition:

```bash
sudo diskutil mount readOnly <efi-device>
```

Generate source and destination manifests independently:

```bash
find EFI -type f -print0 |
  sort -z |
  xargs -0 shasum -a 256 > SHA256SUMS
```

Compare the manifests and file count before accepting the backup. Keep the
machine-specific backup outside Git.

For Windows, export the BCD store before changing firmware order or one-time
boot selection:

```powershell
bcdedit /export C:\Path\To\Private\Backup\bcd
bcdedit /enum firmware /v
```

Record enough read-only evidence to distinguish:

- Windows Boot Manager;
- OpenCore;
- stale firmware-created macOS entries;
- the firmware boot-manager order;
- one-time `bootsequence` state.

## 3. Why the first automatic-boot test failed safely

The original picker had no automatic timeout. Adding a five-second timeout
enabled automatic selection, but the remembered default was Windows.

That result was useful:

- OpenCore itself still loaded;
- the timeout worked;
- Windows fallback remained reachable;
- timeout alone was proven insufficient for a macOS installer.

Firmware entries labelled “Mac OS X” were also tried as temporary firmware
choices. They did not return a reachable macOS system and were treated as stale
instead of being trusted or deleted.

## 4. The successful one-time APFS bootstrap

To select the only internal macOS volume without relying on stale firmware
state, create a temporary OpenCore config with:

```text
LauncherOption = Disabled
ScanPolicy = 0x80103
```

For this configuration, `0x80103` limits scanning to the internal NVMe APFS
path. Recalculate the policy for other hardware instead of copying the number
blindly.

The recovery-capable sequence is:

1. preserve the current config on the EFI;
2. XML-parse and `ocvalidate` the temporary config;
3. verify the candidate hash before and after placing it on the EFI;
4. retain Windows as an independent fallback;
5. if firmware does not enter OpenCore by itself, use an elevated Windows
   console to set only the next firmware boot to the previously verified
   OpenCore entry:

   ```powershell
   bcdedit /bootsequence "{<verified-opencore-guid>}"
   bcdedit /enum firmware /v
   ```

   Resolve the identifier from the entry whose description and EFI path both
   match OpenCore. Never copy a GUID from another machine or trust only a
   friendly label.
6. reboot and wait for macOS SSH;
7. identify the returned OS and root APFS volume;
8. restore the normal config byte-for-byte;
9. verify its hash again.

On the completed run, the routed APFS-only config reached Sonoma directly, so
the Windows one-time override was not needed. The Windows method remained an
independently tested fallback.

## 5. Hash-gated EFI promotion

The local Bash and PowerShell helpers implement the same transaction:

1. require caller-supplied expected hashes;
2. refuse an unexpected live config;
3. create or validate a rollback copy;
4. copy the candidate under a temporary name;
5. hash the temporary copy;
6. preserve the live file;
7. rename the candidate into place;
8. restore the live file automatically if promotion fails;
9. verify the final hash and sync;
10. unmount only a filesystem mounted by the helper.

This prevents a stale script, wrong EFI, interrupted copy, or changed live
config from being silently promoted.

The original machine-specific scripts remain private. Parameterized,
identity-free implementations of the same verified transaction are published
in [`scripts/`](../scripts/):

- `stage-opencore-config.sh`
- `restore-opencore-config.sh`
- `stage-opencore-config.ps1`
- `restore-opencore-config.ps1`

The Bash versions require an explicit EFI device. The PowerShell versions mount
the Windows system EFI and then require both the expected OpenCore directory and
expected live hash. Review [`scripts/README.md`](../scripts/README.md) before
use.

## 6. Route macOS boot variables through OpenCore

The known-good config initially had:

```text
LauncherOption = Full
AllowSetDefault = true
RequestBootVarRouting = false
```

OpenCore documents `RequestBootVarRouting` as redirecting `Boot*` variables to
the OpenCore vendor namespace. This prevents operating systems from replacing
firmware priority and allows Startup Disk and installer reboot choices to stay
inside OpenCore.

Use two candidates so the routing change can be tested without immediately
changing persistent firmware priority:

### Bootstrap candidate

```text
LauncherOption = Disabled
ScanPolicy = internal APFS only
RequestBootVarRouting = true
```

### Final routed candidate

```text
LauncherOption = Full
ScanPolicy = normal
RequestBootVarRouting = true
```

Test procedure:

1. boot the bootstrap candidate once through firmware `bootsequence`;
2. in macOS, select/bless the current Sonoma volume:

   ```bash
   sudo bless --mount / --setBoot --verbose
   ```

3. confirm `bless` writes the intended macOS Preboot target without error;
4. promote the final routed candidate;
5. reboot without input;
6. verify macOS, SSH, the root volume, and the normal picker default;
7. retain the five-second picker timeout through the OS upgrade and verify
   again after the installer reboots.

`nvram -p` does not necessarily expose an `OCBt*` line on every OpenCore
build. The decisive proof is a successful unattended reboot through the exact
candidate, not the presence of a particular printable variable name.

Do not combine the routing test with old config-schema cleanup.

## 7. Normal in-place upgrade and optional extra recovery

The normal execution path is an in-place upgrade of the existing Sonoma
System/Data volume group to Sequoia. This is the same macOS upgrade model that
preserves the current account, home directory, applications, settings,
keychain, and restorable app state. Never select `--eraseinstall`.

The current user environment contains far more data than the APFS container's
remaining free space, so a full same-disk clone is not practical. The accepted
fallback is the verified EFI backup, OpenCore picker, Windows recovery path,
and verified Sonoma installer payload. This is reasonable protection against a
boot or bootloader mistake, but it is not a byte-for-byte rollback of the whole
user environment. Apple's successful-upgrade cleanup removed both
full-installer applications; they can be fetched again from the Apple catalog
using the recorded exact versions.

If the operator later wants more protection, a small `Sonoma-Recovery`
System/Data group can be added inside the same APFS container. APFS volumes
share free space dynamically, so no fixed Sequoia partition is needed. This is
optional and must not block an otherwise normal in-place upgrade.

Do not create a fixed-size Sequoia partition. Do not touch unrelated unformatted
or Linux partitions merely because they appear unused.

### Optional future recovery-volume procedure

This procedure is documented but **not required or executed**:

1. identify the current root's main APFS container again; never reuse a device
   identifier from an old note without checking it;
2. confirm AC power, free capacity, EFI/BCD backups, Windows fallback, SSH, and
   the routed OpenCore default;
3. add a no-reserve, no-quota APFS volume to that existing container:

   ```bash
   sudo diskutil apfs addVolume <verified-main-container> \
     APFS "Sonoma-Recovery"
   ```

4. verify the new volume belongs to the intended container and that no GPT
   partition changed;
5. open the verified Sonoma installer:

   ```bash
   open "/Applications/Install macOS Sonoma.app"
   ```

6. in the installer GUI, choose **Show All Disks** and select only
   `Sonoma-Recovery`;
7. monitor the GUI through Screen Sharing or use a local operator;
8. after installation, boot that volume once, enable/verify its independent SSH
   recovery access, and identify its root volume group;
9. return to the original Sonoma system and verify it remains unchanged;
10. require a second recovery-system boot before treating it as a fallback.

The installer creates the matching System/Data group. Do not pre-create a
second Data volume manually. Do not use `--eraseinstall`: that option targets
the running installation boundary and is not a substitute for GUI selection of
the separate recovery volume.

## 8. Surface input patch boundary

BigSurface v6.5 embeds VoodooInput 1.1.3. A reported Sequoia input regression
on related Surface hardware was resolved by replacing the nested plug-in with
official VoodooInput 1.1.5.

The candidate was prepared without modifying the live EFI:

1. download official VoodooInput 1.1.5;
2. verify the release archive hash;
3. copy the known-good BigSurface bundle;
4. replace only `Contents/PlugIns/VoodooInput.kext`;
5. deep ad-hoc sign the reconstructed parent bundle on macOS;
6. verify both nested and parent signatures;
7. compare trees to ensure no unrelated payload changed.

Copying a kext through Finder or into a normal user directory may attach
`com.apple.FinderInfo` or resource-fork attributes. Strict code-signature
verification rejects that detritus. Inspect the exact staged copy with `xattr`,
remove unwanted extended attributes from that copy, and repeat deep strict
`codesign` verification before placing it on a FAT EFI filesystem.

If a future regression requires it, treat the candidate as its own EFI
experiment:

1. preserve the original BigSurface bundle;
2. install only the input candidate;
3. boot Sonoma, not Sequoia;
4. confirm SSH and graphics;
5. verify loaded BigSurface/VoodooInput versions;
6. reboot once more;
7. obtain physical confirmation of keyboard, touch, and trackpad;
8. roll back immediately if any unrelated hardware regresses.

Staging and signing are not evidence that the physical input path works. On
the completed Sequoia boot, the existing VoodooInput 1.1.3 path enumerated the
type cover and multitouch device, so 1.1.5 was not installed.

## 9. Acquire and verify official installers

List the installers Apple offers to the current system:

```bash
softwareupdate --list-full-installers
```

Fetch an exact version:

```bash
sudo softwareupdate --fetch-full-installer \
  --full-installer-version <version>
```

Before launch:

```bash
defaults read \
  "/Applications/Install macOS <Name>.app/Contents/Info.plist" \
  CFBundleShortVersionString

codesign --verify --deep --strict --verbose=2 \
  "/Applications/Install macOS <Name>.app"

spctl --assess --type install --verbose=4 \
  "/Applications/Install macOS <Name>.app"

"/Applications/Install macOS <Name>.app/Contents/Resources/startosinstall" \
  --usage
```

Record the exact version/build and inspect the executable's real usage before
choosing a CLI or GUI target-volume method. Do not assume options from a
different macOS generation.

The outer installer's `CFBundleShortVersionString` is the InstallAssistant
wrapper version, not necessarily the target macOS version. Mount
`SharedSupport.dmg` read-only and use its MobileAsset `OSVersion` and `Build`
metadata for the target identity.

The verified Sequoia app in this preparation used an old Apple custom resource
envelope. Whole-app strict `codesign` and Gatekeeper assessment therefore
reported `resource envelope is obsolete (custom omit rules)`. Do not “repair”
this by re-signing Apple's installer. Instead, verify independent layers:

1. the app came directly through Apple's `softwareupdate`;
2. `hdiutil verify` accepts the complete `SharedSupport.dmg`;
3. MobileAsset metadata names the requested version and build;
4. critical binaries such as `InstallAssistant` and `startosinstall` pass
   strict verification and chain to Apple Software Signing;
5. preserve the complete SharedSupport SHA-256.

The observed Sequoia 15.7.7 `startosinstall` has no target-volume option. A
future fresh recovery install onto a second APFS volume must therefore use the
installer GUI. The main existing Sonoma environment was upgraded in place
with the authenticated CLI after all boot recovery tests passed.

### Recover a stalled full-installer fetch without rebooting

During this preparation, the CLI remained alive and displayed 41%, but the
open `InstallAssistant.pkg.partial` file had not changed for more than eleven
minutes. A small independent HTTP range request to the same Apple CDN succeeded,
proving that the host still had network access. The existing daemon connection
was tied to a very slow/stalled endpoint.

The safe recovery was:

1. record the partial file size and modification time;
2. interrupt only the active `softwareupdate --fetch-full-installer` client;
3. restart only Apple's Software Update launch daemon:

   ```bash
   sudo launchctl kickstart -k system/com.apple.softwareupdated
   ```

4. confirm the cached partial file still exists at the same size;
5. rerun the exact `softwareupdate --fetch-full-installer` command;
6. verify that the progress quickly catches up and that the partial file starts
   growing again.

The daemon retained roughly 7.18 GB of cached payload, selected a different
Apple CDN endpoint, and resumed. No OS reboot or cache deletion was needed.
Avoid repeatedly invoking internal state-dump/fixup operations while an active
foreground transaction is downloading.

## 10. Main in-place upgrade boundary

Only start the in-place Sequoia installer after:

- Windows fallback has survived a reboot;
- OpenCore can return to Sonoma automatically and route installer reboots;
- installer signatures and build are verified;
- AC power and free APFS capacity are confirmed;
- the current EFI and Windows boot configuration have recovery copies;
- the VoodooInput candidate remains available if Sequoia input regresses.

During the installer:

1. do not manually override normal installer reboots;
2. monitor host identity, ping, SSH, and installer logs;
3. allow long sealed-system and firmware staging periods;
4. use Windows fallback only after evidence shows the routed installer path
   failed;
5. identify the returned OS and root APFS group before changing any default.

After Sequoia returns, verify:

- exact build and sealed-system state;
- the existing account, home, applications, and user data;
- SSH and Screen Sharing;
- UHD 620 acceleration, VRAM, Metal, and loaded Kaby Lake drivers;
- BigSurface/VoodooInput;
- keyboard, touch, trackpad, battery, audio, camera, USB, network, sleep/wake;
- installer/reboot logs and panic state;
- a second unattended Sequoia reboot;
- one intentional Windows fallback boot and return to Sequoia.

### Completed execution

The actual in-place command used:

```bash
sudo "/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
  --agreetolicense \
  --forcequitapps \
  --rebootdelay 30
```

Preparation displayed long plateaus at 16.9% and 55.1%. Read-only checks showed
that these were active phases:

- Apple's internal update state reported `stalled:NO`;
- the update-brain process used a full CPU core;
- the internal SSD continued writing;
- APFS allocation changed while the update environment expanded.

Preparation reached 100%, the machine entered the offline installer, rebooted
again, and returned as Sequoia 15.7.7 (`24G720`). A separate clean reboot then
returned to the same build with SSH, Screen Sharing, UU Remote, both network
paths, graphics acceleration, audio, BigSurface, VoodooInput, and the final EFI
config intact. No new panic report was present.

The existing account, home, login keychain, browser history databases, Xcode
16.2 data, Windows partition, and Linux partitions remained present. The
Windows fallback had been boot-tested before the upgrade and its partition
remained intact; it was not re-entered afterward because no Windows-side state
was changed.

## 11. Picker cleanup comes last

Do not hide recovery entries while the upgrade is in progress.

After every boot path is verified, use OpenCore's supported content labels,
visibility files, auxiliary entries, scan policy, or explicit entries to show
clear names such as:

- Sequoia
- Sonoma Recovery
- Windows

Hide duplicate recovery, raw partition, or Linux entries only after proving how
each visible entry maps to a bootable system. Do not repartition simply to make
the picker look cleaner.

The completed upgrade deliberately left picker cleanup for later. A reliable
five-second routed picker with visible recovery choices is preferable to
combining cosmetic changes with the OS transition.

## 12. Tools and evidence

| Tool | Purpose |
| --- | --- |
| `ssh`, Windows OpenSSH | Independent macOS/Windows recovery channels |
| RDP, Screen Sharing | GUI fallback and installer interaction |
| `diskutil`, `df`, `asr` | APFS topology, capacity, and restore capability |
| `sw_vers`, `system_profiler`, `ioreg` | OS, hardware, graphics, and Metal audit |
| `nvram`, `bless` | macOS/OpenCore boot selection and verification |
| `bcdedit`, `mountvol` | Windows firmware fallback and EFI access |
| `plutil`, `ocvalidate` | OpenCore plist syntax and schema validation |
| `xmllint`, structured plist diff | XML validity and exact candidate-field differences |
| `shasum`, `Get-FileHash` | Source, backup, staging, and installed-file identity |
| `softwareupdate` | Apple-catalog full installer acquisition |
| `launchctl` | Restart only a stalled Software Update daemon without rebooting |
| `lsof`, `stat`, `nettop`, `curl` | Distinguish a stalled CDN stream from host network failure |
| `codesign`, `spctl` | Installer and kext signature assessment |
| `xattr` | Detect and remove signature-breaking Finder/resource metadata from a staged copy |
| `verify-macos-installer.sh` | Read-only payload, metadata, signature, and CLI verification |
| `kmutil`, `kextstat` | Loaded kext verification |
| `pmset` | AC, battery, sleep, and unattended-state checks |
| `tmux` | Persistent monitoring that survives terminal disconnects |
| `gh` | Inspect primary OpenCore, BigSurface, and VoodooInput releases/issues |

No dedicated Hackintosh automation skill was used. The operational policy came
from this repository's `AGENTS.md`, primary OpenCore/Apple/project
documentation, read-only system evidence, hash-gated scripts, and one
independently recoverable change per reboot.

## 13. Failure lessons

- A picker timeout does not select macOS unless the remembered default is
  already macOS.
- Firmware entries with convincing labels may be stale.
- Seeing a prepared config or signed kext is not a boot test.
- OpenCore routing, persistent launcher registration, and scan restriction
  should be separated during bootstrap.
- A full APFS clone is not safe when source data exceeds available container
  space.
- A fresh macOS volume does not automatically inherit the existing user's home
  and applications; an in-place main upgrade is required for that continuity.
- Remote validation cannot prove physical trackpad or touchscreen behavior.
- Fixing unrelated old validator warnings during an OS upgrade makes rollback
  ambiguous.
- Final boot-menu cosmetics are less important than preserving visible recovery
  paths during the work.
