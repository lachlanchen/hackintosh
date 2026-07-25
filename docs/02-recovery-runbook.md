# Recovery Runbook

Use the least invasive recovery path that still works.

## Recovery Order

1. **Sequoia SSH works:** inspect logs and fix only the development volume.
2. **OpenCore picker works:** boot the original volume named `Mac` (Monterey).
3. **Monterey SSH works:** repair the Sequoia snapshot or live EFI from
   Monterey.
4. **Windows boots:** use the prepared Windows BCD OpenCore entry and EFI
   restore script.
5. **No installed OS boots:** use separately verified external recovery media.

Do not erase or repartition the disk while any earlier recovery path remains.

## Distinguish the Two macOS Systems

After SSH returns, do not trust the desktop appearance. Verify:

```bash
sw_vers
diskutil info / | grep -E 'Device Node|Volume Name|APFS Volume Group|Sealed'
```

Expected volume names:

- `Mac`: protected Monterey recovery system
- `Sequoia-Dev`: development system

## Select One Volume for the Next Boot

From macOS:

```bash
sudo bless --mount /Volumes/Sequoia-Dev --setBoot --nextonly --verbose
```

To test Monterey while running Sequoia, mount the Monterey system volume first
and use the same one-time pattern. Always inspect the generated
`efi-boot-next` path and confirm it contains the intended APFS volume-group
path before rebooting.

## Revert a Root-Patched Sequoia Snapshot

List snapshots:

```bash
diskutil apfs listSnapshots /
```

When repairing the non-running Sequoia volume from Monterey:

```bash
sudo diskutil unmount <sequoia-system-device>
sudo mkdir -p /Volumes/Sequoia-RW
sudo mount_apfs -o nobrowse /dev/<sequoia-system-device> /Volumes/Sequoia-RW
sudo bless --mount /Volumes/Sequoia-RW --bootefi --last-sealed-snapshot
sudo bless --info --mount /Volumes/Sequoia-RW
sudo umount /Volumes/Sequoia-RW
```

The final `bless --info` output must name the original Apple-sealed snapshot.
Do not delete snapshots until the corrected boot is verified.

## Restore EFI from Windows

The private recovery bundle contains:

- a complete known-good EFI copy
- a SHA-256 file manifest
- a PowerShell restore script
- a BCD entry that chainloads OpenCore once

Use the script only after mounting the dedicated Mac/OpenCore EFI partition and
verifying the target partition by size and existing directory structure. Never
copy the Mac EFI over the Windows EFI partition.

## After Any Recovery

1. Record the actual volume and OS build.
2. Preserve the panic/log before clearing NVRAM.
3. Verify Ethernet/SSH.
4. Verify loaded graphics kext and Metal.
5. Reboot once more before declaring the repair stable.

