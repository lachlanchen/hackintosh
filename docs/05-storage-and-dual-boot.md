# Storage and Dual Boot

## Verified Layout

The physical disk uses GPT and contains:

- a Windows EFI system partition
- a Windows data/system partition
- a dedicated Mac/OpenCore EFI partition
- one 240.2 GB APFS container

The APFS container holds two System/Data volume groups:

- Monterey `Mac`
- Sequoia `Sequoia-Dev`

APFS volumes share free space dynamically. The smaller "capacity consumed"
number reported for Sequoia is current usage, not a quota. Sequoia and Monterey
can both grow into all remaining free space in the APFS container.

The Windows partition is separate. Expanding APFS into Windows space would
require destructive partition resizing and is not justified while the APFS
container has substantial free space.

## Why Clone Instead of In-Place Upgrade

The Sequoia installer upgrades the current startup volume. The installer used
here did not expose a supported `--volume` argument. Therefore:

1. create an APFS System/Data pair,
2. replicate Monterey with `asr`,
3. boot the clone,
4. prove the clone's volume-group identity,
5. run `startosinstall` there.

This leaves the original Monterey system unchanged and independently bootable.

## Space Policy

- Keep at least 40 GB free before a major macOS update.
- Keep at least 60 GB free before installing Xcode plus a simulator runtime.
- Remove obsolete installers only after a verified backup and stable reboot.
- Do not remove the Monterey volume while this remains unsupported hardware.
- Prefer project caches on Sequoia; do not duplicate large media/model assets
  across both Data volumes.

