#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

usage() {
  cat >&2 <<'EOF'
usage:
  sudo stage-opencore-config.sh \
    EFI_DEVICE SOURCE_CONFIG EXPECTED_SOURCE_SHA256 EXPECTED_LIVE_SHA256 \
    BACKUP_NAME PRESERVED_LIVE_NAME

Safely promote a validated OpenCore config on macOS. The script:

  - mounts EFI_DEVICE only when it is not already mounted;
  - refuses an unexpected live config;
  - creates or verifies BACKUP_NAME;
  - stages and verifies SOURCE_CONFIG under a temporary name;
  - preserves the live config as PRESERVED_LIVE_NAME;
  - rolls back if promotion or final hash verification fails.

BACKUP_NAME and PRESERVED_LIVE_NAME must be unused leaf filenames in EFI/OC.
Pass hashes as 64 hexadecimal SHA-256 strings.
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

[[ $# -eq 6 ]] || usage

efi_device=$1
source_config=$2
expected_source=$(normalize_hash "$3")
expected_live=$(normalize_hash "$4")
backup_name=$5
preserved_name=$6

validate_hash "$expected_source" || die "invalid expected source SHA-256"
validate_hash "$expected_live" || die "invalid expected live SHA-256"
validate_leaf_name "$backup_name" || die "invalid backup leaf name"
validate_leaf_name "$preserved_name" || die "invalid preserved-live leaf name"
[[ $backup_name != "$preserved_name" ]] ||
  die "backup and preserved-live names must differ"
[[ -f $source_config ]] || die "source config does not exist: $source_config"
[[ $(sha256 "$source_config") == "$expected_source" ]] ||
  die "source config hash mismatch"

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
preserved_config="$oc_root/$preserved_name"
temporary_config="$oc_root/.config-stage-$$.tmp"

[[ -d $oc_root ]] || die "OpenCore directory was not found: $oc_root"
[[ -f $oc_root/OpenCore.efi ]] ||
  die "OpenCore.efi was not found beside the target config"
[[ -f $live_config ]] || die "live config was not found: $live_config"
[[ ! -e $temporary_config ]] ||
  die "unexpected temporary path already exists: $temporary_config"
[[ ! -e $preserved_config ]] ||
  die "preserved-live path already exists: $preserved_config"

actual_live=$(sha256 "$live_config")
[[ $actual_live == "$expected_live" ]] ||
  die "live config hash mismatch: $actual_live"

if [[ ! -e $backup_config ]]; then
  cp -p "$live_config" "$backup_config"
fi
[[ -f $backup_config ]] || die "backup is not a regular file"
[[ $(sha256 "$backup_config") == "$expected_live" ]] ||
  die "backup config hash mismatch"

cp -p "$source_config" "$temporary_config"
[[ $(sha256 "$temporary_config") == "$expected_source" ]] ||
  die "staged-on-EFI config hash mismatch"

mv "$live_config" "$preserved_config"
if ! mv "$temporary_config" "$live_config"; then
  mv "$preserved_config" "$live_config"
  die "promotion failed; original live config was restored"
fi
temporary_config=

actual_installed=$(sha256 "$live_config")
if [[ $actual_installed != "$expected_source" ]]; then
  failed_config="$oc_root/.config-failed-$$.tmp"
  mv "$live_config" "$failed_config"
  mv "$preserved_config" "$live_config"
  rm -f "$failed_config"
  die "installed hash mismatch; original live config was restored"
fi

sync
printf 'EFI_DEVICE=%s\n' "$efi_device"
printf 'LIVE_BEFORE_SHA256=%s\n' "$actual_live"
printf 'BACKUP_SHA256=%s\n' "$(sha256 "$backup_config")"
printf 'LIVE_AFTER_SHA256=%s\n' "$actual_installed"
printf 'PRESERVED_LIVE_NAME=%s\n' "$preserved_name"
