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
DEVICECHECK_BACKUP_DIR=$APPLE_DIR/pre-sequoia-devicecheck
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
DEVICECHECK_MIN_KERNEL=24.0.0
DEVICECHECK_MAX_KERNEL=24.99.99

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

inject_devicecheck_patches() {
  local config_path=$1
  python3 - "$config_path" "$DEVICECHECK_MIN_KERNEL" "$DEVICECHECK_MAX_KERNEL" <<'PY'
import plistlib
import sys

config_path, min_kernel, max_kernel = sys.argv[1:]
# Audited against lucid-fabrics/osx-proxmox-next v0.31.2 at commit
# 0f5a16ad1e294f6d4c0c67e976be323fd3a13eb5. These are two
# length-preserving cstring swaps, not arbitrary binary replacements. Keeping
# both entries together prevents duplicate hv_vmm_present names in the kernel.
definitions = (
    (
        "Apple ID VM bypass - hide real hv_vmm_present",
        "626f6f742073657373696f6e20555549440068765f766d6d5f70726573656e7400",
        "626f6f742073657373696f6e20555549440068696265726e617465636f756e7400",
    ),
    (
        "Apple ID VM bypass - route hv_vmm_present to hibernatecount",
        "68696265726e61746568696472656164790068696265726e617465636f756e7400",
        "68696265726e61746568696472656164790068765f766d6d5f70726573656e7400",
    ),
)
with open(config_path, "rb") as handle:
    config = plistlib.load(handle)
patches = config.setdefault("Kernel", {}).setdefault("Patch", [])
finds = {bytes.fromhex(find_hex) for _, find_hex, _ in definitions}
patches[:] = [entry for entry in patches if entry.get("Find") not in finds]
for comment, find_hex, replace_hex in definitions:
    find = bytes.fromhex(find_hex)
    replace = bytes.fromhex(replace_hex)
    assert len(find) == len(replace)
    patches.append({
        "Arch": "x86_64",
        "Base": "",
        "Comment": comment,
        "Count": 1,
        "Enabled": True,
        "Find": find,
        "Identifier": "kernel",
        "Limit": 0,
        "Mask": b"",
        "MaxKernel": max_kernel,
        "MinKernel": min_kernel,
        "Replace": replace,
        "ReplaceMask": b"",
        "Skip": 0,
    })
with open(config_path, "wb") as handle:
    plistlib.dump(config, handle, fmt=plistlib.FMT_XML, sort_keys=False)
PY
}

build_private_opencore() {
  local config_path=$1 output_path=$2 work=$3 mcopy_bin=$4
  local raw extracted first_sector offset
  raw=$work/OpenCore.raw
  extracted=$work/config.extracted.plist
  qemu-img convert -p -O raw "$SOURCE_OPENCORE" "$raw"
  first_sector=$(sgdisk -i 1 "$raw" | awk '/First sector:/ {print $3; exit}')
  [[ "$first_sector" =~ ^[0-9]+$ ]] || die "could not resolve the OpenCore EFI partition offset"
  offset=$((first_sector * 512))
  MTOOLS_SKIP_CHECK=1 "$mcopy_bin" -o -i "$raw@@$offset" "$config_path" ::/EFI/OC/config.plist
  MTOOLS_SKIP_CHECK=1 "$mcopy_bin" -i "$raw@@$offset" ::/EFI/OC/config.plist "$extracted"
  cmp -s "$config_path" "$extracted" || die "private OpenCore config round-trip verification failed"
  qemu-img convert -p -O qcow2 -o compat=1.1,lazy_refcounts=off "$raw" "$output_path"
  qemu-img check -q "$output_path" || die "private OpenCore qcow2 check failed"
}

write_private_manifest() {
  local destination=$1 created_utc=${2:-}
  local config_path=${3:-$PRIVATE_CONFIG} opencore_path=${4:-$PRIVATE_OPENCORE}
  [[ -n "$created_utc" ]] || created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    printf 'format_version=2\n'
    printf 'created_utc=%s\n' "$created_utc"
    printf 'updated_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'model=%s\n' "$MODEL"
    printf 'network_device_path=%s\n' "$NETWORK_DEVICE_PATH"
    printf 'devicecheck_min_kernel=%s\n' "$DEVICECHECK_MIN_KERNEL"
    printf 'devicecheck_max_kernel=%s\n' "$DEVICECHECK_MAX_KERNEL"
    printf 'source_opencore_sha256=%s\n' "$(sha256_of "$SOURCE_OPENCORE")"
    printf 'private_config_sha256=%s\n' "$(sha256_of "$config_path")"
    printf 'private_opencore_sha256=%s\n' "$(sha256_of "$opencore_path")"
  } >"$destination"
  chmod 600 "$destination"
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
  expected=$(sed -n 's/^private_config_sha256=//p' "$MANIFEST" | head -n 1)
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual=$(sha256_of "$PRIVATE_CONFIG")
  [[ "$actual" == "$expected" ]] || return 1
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

validate_devicecheck_support() {
  [[ -s "$PRIVATE_CONFIG" ]] || return 1
  python3 - "$PRIVATE_CONFIG" "$DEVICECHECK_MIN_KERNEL" "$DEVICECHECK_MAX_KERNEL" <<'PY'
import plistlib
import sys

config_path, min_kernel, max_kernel = sys.argv[1:]
expected = (
    (
        "Apple ID VM bypass - hide real hv_vmm_present",
        bytes.fromhex("626f6f742073657373696f6e20555549440068765f766d6d5f70726573656e7400"),
        bytes.fromhex("626f6f742073657373696f6e20555549440068696265726e617465636f756e7400"),
    ),
    (
        "Apple ID VM bypass - route hv_vmm_present to hibernatecount",
        bytes.fromhex("68696265726e61746568696472656164790068696265726e617465636f756e7400"),
        bytes.fromhex("68696265726e61746568696472656164790068765f766d6d5f70726573656e7400"),
    ),
)
with open(config_path, "rb") as handle:
    patches = plistlib.load(handle).get("Kernel", {}).get("Patch", [])

def require(condition):
    if not condition:
        raise SystemExit(1)

for comment, find, replace in expected:
    matches = [entry for entry in patches if entry.get("Find") == find]
    require(len(matches) == 1)
    entry = matches[0]
    require(entry.get("Comment") == comment)
    require(entry.get("Replace") == replace)
    require(len(find) == len(replace))
    require(entry.get("Enabled") is True)
    require(entry.get("Arch") == "x86_64")
    require(entry.get("Identifier") == "kernel")
    require(entry.get("Count") == 1)
    require(entry.get("MinKernel") == min_kernel)
    require(entry.get("MaxKernel") == max_kernel)
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
  validate_devicecheck_support || \
    die "Sequoia DeviceCheck support is missing; run '$0 refresh' while the VM is stopped"
  restore_identity_from_config
  [[ ! -e "$DISABLED_MARKER" ]] || unlink "$DISABLED_MARKER"
  validate_private_state || die "private identity activation validation failed"
  say "private identity enabled for the next launch"
}

refresh_devicecheck_support() {
  local mcopy_bin work patched rebuilt staged_manifest created_utc

  qemu_is_running && die "the VM is running; shut it down cleanly before refreshing private OpenCore"
  require_command python3
  require_command qemu-img
  require_command sgdisk
  require_command sha256sum
  [[ -s "$SOURCE_OPENCORE" ]] || die "audited OpenCore source image is missing"
  ensure_opencore_tools
  validate_private_artifacts || die "private identity artifacts are not valid"
  validate_private_state || die "private identity and QEMU identity files disagree"
  if validate_devicecheck_support; then
    say "Sequoia DeviceCheck support is already present; refusing to rewrite it"
    return 0
  fi

  mcopy_bin=$(ensure_mcopy)
  mkdir -p "$DEVICECHECK_BACKUP_DIR"
  chmod 700 "$DEVICECHECK_BACKUP_DIR"
  [[ -f "$DEVICECHECK_BACKUP_DIR/config.before-devicecheck.plist" ]] || \
    install -m 0600 "$PRIVATE_CONFIG" "$DEVICECHECK_BACKUP_DIR/config.before-devicecheck.plist"
  [[ -f "$DEVICECHECK_BACKUP_DIR/OpenCore-private.before-devicecheck.qcow2" ]] || \
    install -m 0600 "$PRIVATE_OPENCORE" "$DEVICECHECK_BACKUP_DIR/OpenCore-private.before-devicecheck.qcow2"
  [[ -f "$DEVICECHECK_BACKUP_DIR/manifest.before-devicecheck.txt" ]] || \
    install -m 0600 "$MANIFEST" "$DEVICECHECK_BACKUP_DIR/manifest.before-devicecheck.txt"

  work=$(mktemp -d "$APPLE_DIR/devicecheck-build.XXXXXX")
  patched=$work/config.plist
  rebuilt=$work/OpenCore-private.qcow2
  staged_manifest=$work/manifest.txt
  install -m 0600 "$PRIVATE_CONFIG" "$patched"
  inject_devicecheck_patches "$patched"
  "$OCVALIDATE" "$patched" >/dev/null
  build_private_opencore "$patched" "$rebuilt" "$work" "$mcopy_bin"
  created_utc=$(sed -n 's/^created_utc=//p' "$MANIFEST" | head -n 1)
  write_private_manifest "$staged_manifest" "$created_utc" "$patched" "$rebuilt"
  chmod 600 "$patched" "$rebuilt" "$staged_manifest"

  mv "$rebuilt" "$PRIVATE_OPENCORE"
  mv "$patched" "$PRIVATE_CONFIG"
  mv "$staged_manifest" "$MANIFEST"
  validate_private_state || die "refreshed private identity validation failed"
  validate_devicecheck_support || die "refreshed DeviceCheck patch validation failed"
  rm -r -- "$work"
  say "Sequoia DeviceCheck support added without rotating private identity"
}

prepare_identity() {
  local pair serial mlb mac machine_uuid mcopy_bin work
  local patched private_partial config_partial mac_partial uuid_partial

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
    if ! validate_devicecheck_support; then
      refresh_devicecheck_support
      return 0
    fi
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
  patched=$work/config.plist
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
  inject_devicecheck_patches "$patched"
  "$OCVALIDATE" "$patched" >/dev/null
  build_private_opencore "$patched" "$private_partial" "$work" "$mcopy_bin"

  install -m 0600 "$patched" "$config_partial"
  printf '%s\n' "$mac" >"$mac_partial"
  printf '%s\n' "$machine_uuid" >"$uuid_partial"
  chmod 600 "$private_partial" "$mac_partial" "$uuid_partial"
  mv "$private_partial" "$PRIVATE_OPENCORE"
  mv "$config_partial" "$PRIVATE_CONFIG"
  mv "$mac_partial" "$NETWORK_MAC_FILE"
  mv "$uuid_partial" "$MACHINE_UUID_FILE"

  write_private_manifest "$MANIFEST"
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
    elif ! validate_devicecheck_support; then
      say "private identity: valid, but Sequoia DeviceCheck support is missing"
    elif validate_private_state; then
      say "private identity: valid with Sequoia DeviceCheck support and selected for the next VM launch"
    else
      say "private identity: valid, but QEMU identity files do not match"
    fi
  else
    say "private identity: not prepared"
  fi
}

case ${1:-status} in
  prepare) prepare_identity ;;
  refresh) refresh_devicecheck_support ;;
  enable) enable_identity ;;
  disable|rollback) disable_identity ;;
  verify|status) status ;;
  *) die "usage: $0 [prepare|refresh|enable|disable|rollback|verify|status]" ;;
esac
