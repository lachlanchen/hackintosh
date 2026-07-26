#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

usage() {
  cat >&2 <<'EOF'
usage:
  verify-macos-installer.sh \
    "/Applications/Install macOS <Name>.app" EXPECTED_OS_VERSION EXPECTED_BUILD

Read-only verification of a modern full macOS installer. The script:

  - identifies the InstallAssistant wrapper;
  - reports, but does not require, whole-app legacy resource verification;
  - strictly verifies the critical InstallAssistant and startosinstall binaries;
  - verifies and hashes SharedSupport.dmg;
  - mounts SharedSupport.dmg read-only;
  - requires matching OSVersion and Build MobileAsset metadata;
  - prints the actual startosinstall usage.

It does not open the GUI, prepare an installation, change startup state, or
reboot.
EOF
  exit 64
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 3 ]] || usage

app=$1
expected_version=$2
expected_build=$3
dmg="$app/Contents/SharedSupport/SharedSupport.dmg"
install_assistant="$app/Contents/MacOS/InstallAssistant"
startosinstall="$app/Contents/Resources/startosinstall"

[[ $(uname -s) == Darwin ]] || die "this verifier must run on macOS"
[[ -d $app ]] || die "installer app does not exist: $app"
[[ -f $dmg ]] || die "SharedSupport.dmg does not exist: $dmg"
[[ -f $install_assistant ]] ||
  die "InstallAssistant executable does not exist"
[[ -f $startosinstall ]] || die "startosinstall does not exist"

mount_dir=
mounted=0

cleanup() {
  status=$?
  trap - EXIT
  if [[ $mounted -eq 1 && -n $mount_dir ]]; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  if [[ -n $mount_dir && -d $mount_dir ]]; then
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '== Installer wrapper ==\n'
printf 'Path: %s\n' "$app"
du -sh "$app"
printf 'Identifier: '
defaults read "$app/Contents/Info.plist" CFBundleIdentifier
printf 'Wrapper version: '
defaults read "$app/Contents/Info.plist" CFBundleShortVersionString
printf 'Wrapper build: '
defaults read "$app/Contents/Info.plist" CFBundleVersion

printf '\n== Outer resource envelope ==\n'
if codesign --verify --deep --strict --verbose=2 "$app"; then
  printf 'Outer strict verification: passed\n'
else
  printf 'Outer strict verification: not accepted; inspect the message above\n'
  printf 'This does not override the required payload and binary checks below.\n'
fi
codesign -dvvv "$app" 2>&1 |
  grep -E 'Identifier=|Authority=|TeamIdentifier=|CDHash=|Signature=' ||
  true

printf '\n== Critical Apple executables ==\n'
for executable in "$install_assistant" "$startosinstall"; do
  printf '%s\n' "$executable"
  codesign --verify --strict --verbose=2 "$executable"
  codesign -dvvv "$executable" 2>&1 |
    grep -E 'Identifier=|Authority=|TeamIdentifier=|CDHash=|Signature='
done

printf '\n== SharedSupport disk image ==\n'
stat -f 'Bytes: %z' "$dmg"
hdiutil verify "$dmg"
dmg_sha256=$(shasum -a 256 "$dmg" | awk '{print $1}')
printf 'SHA256: %s\n' "$dmg_sha256"

mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/macos-installer-verify.XXXXXX")
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
mounted=1

asset_dir="$mount_dir/com_apple_MobileAsset_MacSoftwareUpdate"
[[ -d $asset_dir ]] || die "MobileAsset metadata directory is missing"

metadata_match=
for metadata in "$asset_dir"/*.json; do
  [[ -f $metadata ]] || continue
  if grep -Fq "\"OSVersion\": \"$expected_version\"" "$metadata" &&
    grep -Fq "\"Build\": \"$expected_build\"" "$metadata"; then
    metadata_match=$metadata
    break
  fi
done

[[ -n $metadata_match ]] ||
  die "no MobileAsset matches OS $expected_version build $expected_build"

printf '\n== Target metadata ==\n'
printf 'Metadata: %s\n' "${metadata_match#"$mount_dir"/}"
grep -E \
  '"(OSVersion|Build|RestoreVersion|InstallationSize|MinimumSystemPartition)"' \
  "$metadata_match" |
  head -n 20
printf 'Expected target: %s (%s)\n' "$expected_version" "$expected_build"

printf '\n== startosinstall usage ==\n'
"$startosinstall" --usage 2>&1

printf '\nVERIFIED_OS_VERSION=%s\n' "$expected_version"
printf 'VERIFIED_BUILD=%s\n' "$expected_build"
printf 'SHARED_SUPPORT_SHA256=%s\n' "$dmg_sha256"
