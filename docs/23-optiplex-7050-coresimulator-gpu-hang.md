# OptiPlex 7050 CoreSimulator GPU Hang

## Status

- **Verified incident:** 2026-08-10 on the Sequoia 15.7.7 development volume.
- **Verified cause:** CoreSimulator's Metal renderer repeatedly hung the Intel
  GPU. This was not a RAM, swap, or disk-capacity exhaustion event.
- **Applied mitigation:** simulator framebuffer compositing is disabled for the
  development user, simulator window restoration is disabled, and every
  simulator device is shut down.
- **Operating decision:** use physical iPhone/iPad devices for visual and
  interaction QA. Keep simulator UI closed on this workstation.
- **Open verification:** a post-mitigation simulator UI boot was intentionally
  not attempted because it would re-enter the failing graphics path.

## Evidence

The post-reboot, read-only audit found:

| Observation | Result |
| --- | --- |
| macOS | 15.7.7 |
| Selected developer directory | Xcode 26.3 installation |
| Graphics | Intel HD Graphics 530, Metal 3 |
| Memory | 16 GiB; 87 percent free; no swap-in or swap-out after reboot |
| Storage | 51 GiB available on the APFS data container |
| Simulator devices | All shut down |
| Kernel diagnostics | Four recent `GPU Reset` reports |
| Responsible executable | CoreSimulator `SimMetalHost` in three reports |
| GPU signature | `Intel GPU Hang Summary`, signature 2 |
| Display diagnostics | WindowServer repeatedly reported its main display as offline |
| Secondary load | `mediaanalysisd` sustained about 140 percent CPU for nearly three hours |
| Indexing load | `mds_stores` sustained about 20-34 percent CPU during release preparation |

The diagnostic combination proves a simulator-triggered GPU reset. It does not
prove whether the final defect is in CoreSimulator, the unsupported Skylake
graphics compatibility path, or their interaction. No raw diagnostic report,
host identifier, EFI, or Apple account data belongs in Git.

## Applied Recovery

The following user-scoped changes were applied after the reboot:

```bash
xcrun simctl shutdown all
defaults write com.apple.CoreSimulator \
  FramebufferServerRendererPolicy -string none
defaults write com.apple.iphonesimulator \
  NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.iphonesimulator \
  ApplePersistenceIgnoreState -bool true
killall -TERM Simulator 2>/dev/null || true
killall -TERM SimMetalHost 2>/dev/null || true
killall -TERM SimRenderServer 2>/dev/null || true
```

Apple documented `FramebufferServerRendererPolicy=none` for headless and CI
use so CoreSimulator skips virtual-framebuffer compositing. The setting is
accepted on this host and directly avoids the process named by the GPU-reset
reports. See Apple's
[Xcode 11 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-11-release-notes)
and
[Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference).

Use the repository guard instead of repeating commands manually:

```bash
scripts/stabilize-optiplex-7050-simulator.sh status
scripts/stabilize-optiplex-7050-simulator.sh stabilize
```

The guard does not delete runtimes, devices, application data, or DerivedData.

## Secondary CPU Pressure

The simulator GPU resets were the freeze cause, but Photos analysis and
Spotlight indexing added avoidable load after reboot. For a bounded archive or
upload window, identify the exact processes first and then temporarily lower
their impact:

```bash
ps -axo pid,stat,%cpu,%mem,etime,command | \
  grep -E 'mediaanalysisd|mds_stores' | grep -v grep

media_pid="$(pgrep -x mediaanalysisd | head -n 1)"
mds_pid="$(pgrep -x mds_stores | head -n 1)"
test -z "$media_pid" || kill -STOP "$media_pid"
test -z "$mds_pid" || sudo renice 20 -p "$mds_pid"
```

Restore both immediately after the bounded operation:

```bash
test -z "$media_pid" || kill -CONT "$media_pid"
test -z "$mds_pid" || sudo renice 0 -p "$mds_pid"
```

Process IDs change after a reboot. Re-read them instead of reusing the example
incident's IDs. `mediaanalysisd` must not be left stopped as a permanent
workstation setting.

At the end of the verified release window, `SIGCONT` was sent to the exact
paused Photos-analysis process and Spotlight was restored to nice level 0.
The Photos-analysis process then exited normally. A follow-up process audit
found no release uploader or simulator renderer left running.

## Release Workstation Policy

1. Keep Simulator closed during archive, export, artifact audit, and provider
   work. None of those steps requires a booted virtual device.
2. Use the physical iPad or iPhone for visual, IME, permissions, links,
   notification, accessibility, and crash QA.
3. Permit at most one virtual device only after an operator explicitly restores
   UI rendering and accepts the GPU-reset risk.
4. Never run multiple Simulator windows or concurrent virtual devices on this
   Intel graphics path.
5. A simulator compile target is allowed when it does not boot a virtual
   device. Check process state before and after the build.
6. Preserve the newest `.gpuRestart` report privately if another reset occurs,
   then return immediately to headless mode.

The offline EchoMind iOS candidate was built outside this workstation. Its
protected import, signed-artifact audit, and custody seal do not require
Simulator UI. Physical-device qualification remains a separate release gate.

## Network And Release Isolation

The 2026-08-10 EchoMind release used two deliberately separate paths:

- Google Play provider traffic ran on the Ubuntu workstation through an
  ephemeral Astrill route limited to `oauth2.googleapis.com` and
  `androidpublisher.googleapis.com` on TCP 443. Cleanup removed the route after
  each operation; Codex, SSH, and ordinary host traffic stayed on the direct
  path.
- The protected iOS audit and upload path ran on this Mac with
  `skip-simulator`. It used the signed IPA and App Store Connect transport
  tools without launching Simulator UI, `SimMetalHost`, or `SimRenderServer`.

That exact headless run validated and uploaded the 9,588,830-byte EchoMind
iOS/watchOS build 64 without errors under delivery resource
`32220390-cb26-4240-9bb3-cfe2b6d1216a`. The guarded public-beta workflow then
attached that exact build and authenticated readback reported it `VALID`,
unexpired, `APPROVED`, and available from the existing 1,000-tester public
TestFlight link. Formal App Store version `1.0` remained separate and
unsubmitted. No new `*.gpuRestart` report appeared during or after the release
window.

This separation is part of the release safety case: a provider-specific VPN
route must never become the Mac's default route, and store publication must not
re-enable the graphics path that caused the freeze.

## Verification

Check the guard without starting CoreSimulator:

```bash
scripts/stabilize-optiplex-7050-simulator.sh status
pgrep -lf 'SimMetalHost|SimRenderServer|/Simulator.app/' || true
```

Expected values:

```text
renderer_policy=none
restore_windows=0
ignore_saved_state=1
gpu_renderer_processes:
```

If the desktop is responsive, memory pressure is normal, and no new GPU-reset
report appears while build and physical-device work continue, the workstation
is stable for the headless release path.

The verified 2026-08-10 run met those conditions. The renderer policy remained
`none`, Spotlight returned to its normal priority, and no upload, Simulator UI,
`SimMetalHost`, or `SimRenderServer` process remained after cleanup.

A follow-up after more than five hours of uptime still showed about 48 GiB of
free APFS space, zero booted simulators, and no Simulator UI, Metal renderer,
`xcodebuild`, or `devicectl diagnose` job. Idle CoreSimulator registration
services remained harmless. This checkpoint supports continued command-line
and physical-device release work; it does not justify reopening Simulator UI.

## Post-Reboot Physical Test Recovery

The next physical-iPad test exposed two separate issues that should not be
confused with the GPU hang:

1. An SSH login could enumerate the Apple Development identities but direct
   `codesign` returned `errSecInternalComponent`. Unlocking the login keychain
   and restoring the `apple-tool:,apple:,codesign:` partition list was
   necessary but not sufficient because the SSH process remained in a
   different audit session from the logged-in desktop.
2. Running the same signing/build process in the active GUI audit session
   succeeded. The app and XCTest runner compiled, signed with the LazyingArt
   development identity, and installed on the physical iPad without starting
   Simulator or `SimMetalHost`.

For an interactive maintenance session, unlock and repair the key ACL without
putting the login password in shell history:

```bash
security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: -s \
  "$HOME/Library/Keychains/login.keychain-db"
```

For a headless command initiated over SSH, enter the logged-in user's GUI audit
session and then drop back to that user before invoking Xcode:

```bash
console_user="$(stat -f '%Su' /dev/console)"
console_uid="$(id -u "$console_user")"

sudo launchctl asuser "$console_uid" \
  sudo -u "$console_user" env \
    HOME="/Users/$console_user" \
    DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer \
    xcodebuild <physical-device arguments>
```

Do not use this pattern to bypass a locked desktop or an OS consent dialog. It
only gives an already authorized command the same audit session as the active
user.

The physical test then stopped at the device boundary with
`Timed out while enabling automation mode`. The iPad was paired, available,
unlocked since boot, and had Developer Mode enabled. The failure therefore did
not justify falling back to Simulator. Treat device-side UI Automation as a
separate one-time physical setup gate.

After a UI-test initialization failure, Xcode may start a ten-minute
`devicectl diagnose` collection and keep `xcodebuild` alive even though no test
is progressing. Inspect the exact process tree and terminate only that failed
job before continuing release work:

```bash
ps -axo pid,ppid,state,etime,%cpu,%mem,command | \
  grep -E 'xcodebuild|devicectl diagnose' | grep -v grep
```

The verified cleanup removed the temporary XCTest runner, ended the bounded
Xcode/diagnostic process tree, restored Spotlight to nice level 0, resumed
Photos analysis, and removed the temporary build directory. No Simulator UI or
Metal renderer appeared, and no new GPU-reset report was created.

## Post-Reboot Xcode Selection Recovery

A later reboot left `xcode-select` pointing at a no-longer-present
`/Applications/Xcode-26.6.0.app/Contents/Developer`, although the validated
Xcode 26.3 bundle remained intact at
`/Applications/Xcode-26.3.0.app`. This made `xcrun` fail before it could even
inspect simulator state. It was a stale path, not an Xcode installation loss.

Verify the selected path and the replacement bundle before changing anything:

```bash
xcode-select -p
test -x /Applications/Xcode-26.3.0.app/Contents/Developer/usr/bin/xcodebuild
/Applications/Xcode-26.3.0.app/Contents/Developer/usr/bin/xcodebuild -version
```

Then correct the global developer directory and shut down virtual devices
without opening Simulator:

```bash
sudo xcode-select --switch \
  /Applications/Xcode-26.3.0.app/Contents/Developer
xcodebuild -version
xcrun simctl shutdown all
xcrun simctl list devices | grep '(Booted)' || true
```

The verified readback reported Xcode 26.3 build `17C529`, zero booted devices,
renderer policy `none`, and no `Simulator`, `SimMetalHost`, `xcodebuild`, or
`devicectl diagnose` job. The historical GPU-report count remained four and
the APFS container retained about 48 GiB free. CoreSimulator helper services
may exist while every virtual device is shut down; the dangerous evidence is a
booted device or active renderer, not an idle service registration.

## Latest Reboot Recovery Checkpoint

After the desktop was reported frozen again at a Simulator loading screen, the
host was recovered over key-only LAN SSH without reopening Simulator. The
post-reboot audit at 2026-08-10 19:56 CST established all of the following:

- macOS 15.7.7 had been up for approximately six hours and SSH was responsive;
- Xcode 26.3 remained the selected and usable developer installation;
- two stale CoreSimulator service trees existed, but no virtual device was
  booted and no `Simulator.app`, `SimMetalHost`, or `SimRenderServer` process
  was running;
- `simctl shutdown all` completed, then the stale simulator service processes
  were terminated and allowed to re-register cleanly;
- the three user defaults still read `none`, `0`, and `1`; and
- the diagnostic inventory still contained exactly the four previously
  recorded GPU-reset reports, newest at 2026-08-10 02:38:45 CST. There was no
  new reset report attributable to the later frozen screen.

Do not infer that a missing new `gpuRestart` report makes Simulator safe. A
stalled loading UI can still leave the desktop unusable before macOS emits a
kernel diagnostic. The recovery decision remains the same: leave virtual
devices shut down and use the paired physical iPad/iPhone path for release QA.

## External Test-Device Network Isolation

The Android Play listing check used a third, RAM-only router overlay bound to
the test phone's exact IPv4 `/32` and verified LAN MAC address. Only the two
hostnames observed in Play Store logs were included, on TCP and UDP port 443.
Ubuntu, Codex, SSH, and the Mac retained their existing source-bound routes.

The real EchoMind internal-testing listing loaded successfully. Cleanup then
removed that owner by generation and a fresh router readback reported no
remaining phone overlay. Use the `astrill-lazy device-flow` command for this
pattern; do not replace it with host-wide or whole-device VPN routing.

A later routing audit found an independent native Astrill setting that changed
that conclusion: the applet's website mode was still global (`mode 0`). The
phone overlay itself remained source scoped, but unmatched Ubuntu and Mac
traffic could still inherit the applet's global tunnel. The previous native
site list was saved in private mode-`0600` storage, the native website policy
was changed to Direct-by-default include mode with an empty list, and the
original endpoint was reconnected through the companion. Final readback
reported both native website and device defaults as Direct, a healthy tunnel,
the original server selection, and no phone overlay. Independent public-egress
checks from Ubuntu and the phone then matched the normal ISP path.

This is an important distinction: a source-scoped companion overlay does not
prove that the native Astrill defaults are also source scoped. Verify both
layers before claiming Codex, SSH, or another workstation stayed Direct.

## Play-Signed Physical Device Result

The same physical-phone run verified the following release facts without
launching an iOS Simulator:

- Google Play Console reported EchoMind Internal testing as Active with
  version code `65` available to internal testers.
- The invited account on the phone accepted the internal-test program, and
  Play scheduled version `65` as five split downloads.
- The signed download URLs selected China-local Google CDN hostnames. Several
  DNS-selected edges timed out. Reachable sibling edges completed TLS, but the
  candidate downloads returned HTTP `400` because the signed delivery context
  and receiving edge/egress did not agree.
- Switching among the original, Hong Kong, and China-optimized Astrill
  endpoints did not produce a valid end-to-end Play download.

The result proves the Console candidate and tester entitlement exist. It does
not prove a Play-signed installation, launch, or deployment-certificate check.
Keep those physical-device gates open and do not infer an application defect
from this provider/CDN delivery failure.

Cleanup force-stopped the failed Play retry, removed the owner-scoped overlay,
removed every temporary packet-mark and destination-translation chain,
restored the original Astrill endpoint, and confirmed ordinary Ubuntu and phone
traffic used the same Direct ISP path. No temporary signed URL, tester identity,
device address, MAC address, or router credential was written to Git.

The root-sealed upload-signed QA APK was then independently checked as exact
version code `65`: its application ID, source commit, SHA-256, provenance, and
upload certificate all matched the formal manifest. This qualifies the APK for
application QA, but not as a Play-signed install. The attached MIUI phone still
required its secure device-side **Install via USB** confirmation. Both relevant
Developer options were enabled, but an injected ADB tap did not complete the
security dialog and later attempts remained `INSTALL_FAILED_USER_RESTRICTED`.
Temporary package-verifier experiments were restored. Do not spoof Play as the
installer, disable persistent security controls, or call this an installation;
leave the physical-install gate open until the device accepts the exact APK.

A physical iPad remained visible to Xcode command-line device services, but the
exact EchoMind app was not installed on it, so no iOS launch or screenshot QA
was claimed. Querying the physical inventory re-registered idle CoreSimulator
helpers even though no virtual device was booted. Stop the user registration
processes and root `simdiskimaged` again after such a query; the final process
readback was empty for Simulator, CoreSimulator, SimMetalHost, and
SimRenderServer.

## Reverting The UI Guard

Re-enable Apple's default framebuffer renderer only for a bounded diagnostic:

```bash
scripts/stabilize-optiplex-7050-simulator.sh restore-ui
```

This keeps all simulator devices shut down. A later UI launch may reproduce the
GPU hang. Run `stabilize` again immediately after the diagnostic.
