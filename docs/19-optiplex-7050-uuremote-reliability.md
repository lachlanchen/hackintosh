# OptiPlex 7050 UU Remote Reliability

Status date: 2026-08-01

## 2026-08-01 Hard Freeze

### Root-cause classification

The August 1 reboot supplied stronger evidence than the July incident. The
primary verified trigger was APFS capacity exhaustion, not a UU-only failure:

- the interactive stability guard recorded 1 GiB free at 01:01;
- it recorded 0 GiB free repeatedly from 01:05 through its final sample at
  01:44:58;
- WindowServer, VNC, and UU were still present at that last guard sample;
- the unified log ended at 01:58:42 and contained no further records until the
  physical reboot at 15:40;
- the reboot produced no panic report and reported shutdown cause 5.

The final three log minutes also contained 2,549 `rapportd` records and 1,089
`airportd` records. This 7050 has active Ethernet on `en0`, no Wi-Fi hardware
port, and no usable Bluetooth controller. Continuity services nevertheless
kept requesting CoreWLAN interface refreshes; individual refreshes stretched
to 4-6.5 seconds near the end of the log. This storm is a verified terminal
amplifier, but the available evidence cannot identify the exact instruction at
which the kernel stopped.

The evidence tiers are therefore:

| Classification | Finding |
| --- | --- |
| Verified primary trigger | The shared APFS container remained at 0 GiB free for about 53 minutes before the hard stall. |
| Verified terminal amplifier | Ethernet-only Continuity/CoreWLAN retries dominated the final logs. |
| Persistent hardware risk | The unused optical SATA-1 path continues to emit approximately one `AppleAHCIPort AbortCommands` event per second. |
| Historical, not causal for this event | Intel GPU restart reports exist from July 26-27, but none was produced during or after the August 1 freeze. |

Do not change the working EFI based on this incident. The optical SATA-1 loop
requires disabling only that port in Dell Setup or repairing its cable/drive;
it is not evidence against the system SSD, whose SMART state remains verified.

### Storage accounting

The internal SSD is 512.1 GB, but macOS does not own the whole device:

| Allocation | Capacity used or assigned |
| --- | ---: |
| Windows partition | 269.3 GB |
| macOS APFS container | 240.2 GB |
| Sequoia System + Data | about 127.2 GB |
| APFS support volumes and container overhead | about 6.6 GB |
| APFS container free after Monterey retirement and reboot | 106.4 GB |

APFS dynamically shares the container. Sequoia's Data volume, which holds
applications and user files, has quota 0 and can consume all container free
space. The displayed 160 GB quota belongs only to Sequoia's 18.4 GB sealed
System volume and does not limit user data. Removing it would require
recreating system storage and would provide no useful capacity.

The August cleanup reclaimed about 16.6 GiB without deleting projects, Codex
state, UU state, simulator runtimes, or either macOS volume. The largest
reproducible categories were 10.9 GiB of iOS DeviceSupport symbols, 2.5 GiB of
DerivedData, 1.4 GiB of Codex cache, and smaller Homebrew, Xcode, Python, and
application caches.

The booted Sequoia Data total is not another copy of macOS. It includes the
user account and currently includes at least 14 GiB of projects, 11 GiB of
pictures, 6.8 GiB of applications, and 4.2 GiB of developer data.

Windows and macOS cannot both own the Windows partition. Expanding the current
APFS container to the full SSD would require deleting or relocating Windows,
the intermediate EFI partition, and the trailing recovery partition. That is
a planned backup/repartition/restore operation, not a stability repair.

### Applied mitigation

The reversible Ethernet-only policy:

- prevents application/window restoration after login;
- disables Handoff advertising and receiving and disables AirDrop;
- disables the per-user `rapportd`, `sharingd`, and `bluetoothuserd` jobs;
- after `brctl status` reported CloudDocs caught-up and consistent, disables
  per-user `bird` and `FileProvider` so this development host does not resume
  iCloud Drive downloads or consistency scans;
- refuses to apply if a Wi-Fi hardware port exists, Ethernet is inactive, or
  the private machine identity does not match;
- leaves SSH, Screen Sharing, Apple Remote Desktop, and UU running.

Machine-specific Ethernet identity is stored locally with mode 600 and is not
committed:

```text
~/.config/optiplex-7050-ethernet-stability/environment
```

The interactive guard now has three free-space levels:

| Free space | Action |
| --- | --- |
| Below 25 GiB | Record a warning. |
| Below 15 GiB | Gracefully shut down booted Simulator devices. |
| Below 8 GiB | Once per six hours, quit heavy apps gracefully and remove only allow-listed reproducible developer/cache data. |

The emergency action never deletes projects, cloud documents, UU state, Codex
state, simulator runtimes, or APFS volumes. It is a last-resort protection
against another zero-space hard lock, not routine housekeeping.

iCloud Drive storage optimization was already enabled. Photos optimization is
also enabled after this incident. The additional per-user iCloud Drive job
disablement stops document sync in both directions on this host; it was applied
only after the main CloudDocs container reported caught-up and consistent.
Photos optimization was enabled at that checkpoint. Photos sync was later
disabled for this development host and the supported `Delete from Mac` choice
was accepted; the cloud library remains intact while local Photos data may
shrink asynchronously. Use the policy script's `rollback` mode to restore the
captured launchd states before using iCloud Drive here again.

Audit and rollback:

```bash
./scripts/stabilize-optiplex-7050-ethernet-only.sh audit
./scripts/stabilize-optiplex-7050-ethernet-only.sh rollback
./scripts/install-macos-interactive-stability-guard.sh audit
./scripts/install-macos-interactive-stability-guard.sh uninstall
```

### Monterey fallback cleanup (historical)

This section records the intermediate state before Monterey retirement. Do not
run its volume-specific commands on the current Sequoia-only layout.

The retained Monterey 12.7.6 volume group was bootable and kept its user, SSH,
UU, and core tool state. A guarded cleanup removed only fallback leftovers:

- the completed 15 GiB `Install macOS Sequoia.app` bundle, after validating its
  bundle identifier;
- a stale 2 GiB sleep image;
- 278 MiB of migration `Previous Content`;
- a quarantined document-revisions directory, caches, and Trash.

The cleanup reported 17,441 MiB reclaimed. Monterey Data fell from 42.5 GB to
24.1 GB, and shared APFS free space stabilized at 46.2 GiB. Sequoia's Xcode
26.3, iOS 26.3 runtime, projects, pictures, archives, and Codex state were
preserved.

A later allow-listed Sequoia cleanup removed 3,042 MiB reported by `du` from
CloudKit cache and 2,475 MiB from closed GlassAgent logs. Concurrent APFS and
system activity means directory totals do not translate one-for-one into
container free space; the authoritative final container values were 188.2 GB
used and 52.1 GB free (about 48.5 GiB). There are no snapshots on the Sequoia
Data volume.

Audit and apply with the mounted Monterey Data path supplied explicitly:

```bash
./scripts/cleanup-optiplex-7050-monterey-fallback.sh audit \
  --volume '/Volumes/<Monterey Data>' --user <account>

sudo ./scripts/cleanup-optiplex-7050-monterey-fallback.sh apply \
  --volume '/Volumes/<Monterey Data>' --user <account> \
  --confirm CLEAN-7050-MONTEREY-FALLBACK
```

Live `diskutil verifyVolume` returns exit code 0 but repeatedly detects a
directory-statistics mismatch and reports that a repair action was deferred.
`diskutil repairVolume` cannot repair that sibling Data volume while Sequoia
volumes in the same APFS container are mounted. At the next planned
maintenance window, boot macOS Recovery and run Disk Utility First Aid on the
APFS container and Monterey volume group. This is not a reason to change EFI
or erase the fallback.

The equivalent guarded Terminal workflow is
[`repair-optiplex-7050-apfs-from-recovery.sh`](../scripts/repair-optiplex-7050-apfs-from-recovery.sh).
Recovery can assign different disk numbers on every boot, so first discover
them rather than copying identifiers from this document:

```bash
/usr/sbin/diskutil list
/usr/sbin/diskutil apfs listVolumeGroups

/bin/cp /Volumes/<source>/repair-optiplex-7050-apfs-from-recovery.sh \
  /tmp/repair-optiplex-7050-apfs-from-recovery.sh

/bin/sh /tmp/repair-optiplex-7050-apfs-from-recovery.sh audit \
  --container diskN --data diskNsN

/bin/sh /tmp/repair-optiplex-7050-apfs-from-recovery.sh repair \
  --container diskN --data diskNsN \
  --confirm REPAIR-7050-MONTEREY-DATA
```

The script checks every Recovery command by absolute path, validates APFS
container membership and the Data role, and refuses a container hosting the
current root. It uses a normal unmount only, repairs and verifies the selected
volume, remounts the container, and writes a timestamped log under `/tmp`.
It never force-unmounts, erases, repartitions, modifies EFI, or depends on
shell profile environment variables. If normal unmount fails, close Disk
Utility windows and rerun it; do not substitute a forced unmount.

Copying the helper to `/tmp` before execution is intentional: the source may
reside on the APFS container that the repair must unmount. Copy the generated
log from `/tmp` to persistent storage before leaving Recovery if it is needed.

The later guarded volume-group deletion removed that Monterey group and its
stale Preboot/Recovery records. Both active Sequoia volumes subsequently passed
live APFS verification. See
[OptiPlex 7050 Sequoia-only storage](22-optiplex-7050-sequoia-only-storage.md).

## Incident Evidence

The host stopped answering Ethernet ARP, ping, SSH, Screen Sharing, and UU
Remote. Wake-on-LAN received no response. A physical power cycle returned the
host.

Evidence captured immediately after boot:

- no new kernel panic or sleep/wake failure report;
- no normal shutdown record for the prior boot;
- `Previous shutdown cause: 5` after the physical restart;
- no memory, thermal, disk SMART, or APFS health warning;
- the current Intel graphics `recoveryCount` was zero;
- macOS, SSH, Screen Sharing, and all three signed UU processes returned.

This supports a whole-system lock or power-level failure, but it does not prove
a root cause. UU Remote was unavailable because the host was unavailable; it
was not shown to have caused the lock.

After the reboot, two pressure events supplied a plausible freeze mechanism:

- a booted iOS 26.3 Simulator spawned hundreds of runtime services and drove
  one-minute load above 500;
- the host iCloud Drive File Provider repeatedly consumed more than one CPU
  core while reconciling a large metadata database.

`xcrun simctl shutdown all` reduced the Simulator runtime process count to
zero without deleting device data. An orderly launchd restart of
`com.apple.FileProvider` gave iCloud a fresh process, and that process settled
temporarily. A later process sample identified the recurring CPU work as
`com.apple.fileproviderd.periodic-fpck`, macOS's periodic File Provider
consistency check, performing SQLite metadata maintenance. The one-minute
system load remained low while that check ran, so it was left to complete.
Repeatedly restarting File Provider can restart or prolong the same maintenance
and is not an appropriate watchdog action. A separate read-only
`fileproviderctl check` did not complete within two minutes and was terminated;
repair mode was not used.

These events are verified after the reboot but are not proof that either one
caused the earlier lock. They explain why a low-risk resource guard is useful.

Do not change the known-good Sequoia EFI from this single incident. In
particular, do not remove graphics properties or watchdog boot arguments
without a hash-gated candidate, rollback EFI, and physical boot test.

## Login Session Handoff

A separate, reproducible disconnect happened when the operator logged in from
UU Remote:

1. UU served the macOS login-window session.
2. Login terminated that launch-agent instance.
3. launchd created a new Aqua-session agent and server.
4. The new room reached UU states `9002`, `9003`, and `9004`.
5. The original controller session still disconnected during the handoff.

Accessibility and Screen Capture are already allowed for the signed
`com.netease.uuremote` bundle. The launch daemon and launch agent both use
`KeepAlive` and `RunAtLoad`. The app is signed by Team ID `PU9BNSBJW7`.

Automatic login is appropriate only for this physically controlled,
single-user remote workstation. It skips the login-window-to-Aqua transition
after reboot. It also allows anyone with physical access to reach the desktop,
and its local credential storage is reversible obfuscation rather than strong
encryption.

Apple documents the supported GUI control at System Settings, Users & Groups,
Automatically log in as. FileVault must be off. On this host,
`sysadminctl -autologin set` returned `SACSetAutoLoginPassword error:22`, so the
same loginwindow preference and protected `/etc/kcpassword` state were created
with a guarded fallback and verified with:

```bash
sudo sysadminctl -autologin status
```

Rollback:

```bash
sudo sysadminctl -autologin off
sudo rm -f /etc/kcpassword
sudo defaults delete \
  /Library/Preferences/com.apple.loginwindow autoLoginUser
```

## macOS Watchdog

Install:

```bash
sudo ./scripts/install-optiplex-7050-uuremote-watchdog.sh install
```

The launch job runs once per minute. It:

- verifies the signed UU bundle and expected Team ID before repair;
- records console user, boot UUID, process IDs, connection count, load, and
  free data-volume space;
- records Simulator runtime count and File Provider CPU;
- gracefully shuts down all Simulator devices only when runtime process count
  is at least 100 and one-minute load is at least 100;
- leaves UU untouched during the first three boot minutes;
- leaves UU untouched when internet validation fails;
- waits for five consecutive unhealthy checks;
- restarts only the current GUI UU agent;
- never reboots macOS and never modifies TCC, login data, or the EFI.

The Simulator threshold is an emergency pressure limit, not a normal
development policy. A normal booted simulator remains untouched. The monitor
does not automatically terminate or repair File Provider because interrupted
cloud database work has a larger data-integrity risk than elevated CPU.

Status and rollback:

```bash
sudo ./scripts/install-optiplex-7050-uuremote-watchdog.sh status
sudo ./scripts/install-optiplex-7050-uuremote-watchdog.sh uninstall
```

## External Linux Monitor

Install from the trusted Ubuntu peer:

```bash
./scripts/install-optiplex-7050-linux-monitor.sh \
  --host <key-only-ssh-alias> \
  --mac <ethernet-mac>
```

The installer stores host-specific values in a mode-600 user configuration,
not in Git. The systemd user timer checks key-only SSH every minute, records
the last remote health sample, logs only state transitions, and sends
rate-limited Wake-on-LAN after three failed checks.

Useful checks:

```bash
systemctl --user status optiplex-7050-monitor.timer
systemctl --user status optiplex-7050-monitor.service
journalctl --user -u optiplex-7050-monitor.service
```

Wake-on-LAN can start a powered-off host whose firmware and NIC permit it. It
cannot power-cycle a machine whose CPU or firmware is hard locked. Fully
unattended recovery from that state requires an independently controllable
power device or correctly configured Intel AMT; neither should be assumed
without a separate hardware and firmware audit.

## Permission Policy

Do not edit a TCC database to suppress macOS consent prompts. A user grant for
the stable signed bundle persists normally. A repeatable fleet deployment
would require an MDM Privacy Preferences Policy Control profile tied to the
exact bundle identifiers and signing requirement. This unmanaged workstation
has no MDM enrollment, so the one-time user approval remains the correct
security boundary.
