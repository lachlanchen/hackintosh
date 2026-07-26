# Surface Book 2 Storage and Picker Policy

Status date: 2026-07-26.

This document records the post-Sequoia storage audit and the minimal OpenCore
picker cleanup. No partition was removed or resized during this work.

## Current capacity

The in-place Sequoia installation uses one 1.6 TB APFS container. At the
latest audited checkpoint it had approximately 137 GB free inside the
container, which is immediately usable by macOS. The small change from an
earlier 142 GB checkpoint reflects ordinary application and user-data growth,
not a new partition.

There is no separate old Sonoma System/Data volume group to delete. The normal
upgrade replaced Sonoma's sealed System volume while preserving the same user
Data volume. Treating "Sonoma" as a separate disposable partition would risk
the current Sequoia installation and its data.

The remaining physical layout is:

| Order | Approximate size | Actual role |
| --- | ---: | --- |
| EFI | 315 MB | OpenCore plus Windows and Ubuntu EFI loaders |
| Microsoft reserved | 17 MB | Windows metadata |
| Main APFS | 1.6 TB | Current Sequoia System/Data group |
| Ubuntu LVM member 1 | 98.7 GB | First member of `vg-ubuntu`; adjacent to APFS |
| Windows | 208.8 GB | Windows system/data partition |
| Ubuntu boot | 1.0 GB | ext4 boot filesystem |
| Ubuntu LVM member 2 | 131.4 GB | Second member of `vg-ubuntu` |

The 98.7 GB entry is misleadingly typed `Apple_APFS` in GPT, but raw,
read-only inspection identifies an LVM2 physical volume. The second LVM member
contains the same `vg-ubuntu` metadata. Removing either member alone destroys
the Ubuntu logical volume.

## What can be reclaimed

The current APFS free space is sufficient for normal Sequoia use and another
major application/toolchain installation, subject to ordinary free-space
monitoring.

If Ubuntu is no longer needed:

- approximately 98.7 GB can be added directly to the main APFS container
  because that LVM member is physically adjacent;
- approximately 132.5 GB can be freed behind Windows;
- the trailing 132.5 GB cannot be joined to macOS without moving Windows.

The trailing space should initially remain free. A later, separate decision
can make it an APFS or ExFAT data volume, or handle it from Windows. The
reclaim helper deliberately does not guess that policy.

### If Windows is kept

Windows currently occupies approximately 120 GB of its 209 GB partition, so
it already has about 89 GB free. Removing Ubuntu can therefore be handled
without resizing Windows:

- add the adjacent 98.7 GB to macOS;
- leave the approximately 132.5 GB behind Windows unallocated until there is
  a clear use for it; or
- extend Windows into that trailing space as a separate Windows-side action.

Windows Disk Management can extend a volume only into unallocated space
immediately to its right. Its shrink operation also creates space on the
right side of the volume. Consequently, extending Windows into the tail and
then shrinking it cannot move Windows to the right or create macOS-usable
space before Windows.

Moving Windows would require a verified image/restore or a separate,
high-risk partition-moving procedure. It is intentionally outside the helper.

### If Windows and Ubuntu are both removed

After independent backups, deleting partitions 4 through 7 would leave the
main APFS physical store followed by approximately 440 GB of contiguous free
space. APFS could then grow through the entire former Ubuntu, Windows, and
Ubuntu-tail region. Together with the current free capacity, macOS would have
roughly 577 GB free before later data growth.

The shared EFI partition must remain. The tiny Microsoft Reserved partition
is before APFS, so deleting it would not help APFS grow and is not worth
disturbing. No current script automates Windows removal.

This partition-level option is much more disruptive than reclaiming ordinary
files. The ranked file cleanup and external-storage plan is documented in
[the space audit](17-surface-book-2-space-audit.md).

## Clean OpenCore picker

The already-proven boot-routing settings remain:

```text
ShowPicker = true
HideAuxiliary = true
Timeout = 5
LauncherOption = Full
AllowSetDefault = true
RequestBootVarRouting = true
```

The current macOS Preboot path is the NVRAM default, so an unattended timeout
selects Sequoia.

Two reversible post-upgrade changes reduce picker clutter:

1. `OpenLinuxBoot.efi` remains present but is disabled in `config.plist`, so
   OpenCore does not add direct Linux-kernel entries.
2. The Ubuntu EFI loader directory has a `.contentVisibility` file containing
   the exact ASCII token `Auxiliary`.

With `HideAuxiliary = true`, the normal picker should show Sequoia and Windows.
Press **Space** in the picker to reveal Ubuntu, macOS Recovery, and tools.
Ubuntu has not been erased or made unbootable.

The prior live config and a complete EFI copy were preserved before this
change. XML parsing passed, and the modified config produced exactly the same
two pre-existing OpenCore-Mod validator findings as the proven baseline. This
picker-only revision is installed but should be marked reboot-verified only
after the next normal restart.

## Guarded reclaim helper

[`surface-book-2-storage-reclaim.sh`](../scripts/surface-book-2-storage-reclaim.sh)
is read-only unless its explicit `apply` mode is selected.

Audit:

```bash
sudo ./scripts/surface-book-2-storage-reclaim.sh audit disk0
```

Show the proposed operation:

```bash
sudo ./scripts/surface-book-2-storage-reclaim.sh plan disk0
```

The helper refuses a changed disk size, partition offset, partition size,
filesystem signature, current macOS physical store, SMART state, Windows
identity, EFI identity, FileVault state, or lack of AC power. Apply mode also
requires a new absolute backup directory and two exact confirmations.

Apply mode:

```bash
sudo ./scripts/surface-book-2-storage-reclaim.sh apply \
  disk0 \
  /absolute/new/private/backup-directory \
  ERASE-UBUNTU-AND-RECLAIM-disk0
```

Do not run `apply` until every wanted Ubuntu file has an independent backup
and the operator has explicitly decided to destroy Ubuntu. The helper first
backs up GPT sectors, partition headers, signatures, disk diagnostics, and its
own source. It then removes the adjacent LVM member, grows the current APFS
store, removes the remaining Ubuntu members, and rechecks Windows and EFI.

There is no automatic rollback after partition removal. A refusal or failure
after destructive work starts must be inspected from the generated operation
record rather than retried blindly.

## Safety boundary

- Do not delete the 98.7 GB partition by itself while Ubuntu matters.
- Do not try to grow APFS through the Windows partition.
- Do not use a generic partition-number recipe on another computer.
- Do not interpret the in-place Sequoia upgrade as two removable macOS
  installations.
- Keep the complete EFI and user-data backups independent of this SSD.
