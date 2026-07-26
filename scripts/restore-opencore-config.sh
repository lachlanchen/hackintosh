#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

usage() {
  cat >&2 <<'EOF'
usage:
  sudo restore-opencore-config.sh \
    EFI_DEVICE EXPECTED_LIVE_SHA256 EXPECTED_BACKUP_SHA256 \
    BACKUP_NAME PRESERVED_USED_NAME

Safely restore a known-good OpenCore config on macOS. The script:

  - refuses unexpected live and backup hashes;
  - stages and verifies the backup under a temporary name;
  - preserves the current live config as PRESERVED_USED_NAME;
  - rolls back if restore or final hash verification fails.

BACKUP_NAME must already exist. PRESERVED_USED_NAME must be an unused leaf
filename in EFI/OC. Pass hashes as 64 hexadecimal SHA-256 strings.
EOF
  exit 64
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

normalize_hash() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_hash() {
  case $1 in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  [[ ${#1} -eq 64 ]]
}

validate_leaf_name() {
  case $1 in
    ''|.|..|*/*|config.plist) return 1 ;;
  esac
}

[[ $# -eq 5 ]] || usage

efi_device=$1
expected_live=$(normalize_hash "$2")
expected_backup=$(normalize_hash "$3")
backup_name=$4
used_name=$5

validate_hash "$expected_live" || die "invalid expected live SHA-256"
validate_hash "$expected_backup" || die "invalid expected backup SHA-256"
validate_leaf_name "$backup_name" || die "invalid backup leaf name"
validate_leaf_name "$used_name" || die "invalid preserved-used leaf name"
[[ $backup_name != "$used_name" ]] ||
  die "backup and preserved-used names must differ"

mounted_here=0
temporary_config=

cleanup() {
  status=$?
  trap - EXIT
  if [[ -n $temporary_config && -e $temporary_config ]]; then
    rm -f "$temporary_config"
  fi
  if [[ $mounted_here -eq 1 ]]; then
    diskutil unmount "$efi_device" >/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

diskutil info "$efi_device" >/dev/null 2>&1 ||
  die "EFI device was not found: $efi_device"

mounted=$(
  diskutil info -plist "$efi_device" |
    plutil -extract Mounted raw -o - - 2>/dev/null ||
    printf 'false'
)
if [[ $mounted != true ]]; then
  diskutil mount "$efi_device" >/dev/null
  mounted_here=1
fi

efi_mount=$(
  diskutil info -plist "$efi_device" |
    plutil -extract MountPoint raw -o - -
)
[[ -n $efi_mount && -d $efi_mount ]] ||
  die "could not resolve the EFI mount point"

oc_root="$efi_mount/EFI/OC"
live_config="$oc_root/config.plist"
backup_config="$oc_root/$backup_name"
used_config="$oc_root/$used_name"
temporary_config="$oc_root/.config-restore-$$.tmp"

[[ -d $oc_root ]] || die "OpenCore directory was not found: $oc_root"
[[ -f $oc_root/OpenCore.efi ]] ||
  die "OpenCore.efi was not found beside the target config"
[[ -f $live_config ]] || die "live config was not found: $live_config"
[[ -f $backup_config ]] || die "backup config was not found: $backup_config"
[[ ! -e $temporary_config ]] ||
  die "unexpected temporary path already exists: $temporary_config"
[[ ! -e $used_config ]] ||
  die "preserved-used path already exists: $used_config"

actual_live=$(sha256 "$live_config")
actual_backup=$(sha256 "$backup_config")
[[ $actual_live == "$expected_live" ]] ||
  die "live config hash mismatch: $actual_live"
[[ $actual_backup == "$expected_backup" ]] ||
  die "backup config hash mismatch: $actual_backup"

cp -p "$backup_config" "$temporary_config"
[[ $(sha256 "$temporary_config") == "$expected_backup" ]] ||
  die "staged restore hash mismatch"

mv "$live_config" "$used_config"
if ! mv "$temporary_config" "$live_config"; then
  mv "$used_config" "$live_config"
  die "restore failed; prior live config was put back"
fi
temporary_config=

actual_restored=$(sha256 "$live_config")
if [[ $actual_restored != "$expected_backup" ]]; then
  failed_config="$oc_root/.config-failed-restore-$$.tmp"
  mv "$live_config" "$failed_config"
  mv "$used_config" "$live_config"
  rm -f "$failed_config"
  die "restored hash mismatch; prior live config was put back"
fi

sync
printf 'EFI_DEVICE=%s\n' "$efi_device"
printf 'LIVE_BEFORE_SHA256=%s\n' "$actual_live"
printf 'BACKUP_SHA256=%s\n' "$actual_backup"
printf 'LIVE_AFTER_SHA256=%s\n' "$actual_restored"
printf 'PRESERVED_USED_NAME=%s\n' "$used_name"
