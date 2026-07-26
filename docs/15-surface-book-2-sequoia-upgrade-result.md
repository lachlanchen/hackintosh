# Surface Book 2 Sequoia Upgrade Result

Completed 2026-07-26. This is a sanitized execution record for an owned
Surface Book 2 Hackintosh. It omits credentials, addresses, host keys, disk
UUIDs, SMBIOS identity values, private backup locations, and the EFI payload.

## Result

The main APFS System/Data volume group was upgraded in place from Sonoma
14.8.3 (`23J220`) to Sequoia 15.7.7 (`24G720`).

The operation preserved:

- the existing primary account, home directory, and login keychain;
- Chrome and Firefox profile/history databases;
- Xcode 16.2 and its user data;
- applications and user settings under the normal macOS migration model;
- the Windows and Linux partitions;
- the existing OpenCore-Mod and kext set.

Sequoia completed its installer reboots without manual picker input. A separate
clean reboot then returned to Sequoia in roughly half a minute. No new panic
report appeared.

## Why the upgrade was approved

The preflight evidence supported the target:

- Apple lists the spoofed `MacBookPro16,3` model for Sequoia.
- UHD 620 was already accelerated through the native Kaby Lake path with
  1536 MB VRAM and Metal 3.
- The live Lilu, WhateverGreen, AppleALC, VirtualSMC, BlueToolFixup, and
  FeatureUnlock versions met or exceeded their first explicit macOS 15
  releases.
- The live OpenCore-Mod binary postdated the upstream macOS 15 CPU fix.
- The exact Realtek Wi-Fi kext trees matched a package that lists Sequoia.
- Apple's Xcode matrix supports Xcode 16.2 on Sequoia 15.x.
- AC power, full battery, more than 100 GB APFS free space, complete EFI
  checksums, Windows fallback, SSH, and external input were available.

The remaining uncertainty was BigSurface's embedded VoodooInput 1.1.3. An
official 1.1.5 replacement was prepared and signed but deliberately left
inactive unless the first Sequoia boot proved it necessary.

## Boot-routing transaction

The original OpenCore timeout selected Windows and
`RequestBootVarRouting` was disabled. That was unsuitable for a multi-reboot
macOS installer.

The boot-critical change was split into two hash-gated transactions:

1. Install a temporary internal-APFS-only config with
   `LauncherOption = Disabled`, restricted `ScanPolicy`, and
   `RequestBootVarRouting = true`.
2. Reboot and verify that Sonoma returns unattended.
3. Run `sudo bless --mount / --setBoot --verbose` from Sonoma.
4. Promote the normal-scan config whose only functional change from the
   known-good config is `RequestBootVarRouting = true`.
5. Reboot again and verify Sonoma before launching the installer.

Each promotion required expected source and live SHA-256 values, preserved the
previous live config on the EFI, copied through a temporary filename, verified
the installed hash, synced, and unmounted the EFI. The matching validator
reported only the two known pre-existing schema issues; no new warning was
introduced.

The previously verified Windows one-time OpenCore boot path remained available
but was not required in the final sequence.

## Installer execution

The full Sequoia installer came directly from Apple's `softwareupdate`
catalog. Before launch:

- `SharedSupport.dmg` passed `hdiutil verify`;
- internal MobileAsset metadata identified 15.7.7 (`24G720`);
- `InstallAssistant` and `startosinstall` chained to Apple Software Signing;
- the complete SharedSupport payload had a recorded SHA-256;
- no active Transporter, notarization, Xcode build, or prior installer process
  was running.

The normal in-place command shape was:

```bash
sudo "/Applications/Install macOS Sequoia.app/Contents/Resources/startosinstall" \
  --agreetolicense \
  --forcequitapps \
  --rebootdelay 30
```

No erase, target-volume replacement, repartitioning, account recreation,
OpenCore update, or kext update was included.

Preparation paused visibly at 16.9% and 55.1%. Those were not hangs:

- Apple's internal log repeatedly reported `stalled:NO`;
- the update worker used a full CPU core;
- the SSD continued writing tens to hundreds of MB/s;
- APFS free space changed as the update environment was expanded;
- the wrapper later advanced to 55.1% and then 100%.

The machine then followed this observable sequence:

1. first installer reboot;
2. wired interface reachable with SSH, Screen Sharing, and RDP closed,
   consistent with the offline macOS installer;
3. second automatic reboot;
4. Sequoia 15.7.7 returned over SSH;
5. a separate clean reboot returned to the same build.

Apple removed the temporary Sequoia and Sonoma full-installer applications
during successful cleanup. Their verified version/build, payload sizes, and
hashes remain in the private audit; they can be fetched again from Apple if
needed.

## Verified post-upgrade state

| Area | Verified state |
| --- | --- |
| OS | Sequoia 15.7.7 (`24G720`) |
| Account and data | Existing account/home, keychain, browser histories, and Xcode data present |
| OpenCore | Final routed config persisted through installer and clean reboots |
| Graphics | Intel UHD 620, 1536 MB, Metal 3 |
| Input | Surface type cover, touch screen, and VoodooInput multitouch device enumerate |
| Audio | Internal microphone and speakers enumerate |
| Network | Realtek Wi-Fi and Apple USB-NCM Ethernet active |
| Remote access | SSH, Screen Sharing, and UU Remote services active |
| Bluetooth | Third-party dongle active |
| Xcode | Xcode 16.2 and publishing command-line tools present |
| Other systems | Windows and Linux partitions unchanged |
| Power/storage | AC power; battery charged; approximately 143 GB APFS container free after cleanup |
| Panic state | No new panic report after upgrade or final reboot |

BigSurface and VoodooInput 1.1.3 loaded successfully, so the prepared
VoodooInput 1.1.5 candidate was not applied.

## First-login remote-access behavior

UU Remote was available at the login window, then briefly disconnected during
the first full Sequoia user login. This was not an application crash:

- the signed UU daemon, agent, server, and helper remained running;
- the vendor launch agent already covered both `LoginWindow` and `Aqua` and
  used `RunAtLoad` plus `KeepAlive`;
- Accessibility and Screen Capture authorization remained allowed;
- control connections were rebuilt while the process identifiers stayed
  stable.

The first login simultaneously rebuilt File Provider, Photos, icon/trust,
Metal, streaming-asset, and Xcode simulator caches. The load spike briefly
starved remote capture. One native-agent restart restored the session while
that one-time work settled:

```bash
uid=$(id -u)
launchctl kickstart -k "gui/$uid/com.netease.uuremote.agent"
```

No competing restart wrapper was installed.

An unrelated Ivanti Secure Access GUI also had a vendor `KeepAlive` launch
agent. To stop only its automatic GUI login while retaining the VPN services
and manual application, disable and unload that exact per-user job:

```bash
uid=$(id -u)
launchctl disable "gui/$uid/net.pulsesecure.pulseagent"
launchctl bootout "gui/$uid" \
  /Library/LaunchAgents/net.pulsesecure.pulseagent.plist
```

## Boundaries still requiring physical use

- Camera absence predates Sequoia.
- HID enumeration proves the trackpad/type-cover driver path is live, but a
  local operator should still confirm every gesture, touch, detach/reattach,
  brightness key, and keyboard shortcut during normal use.
- Sleep/wake was intentionally not mixed into the upgrade test.
- Windows fallback was fully boot-tested before the upgrade and its partition
  remains intact; it was not re-entered after Sequoia because the changed
  boundary was macOS/OpenCore routing, not Windows.
- The two old OpenCore schema warnings remain separate maintenance tasks.
- Picker cosmetics were handled afterward with the reversible policy in
  [Surface Book 2 storage and picker](16-surface-book-2-storage-and-picker.md).

## Practical lessons

- Prove restart routing before starting a multi-reboot macOS installer.
- A static progress percentage is not a stall when the update worker, disk I/O,
  APFS allocation, and internal `stalled:NO` state show activity.
- Do not pre-emptively replace a working hardware kext based only on a related
  model's issue report.
- Keep the known-good EFI, Windows BCD backup, external input, and independent
  SSH paths available until the final OS has passed another clean reboot.
- Preserve the user environment with a normal in-place upgrade; do not turn a
  routine OS upgrade into a repartitioning or bootloader migration project.
