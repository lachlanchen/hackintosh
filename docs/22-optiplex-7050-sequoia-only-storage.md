# OptiPlex 7050 Sequoia-Only Storage

Status date: 2026-08-01

## Result

The former Monterey System/Data volume group was permanently removed after
Sequoia had become the accepted development system. The transaction did not
erase, repartition, resize, or edit:

- the active Sequoia System/Data volume group;
- the OpenCore EFI system partition;
- Windows Boot Manager or its EFI system partition;
- Xcode, projects, release outputs, UU Remote state, or user data on Sequoia.

After a clean reboot, Sequoia 15.7.7 returned unattended on its original sealed
snapshot. The 240.2 GB APFS container had 106.4 GB unallocated, UU Remote and
Apple Remote Desktop returned automatically, and key-only SSH remained usable.

Deleting an APFS volume is irreversible. Apple's Disk Utility guide states that
deleting a volume permanently erases its data and removes it from the container:
[Delete an APFS volume](https://support.apple.com/en-asia/guide/disk-utility/dskua9e6a110/mac).

## Safety Boundary

The deletion was allowed only after all of these identities were independently
resolved from the live host:

| Identity | Required evidence |
| --- | --- |
| Running OS | `sw_vers` reported the accepted Sequoia build |
| Running root | `diskutil info /` resolved to the Sequoia System volume |
| Running Data | `/System/Volumes/Data` resolved to Sequoia Data |
| Active group | Root and Data belonged to the same Sequoia volume group |
| Target group | Both target members were explicitly named as Monterey System and Data |
| Boot default | `bless` and NVRAM pointed to the active Sequoia group |
| Workload | No Xcode build, archive, notarization, or upload was active |
| Recovery | Key-only SSH, UU Remote, ARD, and Windows loaders were healthy |

Disk identifiers and APFS UUIDs are intentionally omitted from Git. They can
change after recovery or reinstallation and must always be rediscovered.

## Off-Machine Checkpoint

Before deletion, the Ubuntu peer stored an ignored, timestamped checkpoint with:

- the complete OpenCore EFI tree;
- the Windows `EFI/Microsoft` and fallback `EFI/Boot` trees;
- a SHA-256 manifest for every copied file;
- APFS, GPT, bless, NVRAM, and picker evidence;
- Sequoia data-directory size sentinels;
- GlassAgent root/submodule state and release-artifact counts;
- Xcode version and signature evidence.

The manifest was checked from the Ubuntu copy before proceeding. This is a
loader/configuration recovery checkpoint, not a backup of deleted Monterey user
data. Irreplaceable user data still requires an independent backup system.

## Guarded Transaction Pattern

First discover, never assume, the current and target identifiers:

```bash
sw_vers
diskutil info /
diskutil info /System/Volumes/Data
diskutil apfs listVolumeGroups
bless --getBoot
bless --info /
nvram -p | grep -E 'efi-(backup-)?boot-device'
```

The operator must record the active Sequoia group and the separately identified
Monterey group. A transaction wrapper should refuse to continue when:

- either variable is empty;
- the active and target groups are equal;
- the current root or Data device appears in the target group;
- the target does not contain exactly the expected Monterey System and Data
  roles;
- a second read immediately before deletion differs from the audit.

Only after those guards pass is the destructive primitive appropriate:

```bash
sudo diskutil apfs deleteVolumeGroup "$MONTEREY_GROUP"
```

Do not replace this with partition deletion, container deletion, `eraseDisk`,
or a copied `diskN` identifier. Those operations have a different and much
larger blast radius.

## Picker Cleanup

`deleteVolumeGroup` removed Monterey's System/Data members and their associated
Preboot and Recovery directories. The remaining Sequoia Preboot metadata was
then rebuilt against the running root:

```bash
sudo diskutil apfs updatePreboot "$SEQUOIA_SYSTEM" -od /
```

The existing OpenCore configuration already had the desired behavior:

- graphical external picker with the GoldenGate resources;
- picker visible for five seconds;
- auxiliary entries hidden by default;
- full launcher option;
- Sequoia saved as the persistent default;
- Windows loader preserved independently.

No EFI configuration change was needed. OpenCore discovers APFS systems from
Preboot metadata, so removing the stale APFS group and rebuilding the surviving
metadata is cleaner than adding a custom hide rule. The live OpenCore and
Windows loader hashes remained identical to the pre-change checkpoint.

## Acceptance Checks

The operation was not accepted until all of these checks passed:

```bash
diskutil apfs listVolumeGroups
diskutil apfs list
diskutil verifyVolume /
diskutil verifyVolume /System/Volumes/Data
bless --getBoot
bless --info /
```

Additional checks confirmed:

- only the Sequoia group remained in the macOS APFS container;
- the retired group was absent from NVRAM, Preboot, and mounted Recovery;
- Sequoia System and Data each passed live read-only `fsck_apfs` with exit 0;
- critical development directories and the Xcode application remained present;
- GlassAgent's root commit and submodule state were unchanged;
- Xcode 26.3 remained selected and its deep code-signature verification passed;
- no build or publishing process was interrupted;
- OpenCore and Windows EFI partitions were unmounted cleanly after audit.

Finally, one controlled reboot proved that OpenCore still selected Sequoia
after the five-second timeout. The same sealed root snapshot and Data volume
returned, followed by the console user, UU Remote, ARD, and SSH.

## Recovery After Retirement

The current recovery order is now:

1. key-only SSH into running Sequoia;
2. `Sequoia-Dev` in the OpenCore picker;
3. the auxiliary Sequoia APFS Recovery entry, revealed with Space;
4. Windows plus the private hash-verified EFI restore checkpoint;
5. separately verified external recovery media.

Monterey is no longer a rollback choice. Historical docs that describe the
clone and Monterey acceptance period explain how Sequoia was established, but
they do not describe the current boot inventory.
