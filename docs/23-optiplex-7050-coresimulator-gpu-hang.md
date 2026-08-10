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

## Reverting The UI Guard

Re-enable Apple's default framebuffer renderer only for a bounded diagnostic:

```bash
scripts/stabilize-optiplex-7050-simulator.sh restore-ui
```

This keeps all simulator devices shut down. A later UI launch may reproduce the
GPU hang. Run `stabilize` again immediately after the diagnostic.
