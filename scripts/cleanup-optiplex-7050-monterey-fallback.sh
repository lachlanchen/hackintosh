#!/bin/bash

set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly CONFIRMATION="CLEAN-7050-MONTEREY-FALLBACK"
mode="${1:-audit}"
shift || true
target=""
fallback_user=""
confirmation=""

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  cleanup-optiplex-7050-monterey-fallback.sh audit \
    --volume '/Volumes/<Monterey Data>' --user <account>

  sudo cleanup-optiplex-7050-monterey-fallback.sh apply \
    --volume '/Volumes/<Monterey Data>' --user <account> \
    --confirm CLEAN-7050-MONTEREY-FALLBACK

The apply mode removes only reviewed fallback-volume leftovers. It preserves
the Monterey volume group, account, SSH/UU state, applications, and projects.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volume)
      [ "$#" -ge 2 ] || fail "--volume requires a path"
      target="$2"
      shift 2
      ;;
    --user)
      [ "$#" -ge 2 ] || fail "--user requires an account name"
      fallback_user="$2"
      shift 2
      ;;
    --confirm)
      [ "$#" -ge 2 ] || fail "--confirm requires a value"
      confirmation="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$mode" in
  audit|apply) ;;
  *) fail "mode must be audit or apply" ;;
esac
[ "$(uname -s)" = Darwin ] || fail "run this script from macOS"
[ -n "$target" ] || fail "--volume is required"
[ -n "$fallback_user" ] || fail "--user is required"
case "$target" in
  /Volumes/*) ;;
  *) fail "the fallback Data volume must be mounted below /Volumes" ;;
esac
[ -d "$target" ] || fail "fallback Data volume is not mounted: $target"
[ -d "$target/Users/$fallback_user" ] ||
  fail "the expected fallback account is absent"

current_version=$(sw_vers -productVersion)
case "$current_version" in
  15.*) ;;
  *) fail "apply only while the reviewed Sequoia system is active" ;;
esac

target_device=$(df "$target" | awk 'NR == 2 { sub("/dev/", "", $1); print $1 }')
active_device=$(df /System/Volumes/Data | awk 'NR == 2 { sub("/dev/", "", $1); print $1 }')
[ -n "$target_device" ] || fail "could not resolve the fallback device"
[ "$target_device" != "$active_device" ] || fail "refusing to clean the active Data volume"
diskutil info "$target_device" | grep -q 'File System Personality:.*APFS' ||
  fail "fallback Data volume is not APFS"
diskutil apfs list | awk -v device="$target_device" '
  index($0, "APFS Volume Disk (Role):") &&
  index($0, device " (Data)") { found = 1 }
  END { exit !found }
' || fail "the selected APFS volume does not have the Data role"

installer="$target/Applications/Install macOS Sequoia.app"
old_home="$target/Users/$fallback_user"
before_kb=$(df -k /System/Volumes/Data | awk 'NR == 2 { print $4 + 0 }')

print_size() {
  local path="$1"

  [ -e "$path" ] || return 0
  du -x -s -h "$path" 2>/dev/null || printf 'unreadable\t%s\n' "$path"
}

printf 'Active macOS: %s\n' "$current_version"
printf 'Active Data device: %s\n' "$active_device"
printf 'Fallback Data device: %s\n' "$target_device"
printf '\nReviewed cleanup targets:\n'
print_size "$installer"
print_size "$target/Previous Content"
print_size "$target/.DocumentRevisions-V100-bad-1"
print_size "$target/private/var/vm"
print_size "$target/Library/Caches"
print_size "$old_home/Library/Caches"
print_size "$old_home/.Trash"

if [ "$mode" = audit ]; then
  exit 0
fi

[ "$(id -u)" -eq 0 ] || fail "apply must run as root"
[ "$confirmation" = "$CONFIRMATION" ] ||
  fail "apply requires literal confirmation $CONFIRMATION"

remove_tree() {
  local path="$1"

  [ -e "$path" ] || return 0
  case "$path" in
    "$target"/*) ;;
    *) fail "internal path guard rejected cleanup target" ;;
  esac
  chflags -R nouchg,noschg "$path" 2>/dev/null || true
  rm -rf -- "$path"
  printf 'Removed %s\n' "$path"
}

if [ -d "$installer" ]; then
  installer_id=$(defaults read "$installer/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  [ "$installer_id" = com.apple.InstallAssistant.macOSSequoia ] ||
    fail "refusing unexpected installer bundle: ${installer_id:-unknown}"
  remove_tree "$installer"
fi

remove_tree "$target/Previous Content"
remove_tree "$target/.DocumentRevisions-V100-bad-1"
remove_tree "$target/private/var/vm/sleepimage"
for path in "$target/private/var/vm"/swapfile*; do
  [ -e "$path" ] || continue
  remove_tree "$path"
done

for path in \
  "$target/Library/Caches" \
  "$old_home/Library/Caches" \
  "$old_home/.Trash"; do
  [ -d "$path" ] || continue
  find "$path" -mindepth 1 -depth -delete 2>/dev/null || true
done

sync
after_kb=$(df -k /System/Volumes/Data | awk 'NR == 2 { print $4 + 0 }')
printf 'Reclaimed approximately %d MiB.\n' "$(((after_kb - before_kb) / 1024))"
printf 'An offline Recovery First Aid pass is still required for the fallback Data volume.\n'
