#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

usage() {
  cat >&2 <<'EOF'
usage:
  sudo surface-book-2-storage-reclaim.sh audit [disk0]
  sudo surface-book-2-storage-reclaim.sh plan [disk0]
  sudo surface-book-2-storage-reclaim.sh apply disk0 ABSOLUTE_BACKUP_DIR \
    ERASE-UBUNTU-AND-RECLAIM-disk0

Audit or reclaim the verified Surface Book 2 storage layout.

The read-only audit and plan modes require the exact pre-reclaim layout:

  disk0s3  current macOS APFS physical store
  disk0s4  first Ubuntu LVM physical volume, adjacent to macOS
  disk0s5  Windows
  disk0s6  Ubuntu ext4 boot volume
  disk0s7  second Ubuntu LVM physical volume

Apply mode permanently destroys the complete Ubuntu installation. It grows
the current macOS APFS container into the adjacent ~98.7 GB only. The
remaining ~132.5 GB after Windows is left as free space because it cannot be
joined to macOS across the Windows partition.

Apply mode is deliberately difficult to trigger. It requires:

  - macOS booted from the expected internal APFS store;
  - AC power;
  - exact partition offsets, sizes, types, and Linux signatures;
  - a new absolute backup directory;
  - the command-line confirmation token shown above;
  - the same confirmation typed interactively after metadata backup.

No operation removes Windows, OpenCore, the EFI partition, or user data in
the current macOS APFS container. There is no automatic partition rollback.
EOF
  exit 64
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

plist_value() {
  local device=$1
  local key=$2
  diskutil info -plist "$device" |
    plutil -extract "$key" raw -o - - 2>/dev/null
}

expect_value() {
  local device=$1
  local key=$2
  local expected=$3
  local actual
  actual=$(plist_value "$device" "$key") ||
    die "could not read $key from $device"
  [[ $actual == "$expected" ]] ||
    die "$device $key changed: expected '$expected', found '$actual'"
}

expect_partition() {
  local device=$1
  local content=$2
  local size=$3
  local offset=$4

  expect_value "$device" ParentWholeDisk "$whole_disk"
  expect_value "$device" Internal true
  expect_value "$device" Content "$content"
  expect_value "$device" Size "$size"
  expect_value "$device" PartitionMapPartitionOffset "$offset"
}

gb() {
  awk -v bytes="$1" 'BEGIN { printf "%.1f GB", bytes / 1000000000 }'
}

assert_not_mounted() {
  local device=$1
  if mount | grep -Eq "^/dev/${device}[[:space:]]"; then
    die "$device is mounted"
  fi
}

resolve_uuid() {
  local uuid=$1
  local device
  device=$(plist_value "$uuid" DeviceIdentifier) ||
    die "could not resolve partition UUID $uuid"
  expect_value "$device" DiskUUID "$uuid"
  expect_value "$device" ParentWholeDisk "$whole_disk"
  printf '%s\n' "$device"
}

assert_uuid_absent() {
  local uuid=$1
  if diskutil info "$uuid" >/dev/null 2>&1; then
    die "partition UUID $uuid still exists after the requested removal"
  fi
}

run_logged() {
  "$@" 2>&1 | tee -a "$operation_log"
}

[[ $# -ge 1 ]] || usage
mode=$1
case $mode in
  audit|plan)
    [[ $# -le 2 ]] || usage
    whole_disk=${2:-disk0}
    ;;
  apply)
    [[ $# -eq 4 ]] || usage
    whole_disk=$2
    backup_dir=$3
    confirmation=$4
    ;;
  *)
    usage
    ;;
esac

whole_disk=${whole_disk#/dev/}
case $whole_disk in
  disk*) ;;
  *) die "whole disk must look like disk0, not '$whole_disk'" ;;
esac
case ${whole_disk#disk} in
  ''|*[!0-9]*)
    die "whole disk must look like disk0, not '$whole_disk'"
    ;;
esac

[[ $(uname -s) == Darwin ]] ||
  die "this script must run from macOS"
[[ ${EUID:-$(id -u)} -eq 0 ]] ||
  die "run this script with sudo so raw signatures can be verified"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/sb2-storage-audit.XXXXXX")
destructive_started=0
cleanup() {
  status=$?
  trap - EXIT
  rm -rf "$scratch"
  if [[ $status -ne 0 && $destructive_started -eq 1 ]]; then
    printf '%s\n' \
      "WARNING: a destructive step had started before the failure." \
      "Do not guess or rerun blindly; inspect the backup and operation log." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

root_store="${whole_disk}s3"
adjacent_lvm="${whole_disk}s4"
windows_partition="${whole_disk}s5"
ubuntu_boot="${whole_disk}s6"
tail_lvm="${whole_disk}s7"

# Exact verified layout on 2026-07-26. These checks intentionally make the
# script refuse to operate after any partition-map change.
whole_size=2000398934016
root_size=1560000000000
root_offset=333447168
adjacent_size=98713751552
adjacent_offset=1560333447168
windows_size=208842044416
windows_offset=1659047201280
ubuntu_boot_size=1024000000
ubuntu_boot_offset=1867889246208
tail_size=131435855872
tail_offset=1868962988032

expect_value "$whole_disk" WholeDisk true
expect_value "$whole_disk" Internal true
expect_value "$whole_disk" Content GUID_partition_scheme
expect_value "$whole_disk" Size "$whole_size"
expect_value "$whole_disk" SMARTStatus Verified

current_root_store=$(
  diskutil info -plist / |
    plutil -extract APFSPhysicalStores.0.APFSPhysicalStore raw -o - -
)
[[ $current_root_store == "$root_store" ]] ||
  die "current macOS root is on $current_root_store, not $root_store"
expect_value "$root_store" APFSContainerReference \
  "$(plist_value / APFSContainerReference)"

expect_partition "$root_store" Apple_APFS "$root_size" "$root_offset"
expect_partition "$adjacent_lvm" Apple_APFS \
  "$adjacent_size" "$adjacent_offset"
expect_partition "$windows_partition" "Microsoft Basic Data" \
  "$windows_size" "$windows_offset"
expect_partition "$ubuntu_boot" "Linux Filesystem" \
  "$ubuntu_boot_size" "$ubuntu_boot_offset"
expect_partition "$tail_lvm" "Linux Filesystem" "$tail_size" "$tail_offset"
expect_value "$windows_partition" VolumeName Windows
expect_value "$ubuntu_boot" VolumeName boot

[[ $((root_offset + root_size)) -eq $adjacent_offset ]] ||
  die "the first Ubuntu LVM partition is no longer adjacent to macOS"

for device in "$adjacent_lvm" "$ubuntu_boot" "$tail_lvm"; do
  assert_not_mounted "$device"
done

file -s "/dev/r$adjacent_lvm" >"$scratch/adjacent-signature.txt"
file -s "/dev/r$ubuntu_boot" >"$scratch/boot-signature.txt"
file -s "/dev/r$tail_lvm" >"$scratch/tail-signature.txt"
grep -Fq "LVM2 PV" "$scratch/adjacent-signature.txt" ||
  die "$adjacent_lvm is not an LVM2 physical volume"
grep -Fq "ext4 filesystem" "$scratch/boot-signature.txt" ||
  die "$ubuntu_boot is not an ext4 filesystem"
grep -Fq 'volume name "boot"' "$scratch/boot-signature.txt" ||
  die "$ubuntu_boot does not have the expected boot label"
grep -Fq "LVM2 PV" "$scratch/tail-signature.txt" ||
  die "$tail_lvm is not an LVM2 physical volume"

dd if="/dev/r$adjacent_lvm" bs=4096 count=256 2>/dev/null |
  strings >"$scratch/adjacent-lvm-strings.txt"
dd if="/dev/r$tail_lvm" bs=4096 count=256 2>/dev/null |
  strings >"$scratch/tail-lvm-strings.txt"
grep -Fq "vg-ubuntu {" "$scratch/adjacent-lvm-strings.txt" ||
  die "$adjacent_lvm does not identify the expected Ubuntu volume group"
grep -Fq "vg-ubuntu {" "$scratch/tail-lvm-strings.txt" ||
  die "$tail_lvm does not identify the expected Ubuntu volume group"

gpt -r show "/dev/$whole_disk" >"$scratch/gpt-before.txt"
grep -Eq \
  '^[[:space:]]*3047526264[[:space:]]+192800296[[:space:]]+4[[:space:]]+GPT part - 7C3457EF-0000-11AA-AA11-00306543ECAC$' \
  "$scratch/gpt-before.txt" ||
  die "GPT entry 4 no longer matches the verified layout"
grep -Eq \
  '^[[:space:]]*3648221184[[:space:]]+2000000[[:space:]]+6[[:space:]]+GPT part - 0FC63DAF-8483-4772-8E79-3D69D8477DE4$' \
  "$scratch/gpt-before.txt" ||
  die "GPT entry 6 no longer matches the verified layout"
grep -Eq \
  '^[[:space:]]*3650318336[[:space:]]+256710656[[:space:]]+7[[:space:]]+GPT part - 0FC63DAF-8483-4772-8E79-3D69D8477DE4$' \
  "$scratch/gpt-before.txt" ||
  die "GPT entry 7 no longer matches the verified layout"

root_container=$(plist_value / APFSContainerReference)
root_free=$(plist_value / APFSContainerFree)
root_filevault=$(plist_value / FileVault)
root_store_uuid=$(plist_value "$root_store" DiskUUID)
adjacent_uuid=$(plist_value "$adjacent_lvm" DiskUUID)
windows_uuid=$(plist_value "$windows_partition" DiskUUID)
ubuntu_boot_uuid=$(plist_value "$ubuntu_boot" DiskUUID)
tail_uuid=$(plist_value "$tail_lvm" DiskUUID)
efi_uuid=$(plist_value "${whole_disk}s1" DiskUUID)

printf 'VERIFIED_LAYOUT=yes\n'
printf 'MACOS_VERSION=%s\n' "$(sw_vers -productVersion)"
printf 'WHOLE_DISK=%s\n' "$whole_disk"
printf 'MACOS_APFS_STORE=%s\n' "$root_store"
printf 'MACOS_APFS_CONTAINER=%s\n' "$root_container"
printf 'MACOS_FREE=%s\n' "$(gb "$root_free")"
printf 'UBUNTU_ADJACENT_TO_MACOS=%s\n' "$(gb "$adjacent_size")"
printf 'UBUNTU_BEHIND_WINDOWS=%s\n' \
  "$(gb "$((ubuntu_boot_size + tail_size))")"
printf 'MACOS_RECLAIMABLE_IF_ALL_UBUNTU_IS_REMOVED=%s\n' \
  "$(gb "$adjacent_size")"
printf '%s\n' \
  "NOTE=The space behind Windows cannot be joined to macOS without moving Windows."

if [[ $mode == audit ]]; then
  exit 0
fi

if [[ $mode == plan ]]; then
  cat <<EOF

No changes made. Apply mode would execute this guarded sequence:
  1. Back up GPT sectors, partition metadata, and diagnostics.
  2. Remove $adjacent_lvm and grow $root_store to fill that adjacent gap.
  3. Remove $tail_lvm and then $ubuntu_boot.
  4. Re-verify the EFI, Windows, and macOS partition identities.

The final tail space remains free. It may later become a separate APFS/ExFAT
data partition or be handled from Windows; this script will not guess.
EOF
  exit 0
fi

[[ $root_filevault == false ]] ||
  die "FileVault state changed; this procedure was not validated for it"
pmset -g batt | grep -Fq "AC Power" ||
  die "connect AC power before applying partition changes"

expected_confirmation="ERASE-UBUNTU-AND-RECLAIM-$whole_disk"
[[ $confirmation == "$expected_confirmation" ]] ||
  die "the command-line confirmation token is incorrect"
case $backup_dir in
  /*) ;;
  *) die "backup directory must be an absolute path" ;;
esac
[[ $backup_dir != / ]] || die "backup directory cannot be /"
[[ ! -e $backup_dir ]] ||
  die "backup path already exists; provide a new directory"
[[ -d $(dirname "$backup_dir") ]] ||
  die "backup parent does not exist: $(dirname "$backup_dir")"

mkdir -m 0700 "$backup_dir"
operation_log="$backup_dir/operation.log"
: >"$operation_log"

diskutil list "$whole_disk" >"$backup_dir/diskutil-list-before.txt"
diskutil apfs list >"$backup_dir/diskutil-apfs-before.txt"
cp "$scratch/gpt-before.txt" "$backup_dir/gpt-before.txt"
for device in "${whole_disk}s1" "$root_store" "$adjacent_lvm" \
  "$windows_partition" "$ubuntu_boot" "$tail_lvm"; do
  diskutil info "$device" \
    >"$backup_dir/diskutil-info-${device}.txt"
done
cp "$scratch/"*-signature.txt "$backup_dir/"
cp "$scratch/"*-lvm-strings.txt "$backup_dir/"
cp -p "${BASH_SOURCE[0]}" "$backup_dir/script-used.sh"

disk_blocks=$((whole_size / 512))
secondary_gpt_start=$((disk_blocks - 33))
dd if="/dev/r$whole_disk" of="$backup_dir/gpt-primary-34-sectors.bin" \
  bs=512 count=34 2>>"$operation_log"
dd if="/dev/r$whole_disk" of="$backup_dir/gpt-secondary-33-sectors.bin" \
  bs=512 skip="$secondary_gpt_start" count=33 2>>"$operation_log"
for device in "$adjacent_lvm" "$ubuntu_boot" "$tail_lvm"; do
  dd if="/dev/r$device" of="$backup_dir/${device}-first-4MiB.bin" \
    bs=1048576 count=4 2>>"$operation_log"
done
shasum -a 256 "$backup_dir/"*.bin >"$backup_dir/metadata-sha256.txt"

cat >"$backup_dir/plan.txt" <<EOF
Current root:             $root_store
Current APFS container:   $root_container
EFI UUID recorded:        $efi_uuid
Windows UUID recorded:    $windows_uuid
Ubuntu members to erase:  $adjacent_lvm $ubuntu_boot $tail_lvm
macOS growth available:   $(gb "$adjacent_size")
tail left free:           $(gb "$((ubuntu_boot_size + tail_size))")
EOF

[[ -r /dev/tty && -w /dev/tty ]] ||
  die "apply mode requires an interactive terminal"
printf '\nType exactly %s to continue: ' "$expected_confirmation" >/dev/tty
IFS= read -r typed_confirmation </dev/tty
printf '\n' >/dev/tty
[[ $typed_confirmation == "$expected_confirmation" ]] ||
  die "interactive confirmation did not match; no partition was removed"

destructive_started=1
printf '== Remove adjacent Ubuntu LVM member ==\n' | tee -a "$operation_log"
run_logged diskutil eraseVolume free free "$adjacent_lvm"
assert_uuid_absent "$adjacent_uuid"
windows_partition=$(resolve_uuid "$windows_uuid")
expect_partition "$windows_partition" "Microsoft Basic Data" \
  "$windows_size" "$windows_offset"

printf '== Grow current macOS APFS container ==\n' | tee -a "$operation_log"
run_logged diskutil apfs resizeContainer "$root_container" 0
root_store=$(resolve_uuid "$root_store_uuid")
new_root_size=$(plist_value "$root_store" Size)
minimum_expected_size=$((root_size + adjacent_size - 16777216))
maximum_expected_size=$((root_size + adjacent_size + 16777216))
[[ $new_root_size -ge $minimum_expected_size &&
  $new_root_size -le $maximum_expected_size ]] ||
  die "macOS APFS grew to an unexpected size: $new_root_size"
windows_partition=$(resolve_uuid "$windows_uuid")
resolve_uuid "$efi_uuid" >/dev/null

printf '== Remove remaining Ubuntu LVM and boot members ==\n' |
  tee -a "$operation_log"
tail_lvm=$(resolve_uuid "$tail_uuid")
expect_partition "$tail_lvm" "Linux Filesystem" "$tail_size" "$tail_offset"
run_logged diskutil eraseVolume free free "$tail_lvm"
assert_uuid_absent "$tail_uuid"
ubuntu_boot=$(resolve_uuid "$ubuntu_boot_uuid")
expect_partition "$ubuntu_boot" "Linux Filesystem" \
  "$ubuntu_boot_size" "$ubuntu_boot_offset"
run_logged diskutil eraseVolume free free "$ubuntu_boot"
assert_uuid_absent "$ubuntu_boot_uuid"

windows_partition=$(resolve_uuid "$windows_uuid")
resolve_uuid "$efi_uuid" >/dev/null
current_root_store=$(
  diskutil info -plist / |
    plutil -extract APFSPhysicalStores.0.APFSPhysicalStore raw -o - -
)
expect_value "$current_root_store" DiskUUID "$root_store_uuid"

diskutil list "$whole_disk" >"$backup_dir/diskutil-list-after.txt"
diskutil apfs list >"$backup_dir/diskutil-apfs-after.txt"
gpt -r show "/dev/$whole_disk" >"$backup_dir/gpt-after.txt"
new_root_free=$(plist_value / APFSContainerFree)
{
  printf 'COMPLETED=yes\n'
  printf 'MACOS_APFS_STORE=%s\n' "$root_store"
  printf 'MACOS_APFS_SIZE_BEFORE=%s\n' "$root_size"
  printf 'MACOS_APFS_SIZE_AFTER=%s\n' "$new_root_size"
  printf 'MACOS_APFS_FREE_AFTER=%s\n' "$new_root_free"
  printf 'TAIL_SPACE_POLICY=left-free-behind-Windows\n'
} | tee "$backup_dir/result.txt"

sync
destructive_started=0
printf '\nUbuntu was removed and macOS reclaimed %s.\n' \
  "$(gb "$adjacent_size")"
printf 'The trailing %s remains intentionally unallocated.\n' \
  "$(gb "$((ubuntu_boot_size + tail_size))")"
printf 'Backup and operation record: %s\n' "$backup_dir"
