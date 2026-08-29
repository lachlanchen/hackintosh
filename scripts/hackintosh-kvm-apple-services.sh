#!/usr/bin/env bash

# Build one stable, private OpenCore identity for Apple services. Identity
# values and generated EFI images remain in the private SATA runtime.

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_FILE=${HACKINTOSH_KVM_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hackintosh-kvm/config.env}
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RUNTIME_ROOT=${RUNTIME_ROOT:-$HOME/VirtualMachines/Hackintosh-KVM}
UPSTREAM_DIR=${UPSTREAM_DIR:-$RUNTIME_ROOT/upstream/OSX-KVM}
DISK_IMAGE=${DISK_IMAGE:-$RUNTIME_ROOT/disks/macOS-Sequoia.qcow2}
STATE_DIR=$RUNTIME_ROOT/state
APPLE_DIR=$STATE_DIR/apple-services
BACKUP_DIR=$APPLE_DIR/original
PRIVATE_CONFIG=$APPLE_DIR/config.plist
MANIFEST=$APPLE_DIR/manifest.txt
DISABLED_MARKER=$APPLE_DIR/disabled
SOURCE_CONFIG=$UPSTREAM_DIR/OpenCore/config.plist
SOURCE_OPENCORE=$UPSTREAM_DIR/OpenCore/OpenCore.qcow2
PRIVATE_OPENCORE=$STATE_DIR/OpenCore-private.qcow2
NETWORK_MAC_FILE=$STATE_DIR/network-mac
MACHINE_UUID_FILE=$STATE_DIR/machine-uuid
OVMF_VARS_FILE=$STATE_DIR/OVMF_VARS.fd
QEMU_PID_FILE=$STATE_DIR/qemu.pid

OPENCORE_VERSION=1.0.7
OPENCORE_ARCHIVE_SHA256=2ffab6ebf58c7aefb0bcb3a1a385d207746823d6dd87d44bd666e1286939943e
TOOLS_DIR=$RUNTIME_ROOT/tools/OpenCore-$OPENCORE_VERSION
OPENCORE_ARCHIVE=$TOOLS_DIR/OpenCore-$OPENCORE_VERSION-RELEASE.zip
MACSERIAL=$TOOLS_DIR/bin/macserial.linux
OCVALIDATE=$TOOLS_DIR/bin/ocvalidate.linux
MTOOLS_ROOT=$RUNTIME_ROOT/tools/mtools
PRIVATE_MCOPY=$MTOOLS_ROOT/usr/bin/mcopy
NETWORK_DEVICE_PATH='PciRoot(0x0)/Pci(0x4,0x0)'
MODEL=iMac19,1

say() {
  printf '[hackintosh-kvm-apple-services] %s\n' "$*"
}

die() {
  printf '[hackintosh-kvm-apple-services] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

qemu_is_running() {
  local pid
  [[ -s "$QEMU_PID_FILE" ]] || return 1
  pid=$(tr -d '[:space:]' <"$QEMU_PID_FILE")
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  tr '\0' '\n' <"/proc/$pid/cmdline" | grep -Fq -- "$DISK_IMAGE"
}

ensure_opencore_tools() {
  local actual partial
  require_command curl
  require_command unzip
  mkdir -p "$TOOLS_DIR/bin"
  chmod 700 "$RUNTIME_ROOT/tools" "$TOOLS_DIR" "$TOOLS_DIR/bin"
  if [[ ! -s "$OPENCORE_ARCHIVE" ]]; then
    partial=$OPENCORE_ARCHIVE.partial.$$
    curl --fail --location --retry 3 \
      --output "$partial" \
      "https://github.com/acidanthera/OpenCorePkg/releases/download/$OPENCORE_VERSION/OpenCore-$OPENCORE_VERSION-RELEASE.zip"
    actual=$(sha256_of "$partial")
    [[ "$actual" == "$OPENCORE_ARCHIVE_SHA256" ]] || die "OpenCore release archive checksum mismatch"
    chmod 600 "$partial"
    mv "$partial" "$OPENCORE_ARCHIVE"
  fi
  actual=$(sha256_of "$OPENCORE_ARCHIVE")
  [[ "$actual" == "$OPENCORE_ARCHIVE_SHA256" ]] || die "cached OpenCore release archive checksum mismatch"
  if [[ ! -x "$MACSERIAL" || ! -x "$OCVALIDATE" ]]; then
    unzip -jo "$OPENCORE_ARCHIVE" \
      'Utilities/macserial/macserial.linux' \
      'Utilities/ocvalidate/ocvalidate.linux' \
      -d "$TOOLS_DIR/bin" >/dev/null
    chmod 700 "$MACSERIAL" "$OCVALIDATE"
  fi
}

ensure_mcopy() {
  local apt_work package partial_root
  if command -v mcopy >/dev/null 2>&1; then
    command -v mcopy
    return 0
  fi
  if [[ -x "$PRIVATE_MCOPY" ]]; then
    printf '%s\n' "$PRIVATE_MCOPY"
    return 0
  fi
  require_command apt-get
  require_command dpkg-deb
  apt_work=$(mktemp -d "$RUNTIME_ROOT/tools/mtools-download.XXXXXX")
  partial_root=$MTOOLS_ROOT.partial.$$
  mkdir -p "$partial_root"
  (
    cd "$apt_work"
    apt-get download mtools >/dev/null
  )
  package=$(find "$apt_work" -maxdepth 1 -type f -name 'mtools_*.deb' -print -quit)
  [[ -n "$package" ]] || die "could not download the Ubuntu mtools package"
  dpkg-deb -x "$package" "$partial_root"
  [[ -x "$partial_root/usr/bin/mcopy" ]] || die "downloaded mtools package lacks mcopy"
  chmod -R go-rwx "$partial_root"
  mv "$partial_root" "$MTOOLS_ROOT"
  rm -r -- "$apt_work"
  printf '%s\n' "$PRIVATE_MCOPY"
}

backup_once() {
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$APPLE_DIR" "$BACKUP_DIR"
  [[ -f "$BACKUP_DIR/network-mac.before" ]] || \
    install -m 0600 "$NETWORK_MAC_FILE" "$BACKUP_DIR/network-mac.before"
  [[ -f "$BACKUP_DIR/machine-uuid.before" ]] || \
    install -m 0600 "$MACHINE_UUID_FILE" "$BACKUP_DIR/machine-uuid.before"
  if [[ -f "$OVMF_VARS_FILE" && ! -f "$BACKUP_DIR/OVMF_VARS.before.fd" ]]; then
    install -m 0600 "$OVMF_VARS_FILE" "$BACKUP_DIR/OVMF_VARS.before.fd"
  fi
}

validate_private_artifacts() {
  local expected actual
  [[ -s "$PRIVATE_CONFIG" && -s "$PRIVATE_OPENCORE" && -s "$MANIFEST" ]] || return 1
  expected=$(sed -n 's/^private_opencore_sha256=//p' "$MANIFEST" | head -n 1)
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual=$(sha256_of "$PRIVATE_OPENCORE")
  [[ "$actual" == "$expected" ]] || return 1
  "$OCVALIDATE" "$PRIVATE_CONFIG" >/dev/null || return 1
  python3 - "$PRIVATE_CONFIG" "$NETWORK_DEVICE_PATH" <<'PY'
import plistlib
import sys

config_path, network_path = sys.argv[1:]
with open(config_path, "rb") as handle:
    config = plistlib.load(handle)
generic = config["PlatformInfo"]["Generic"]
assert generic["SystemProductName"] == "iMac19,1"
assert generic["SystemSerialNumber"] != "W00000000001"
assert generic["MLB"] != "M0000000000000001"
assert generic["SystemUUID"] != "00000000-0000-0000-0000-000000000000"
assert isinstance(generic["ROM"], bytes) and len(generic["ROM"]) == 6
assert config["DeviceProperties"]["Add"][network_path]["built-in"] == b"\x01"
PY
}

validate_private_state() {
  validate_private_artifacts || return 1
  python3 - "$PRIVATE_CONFIG" "$NETWORK_MAC_FILE" "$MACHINE_UUID_FILE" <<'PY'
import plistlib
import sys

config_path, mac_path, uuid_path = sys.argv[1:]
with open(config_path, "rb") as handle:
    generic = plistlib.load(handle)["PlatformInfo"]["Generic"]
mac = open(mac_path, encoding="ascii").read().strip().lower()
machine_uuid = open(uuid_path, encoding="ascii").read().strip().upper()
assert generic["SystemUUID"].upper() == machine_uuid
assert generic["ROM"] == bytes.fromhex(mac.replace(":", ""))
PY
}

restore_identity_from_config() {
  local mac_partial uuid_partial
  mac_partial=$STATE_DIR/network-mac.partial.$$
  uuid_partial=$STATE_DIR/machine-uuid.partial.$$
  python3 - "$PRIVATE_CONFIG" "$mac_partial" "$uuid_partial" <<'PY'
import plistlib
import sys

config_path, mac_path, uuid_path = sys.argv[1:]
with open(config_path, "rb") as handle:
    generic = plistlib.load(handle)["PlatformInfo"]["Generic"]
mac = ":".join(f"{byte:02x}" for byte in generic["ROM"])
with open(mac_path, "w", encoding="ascii") as handle:
    handle.write(mac + "\n")
with open(uuid_path, "w", encoding="ascii") as handle:
    handle.write(generic["SystemUUID"].upper() + "\n")
PY
  chmod 600 "$mac_partial" "$uuid_partial"
  mv "$mac_partial" "$NETWORK_MAC_FILE"
  mv "$uuid_partial" "$MACHINE_UUID_FILE"
}

disable_identity() {
  qemu_is_running && die "the VM is running; shut it down cleanly before selecting the rollback identity"
  ensure_opencore_tools
  validate_private_artifacts || die "private OpenCore artifacts are not valid"
  [[ -s "$BACKUP_DIR/network-mac.before" && -s "$BACKUP_DIR/machine-uuid.before" ]] || \
    die "original QEMU identity backup is incomplete"
  install -m 0600 "$BACKUP_DIR/network-mac.before" "$NETWORK_MAC_FILE"
  install -m 0600 "$BACKUP_DIR/machine-uuid.before" "$MACHINE_UUID_FILE"
  : >"$DISABLED_MARKER"
  chmod 600 "$DISABLED_MARKER"
  say "private identity disabled; the audited template will be used on the next launch"
}

enable_identity() {
  qemu_is_running && die "the VM is running; shut it down cleanly before selecting the private identity"
  ensure_opencore_tools
  validate_private_artifacts || die "private OpenCore artifacts are not valid"
  restore_identity_from_config
  [[ ! -e "$DISABLED_MARKER" ]] || unlink "$DISABLED_MARKER"
  validate_private_state || die "private identity activation validation failed"
  say "private identity enabled for the next launch"
}

prepare_identity() {
  local pair serial mlb mac machine_uuid mcopy_bin work raw first_sector offset
  local patched extracted private_partial config_partial mac_partial uuid_partial

  qemu_is_running && die "the VM is running; shut it down cleanly before changing OpenCore identity"
  require_command python3
  require_command qemu-img
  require_command sgdisk
  require_command uuidgen
  require_command sha256sum
  [[ -s "$SOURCE_CONFIG" && -s "$SOURCE_OPENCORE" ]] || die "audited OpenCore source files are missing"
  [[ -s "$NETWORK_MAC_FILE" && -s "$MACHINE_UUID_FILE" ]] || die "existing private QEMU identity is missing"

  ensure_opencore_tools
  if validate_private_artifacts; then
    [[ ! -e "$DISABLED_MARKER" ]] || \
      die "the verified private identity is disabled; run '$0 enable' to select it"
    validate_private_state || die "private identity artifacts and QEMU identity files disagree"
    say "existing private identity passed validation; refusing to rotate it"
    return 0
  fi
  [[ ! -e "$MANIFEST" && ! -e "$PRIVATE_OPENCORE" ]] || \
    die "incomplete private identity exists; preserve it and inspect manually instead of rotating values"

  mcopy_bin=$(ensure_mcopy)
  backup_once
  pair=$("$MACSERIAL" --model "$MODEL" --num 1 | head -n 1)
  serial=${pair%% | *}
  mlb=${pair##* | }
  [[ "$serial" =~ ^[A-Z0-9]{12}$ ]] || die "macserial returned an invalid serial format"
  [[ "$mlb" =~ ^[A-Z0-9]{17}$ ]] || die "macserial returned an invalid MLB format"
  printf -v mac '00:16:cb:%02x:%02x:%02x' \
    "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))" \
    "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))" \
    "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))"
  machine_uuid=$(uuidgen | tr '[:lower:]' '[:upper:]')

  work=$(mktemp -d "$APPLE_DIR/build.XXXXXX")
  raw=$work/OpenCore.raw
  patched=$work/config.plist
  extracted=$work/config.extracted.plist
  private_partial=$STATE_DIR/OpenCore-private.qcow2.partial.$$
  config_partial=$APPLE_DIR/config.plist.partial.$$
  mac_partial=$STATE_DIR/network-mac.partial.$$
  uuid_partial=$STATE_DIR/machine-uuid.partial.$$

  SERIAL="$serial" MLB="$mlb" MAC="$mac" MACHINE_UUID="$machine_uuid" \
    MODEL="$MODEL" NETWORK_DEVICE_PATH="$NETWORK_DEVICE_PATH" \
    python3 - "$SOURCE_CONFIG" "$patched" <<'PY'
import os
import plistlib
import sys

source, destination = sys.argv[1:]
with open(source, "rb") as handle:
    config = plistlib.load(handle)
generic = config["PlatformInfo"]["Generic"]
generic["SystemProductName"] = os.environ["MODEL"]
generic["SystemSerialNumber"] = os.environ["SERIAL"]
generic["MLB"] = os.environ["MLB"]
generic["SystemUUID"] = os.environ["MACHINE_UUID"]
generic["ROM"] = bytes.fromhex(os.environ["MAC"].replace(":", ""))
properties = config.setdefault("DeviceProperties", {}).setdefault("Add", {})
properties.setdefault(os.environ["NETWORK_DEVICE_PATH"], {})["built-in"] = b"\x01"
with open(destination, "wb") as handle:
    plistlib.dump(config, handle, fmt=plistlib.FMT_XML, sort_keys=False)
PY
  "$OCVALIDATE" "$patched" >/dev/null

  qemu-img convert -p -O raw "$SOURCE_OPENCORE" "$raw"
  first_sector=$(sgdisk -i 1 "$raw" | awk '/First sector:/ {print $3; exit}')
  [[ "$first_sector" =~ ^[0-9]+$ ]] || die "could not resolve the OpenCore EFI partition offset"
  offset=$((first_sector * 512))
  MTOOLS_SKIP_CHECK=1 "$mcopy_bin" -o -i "$raw@@$offset" "$patched" ::/EFI/OC/config.plist
  MTOOLS_SKIP_CHECK=1 "$mcopy_bin" -i "$raw@@$offset" ::/EFI/OC/config.plist "$extracted"
  cmp -s "$patched" "$extracted" || die "private OpenCore config round-trip verification failed"
  qemu-img convert -p -O qcow2 -o compat=1.1,lazy_refcounts=off "$raw" "$private_partial"
  qemu-img check -q "$private_partial" || die "private OpenCore qcow2 check failed"

  install -m 0600 "$patched" "$config_partial"
  printf '%s\n' "$mac" >"$mac_partial"
  printf '%s\n' "$machine_uuid" >"$uuid_partial"
  chmod 600 "$private_partial" "$mac_partial" "$uuid_partial"
  mv "$private_partial" "$PRIVATE_OPENCORE"
  mv "$config_partial" "$PRIVATE_CONFIG"
  mv "$mac_partial" "$NETWORK_MAC_FILE"
  mv "$uuid_partial" "$MACHINE_UUID_FILE"

  {
    printf 'format_version=1\n'
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'model=%s\n' "$MODEL"
    printf 'network_device_path=%s\n' "$NETWORK_DEVICE_PATH"
    printf 'source_opencore_sha256=%s\n' "$(sha256_of "$SOURCE_OPENCORE")"
    printf 'private_config_sha256=%s\n' "$(sha256_of "$PRIVATE_CONFIG")"
    printf 'private_opencore_sha256=%s\n' "$(sha256_of "$PRIVATE_OPENCORE")"
  } >"$MANIFEST"
  chmod 600 "$MANIFEST"
  [[ ! -e "$DISABLED_MARKER" ]] || die "disabled marker unexpectedly exists"
  validate_private_state || die "final private identity validation failed"
  rm -r -- "$work"
  say "private OpenCore identity created and validated"
  say "identity values remain private; repeated runs will not rotate them"
}

status() {
  ensure_opencore_tools
  if validate_private_artifacts; then
    if [[ -e "$DISABLED_MARKER" ]]; then
      say "private identity: valid but disabled"
    elif validate_private_state; then
      say "private identity: valid and selected for the next VM launch"
    else
      say "private identity: valid, but QEMU identity files do not match"
    fi
  else
    say "private identity: not prepared"
  fi
}

case ${1:-status} in
  prepare) prepare_identity ;;
  enable) enable_identity ;;
  disable|rollback) disable_identity ;;
  verify|status) status ;;
  *) die "usage: $0 [prepare|enable|disable|rollback|verify|status]" ;;
esac
