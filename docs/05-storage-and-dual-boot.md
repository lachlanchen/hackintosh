# Storage and Dual Boot

## Verified Layout

The physical disk uses GPT and contains:

- a Windows EFI system partition
- a Windows data/system partition
- a dedicated Mac/OpenCore EFI partition
- one 240.2 GB APFS container

The APFS container now holds one System/Data volume group:

- Sequoia `Sequoia-Dev`

APFS volumes share free space dynamically. The smaller "capacity consumed"
number reported for Sequoia is current usage, not a quota. Sequoia can grow
into all remaining free space in the APFS container. The verified post-reboot
checkpoint on 2026-08-01 had 106.4 GB unallocated.

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

This originally left Monterey unchanged and independently bootable during the
Sequoia acceptance period. Monterey was later retired after the development OS,
Recovery metadata, remote access, and off-machine loader backups were verified.

## Space Policy

- Keep at least 40 GB free before a major macOS update.
- Keep at least 60 GB free before installing Xcode plus a simulator runtime.
- Remove obsolete installers only after a verified backup and stable reboot.
- Keep the ignored off-machine EFI backup and its SHA-256 manifest; it does not
  contain a backup of the retired Monterey user data.
- Prefer reproducible project caches and keep irreplaceable development data in
  a separate backup system.

The guarded retirement transaction and its acceptance checks are documented in
[OptiPlex 7050 Sequoia-only storage](22-optiplex-7050-sequoia-only-storage.md).
