# Current State

Status date: 2026-08-30

## Verified

- Hardware: Dell OptiPlex 7050, Intel Core i5-6500, Intel HD Graphics 530,
  16 GB memory.
- OpenCore: 1.0.7.
- Recovery system: the APFS Recovery volume associated with Sequoia. The former
  Monterey System/Data volume group was retired on 2026-08-01.
- Development system: macOS Sequoia 15.7.7, build `24G720`.
- Sequoia boots from its original Apple-sealed system snapshot.
- Sequoia graphics use `AppleIntelKBLGraphics` and
  `AppleIntelKBLGraphicsFramebuffer` 23.0.7.
- Sequoia reports 1536 MB dynamic VRAM and Metal 3.
- OpenCore defaults to Sequoia after five seconds. Its graphical picker exposes
  Windows while keeping auxiliary Recovery entries hidden unless requested.
- Ethernet and SSH are functional after reboot.
- OCLP root-patch launch agents, daemons, app, and privileged helper were
  removed with the signed/notarized 2.4.1 uninstaller.
- The macOS APFS container is 240.2 GB and now contains one System/Data volume
  group. After Monterey retirement and a clean reboot, 106.4 GB was
  unallocated inside the container.
- Sequoia System and Data both passed live read-only APFS verification. The
  blessed snapshot, NVRAM boot path, Preboot, and Recovery records all resolve
  only to the active Sequoia volume group.
- Windows remains on a separate GPT partition and retains its firmware boot
  manager.
- System sleep, display sleep, disk sleep, standby, and automatic power-off are
  disabled for this development workstation.
- The current user's screensaver idle timer is disabled. Remote
  `caffeinate -u -t 10` successfully restored a display that had not responded
  to local mouse movement.
- Key-based SSH works in both directions between the Sequoia host and its
  Ubuntu development peer.
- macOS Screen Sharing is reachable on the trusted LAN. Ubuntu's existing
  live-desktop RDP bridge is reachable from the Mac through Windows App.
- Chrome uses a dedicated publication profile with CDP bound to loopback only.
- The GlassAgent root checkout is clean at its pinned root and top-level
  submodule commits.
- XcodeGen 2.46.0 and CocoaPods 1.17.0 successfully generate the LightMind iOS
  workspace and resolve its local Rokid SDK pod.
- Universal Xcode 26.3 (`17C529`) is installed at
  `/Applications/Xcode-26.3.0.app`, selected with `xcode-select`, licensed, and
  through first-launch setup.
- The downloaded Xcode archive was verified as Apple-signed before expansion.
  Its SHA-256 was
  `cf87232e0419785170edcfa070b750f28808ec00b489ab540c08b7d197c79ae4`;
  the archive was deleted after installation.
- Universal iOS 26.3.1 simulator runtime `23D8133` is installed and boots on
  this Intel host.
- The LightMind CocoaPods workspace builds unsigned and signed with Xcode 26.3.
- Five unit tests and one portrait/landscape UI test pass.
- A version `0.2.3` build `5` archive and App Store export completed with a
  production-style signature. This verifies the temporary development
  workstation path; final release evidence still belongs on Apple-supported
  hardware.
- The development shell selects Python 3.12.13 and OpenJDK 21.0.12. GitHub CLI
  2.96.0, tmux 3.7b, ADB/platform-tools 37.0.0, `scrcpy` 4.1, and Android
  platform/build tools for API 35 are installed.
- The GlassAgent backend's 167 tests, PWA's 45 checks, and Toolchains' 27 tests
  pass on this host. The Android phone plus glasses-display modules also pass
  `testDebugUnitTest assembleDebug`.

## Boot-Critical Graphics Values

These values describe the sanitized intent, not a complete EFI:

| Property | Data |
| --- | --- |
| `AAPL,ig-platform-id` | `00001259` |
| `device-id` | `12590000` |
| `framebuffer-patch-enable` | `01000000` |
| `framebuffer-stolenmem` | `00003001` |
| `framebuffer-fbmem` | `00009000` |

`-igfxsklaskbl` remains in the known-good EFI after Monterey retirement.
Current WhateverGreen documentation says it is not required on macOS 13 or
newer, but removing a graphics boot argument is a separate change that needs a
hash-gated EFI candidate and physical boot validation.

## Deliberately Not Enabled

- OCLP graphics root patching
- automatic macOS installation
- Tahoe upgrade
- FileVault
- AirDrop, because no AWDL-capable Wi-Fi interface is present

## Development Power Policy

The verified effective values are:

```text
sleep        0
displaysleep 0
disksleep    0
standby      0
autopoweroff 0
powernap     0
```

The current-host screensaver `idleTime` is also `0`. This prevents unattended
build, download, and remote-debug sessions from being interrupted, but it also
means the workstation and display do not conserve power automatically. Revisit
this policy when the machine no longer needs to behave as an always-available
development host.

## Pending

- A private, checksum-pinned OptiPlex 7050 BIOS update and recovery kit is
  prepared. The physical service tag and installed BIOS version remain
  intentionally unclaimed until Windows reads them from WMI at the next local
  boot. No firmware update has been launched.
- Repeat final archive and physical-device evidence on Apple-supported
  hardware.
- Optionally add a Broadcom BCM94360CD PCIe card for AirDrop, accepting that
  Sequoia requires a separately maintained legacy wireless patch.

## Separate Z790 KVM profile

These facts describe the isolated Ubuntu-hosted VM documented in
[`24-z790-kvm-sequoia.md`](24-z790-kvm-sequoia.md), not the physical OptiPlex
state above:

- Sequoia 15.7.9 (`24G830`) boots from the sparse private qcow2 through the
  pinned OSX-KVM/OpenCore profile.
- The private OpenCore identity and built-in `en0` mapping remain stable. A
  stable private QEMU `vmgenid` is now reused across normal boots.
- Two exact kernel cstring swaps are scoped to Darwin 24 and passed the
  matching `ocvalidate`, EFI round-trip, qcow2, and post-boot checks.
- Post-boot `kern.hv_vmm_present = 0` is verified. The operator subsequently
  completed Apple Account login manually; an authenticated App Store download
  verified the Media & Purchases path without rotating identity or NVRAM.
- Xcode 26.3 (`17C529`) is installed at `/Applications/Xcode.app`, selected,
  licensed, and through first-launch setup. The signed App Store package and
  application passed independent verification before the temporary 5.5 GiB
  capture/expansion files were removed.
- Bundled macOS 26.2, iOS 26.2, and watchOS 26.2 SDKs are present. Only
  universal iOS 26.3.1 (`23D8133`) and watchOS 26.2 (`23S303`) simulator
  runtimes were installed and registered; tvOS, visionOS, and
  `-downloadAllPlatforms` were excluded. Swift 6.2.4 and Apple Clang 17 were
  verified, including a successful Swift execution test. About 448 GiB remains
  free in the guest.
- iCloud Drive is enabled with optimized storage, but currently consumes no
  local file data. Cloud-backed files must be made online-only with Finder's
  **Remove Download**, never filesystem deletion.
- The nested JIS/US punctuation mismatch was isolated to QEMU's extended VNC
  physical-key path. A hash-pinned, private noVNC overlay now converts only
  printable ASCII punctuation to explicit U.S. guest chords. The live proxy
  was migrated without rebooting the VM; `layoutsafe=0` is the immediate
  rollback, and no Ubuntu or macOS global keyboard layout was changed.
- No NVRAM reset, identity rotation, host boot change, GPU passthrough, or
  non-loopback service exposure was performed.

## OptiPlex 3040 Candidate

The separate OptiPlex 3040 is staged but has not booted macOS yet. Do not merge
these candidate facts into the verified OptiPlex 7050 state above.

- Windows 10 Pro 22H2 remains the default and is reachable through key-only
  SSH.
- Both GPTs and the Windows BCD have private pre-change backups.
- A 4 GiB FAT32 `MACRECOVERY` ESP was created at the end of the 1 TB data disk
  by shrinking only the end of `G:`. Its complete 27-file payload was
  hash-verified after copy.
- The Samsung SSD's 136.7 GiB unallocated extent remains untouched and is the
  intended macOS target.
- The Monterey recovery `BaseSystem.dmg` passed Apple's chunklist verification.
- The private OpenCore 1.0.7 candidate passes its matching `ocvalidate` with no
  issues.
- A Windows BCD `BOOTAPP` entry points to the recovery OpenCore bootstrap.
  Windows remains the default and no one-time boot is currently armed.
- The first test still requires a physical display and USB keyboard. Graphics,
  USB, Ethernet, audio, Recovery, installation, and reboot behavior remain
  unverified on this board.
- Setup Assistant must create the `lachlan` account before the prepared
  bootstrap can install its dedicated public key and enable persistent SSH.
