# Surface Book 2 Space Audit

Status date: 2026-07-26.

This is a read-only storage audit of the post-upgrade Sequoia installation.
No file, application, cache, snapshot, volume, or partition was removed or
moved during the audit.

## Capacity and accounting

The current macOS APFS container is 1.56 TB decimal. It has approximately
1.42 TB allocated and 137 GB unallocated, or about 128 GiB shown by `df`.
The Data volume accounts for almost all use.

APFS, Finder, and `du` do not always report identical values. APFS cloning,
compression, sparse files, mounted simulator images, and cloud placeholders
can all affect the result. The figures below are rounded observations intended
to rank decisions, not values that should be added as an exact equation.

| Area | Approximate allocated size | Main content |
| --- | ---: | --- |
| User home | 1.1 TiB | Personal data and per-user application state |
| User Library | 490 GiB | iCloud downloads, containers, caches, developer data |
| Pictures | 237 GiB | Almost entirely one Photos library |
| Documents | 103 GiB | Projects, books, video, and technical archives |
| Parallels | 80 GiB | Three virtual-machine bundles |
| Applications | 108 GiB | Scientific, developer, creative, and office apps |
| System-wide Library | 33 GiB | Shared support and developer components |
| Spotlight index | 19 GiB | Rebuildable search index, not a manual-delete target |

## Largest actionable groups

### 1. Locally downloaded iCloud Drive data

The local iCloud Drive tree occupies roughly 331 GiB. “Optimise Mac Storage”
is already enabled, but a large amount remains physically downloaded. This is
the largest low-risk opportunity if Finder reports that the relevant folders
are fully synchronized.

Use Finder's **Remove Download** action on completed, infrequently used
folders. This removes only the Mac's local copy while keeping the item in
iCloud. Do **not** use `rm`, move the folder out of iCloud Drive, or empty it
from Finder: those actions can remove it from iCloud and other devices.

Evict a few large folders at a time, confirm the cloud icon appears, and allow
Finder to settle before continuing. The theoretical local allocation is not a
guaranteed reclaim figure because macOS may retain active or pinned content.

### 2. Photos library

The Photos library occupies about 235 GiB, including roughly 205 GiB of
originals. There are two supported strategies:

1. If iCloud Photos is confirmed fully synchronized, enable **Optimise Mac
   Storage** in Photos settings and let macOS reduce local originals over time.
2. Move the complete Photos library to a real USB or Thunderbolt SSD formatted
   APFS or Mac OS Extended (Journaled), open it from the new location, and set
   it as the System Photo Library if required.

Do not place a Photos library on the mounted volume named `Ubuntu`, a network
share, a cloud-synchronized folder, a Time Machine volume, an SD card, or a
generic flash drive.

### 3. Parallels virtual machines

The three `.pvm` bundles occupy about 80 GiB:

| VM | Approximate size |
| --- | ---: |
| Largest Windows VM | 51 GiB |
| Second Windows VM | 20 GiB |
| Ubuntu VM | 9 GiB |

Parallels supports running a VM from an external SSD. Fully shut down the VM,
copy the entire `.pvm` bundle, verify the copy, double-click it on the external
disk, choose **Moved** when appropriate, and test it before removing the
original. Do not place an active VM in iCloud Drive.

### 4. Rebuildable application and developer data

The strongest cache candidate is an application asset cache occupying about
24 GiB. Quit the application first and prefer its own clear/reset operation;
if testing a manual cleanup later, move the cache aside, reopen and verify the
application, and delete the old copy only after a stable test.

Developer storage includes:

- about 8.4 GiB of CoreSimulator cache;
- about 11 GiB of simulator device data;
- ten unavailable iOS 16.2 devices, together occupying about 1 GiB;
- about 1.9 GiB of Xcode DerivedData;
- Xcode 16.2 and Xcode 26.2 installed side by side.

`xcrun simctl delete unavailable` is the narrow cleanup for stale devices.
Simulator caches and DerivedData can rebuild, but active simulator devices,
archives, provisioning data, and Xcode `UserData` should not be removed
blindly. Remove an Xcode app only after choosing the retained toolchain and
checking project compatibility.

### 5. App-managed chat and work data

Two communication-app containers use about 58 GiB combined. Most of the
larger container is message/media state rather than a simple cache. Use each
application's storage-management and export tools; do not manually delete its
container. The obvious cache portion is only a small fraction of the total.

### 6. Archives suitable for a portable disk

Documents, video, books, Raspberry Pi images, archived iCloud material, and
inactive projects account for well over 150 GiB. These are good relocation
candidates after identifying which projects are inactive. Keep active source
trees at stable paths or replace a moved tree with a deliberate symlink only
after all tools have been tested.

Scientific applications also consume substantial space. Uninstalling unused
MATLAB, COMSOL, an old Xcode, or other large applications can recover tens of
gigabytes, but only after confirming installers, licenses, and project
compatibility. Moving ordinary application bundles to a removable disk is
not the preferred strategy.

## The volume named `Ubuntu` is not portable storage

macOS lists `/Volumes/Ubuntu` as an external physical disk because a
third-party Linux filesystem driver exposes an LVM logical volume that way.
Hardware inspection identifies it as:

- the internal Samsung NVMe device;
- PCI Express;
- device location `Internal`;
- part of the installed Ubuntu LVM layout.

It has only about 104 GB free and will disappear if Ubuntu is reclaimed.
Copying files there would neither move them off the internal SSD nor provide
an independent backup.

A true portable target should report USB or Thunderbolt and an external
device location. For Photos plus all VMs, use an SSD with at least 500 GB free;
a 1 TB or larger APFS SSD provides sensible verification and growth headroom.

## Recommended order

1. Confirm important data has an independent backup.
2. In Finder, use **Remove Download** on the largest fully synchronized,
   inactive iCloud Drive folders. Target 150–250 GB first rather than evicting
   everything at once.
3. Clear the approximately 24 GiB asset cache through the application and
   remove unavailable simulator devices. Review other rebuildable caches.
4. Connect and positively identify a true external APFS SSD.
5. Copy and verify the Photos library and selected Parallels VMs before
   deleting any source copy.
6. Relocate inactive books, video, images, and archives with copy–verify–open–
   retain-old-temporarily discipline.
7. Reassess free space. Partition reclaim should be a later decision only if
   file-level cleanup is still insufficient.

A conservative first pass can plausibly recover 175–285 GB from synchronized
iCloud downloads and rebuildable caches. A verified external migration of the
Photos library and all VMs could move another approximately 315 GiB off the
internal SSD. These ranges overlap with normal macOS cleanup behavior and are
planning estimates, not promises.

## Do not delete manually

- the sealed APFS System snapshot;
- the Spotlight database as a first-line cleanup;
- iCloud Drive content with `rm`;
- Photos-library internals;
- active `.pvm` internals;
- communication-app containers;
- Xcode `UserData`, archives, or provisioning state;
- the misleadingly named internal `Ubuntu` volume;
- any Ubuntu partition independently of the complete LVM reclaim plan.

Partition geometry and the optional Windows/Ubuntu removal paths are covered
separately in
[Surface Book 2 Storage and Picker Policy](16-surface-book-2-storage-and-picker.md).
