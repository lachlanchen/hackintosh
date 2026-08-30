#!/usr/bin/env bash

# Reproducible, private macOS/OpenCore QEMU launcher for a Linux KVM host.
# Large images, Apple software, machine state, and identifiers stay outside Git.

set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG_FILE=${HACKINTOSH_KVM_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hackintosh-kvm/config.env}

if [[ -f "$CONFIG_FILE" ]]; then
  # The private config is intentionally a shell fragment owned by this user.
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RUNTIME_ROOT=${RUNTIME_ROOT:-$HOME/VirtualMachines/Hackintosh-KVM}
STATE_DIR=$RUNTIME_ROOT/state
LOG_DIR=$RUNTIME_ROOT/logs
UPSTREAM_DIR=${UPSTREAM_DIR:-$RUNTIME_ROOT/upstream/OSX-KVM}
RECOVERY_DIR=${RECOVERY_DIR:-$RUNTIME_ROOT/installer/com.apple.recovery.boot}
DISK_IMAGE=${DISK_IMAGE:-$RUNTIME_ROOT/disks/macOS-Sequoia.qcow2}
DISK_SIZE=${DISK_SIZE:-512G}
RAM_GIB=${HACKINTOSH_KVM_RAM_GIB:-${RAM_GIB:-16}}
CPU_CORES=${HACKINTOSH_KVM_CPU_CORES:-${CPU_CORES:-4}}
CPU_THREADS=${HACKINTOSH_KVM_CPU_THREADS:-${CPU_THREADS:-2}}
VNC_DISPLAY=${VNC_DISPLAY:-41}
NOVNC_PORT=${NOVNC_PORT:-6141}
SSH_PORT=${SSH_PORT:-2224}
VNC_BIND=${VNC_BIND:-127.0.0.1}
NOVNC_BIND=${NOVNC_BIND:-127.0.0.1}
NOVNC_SYSTEM_ROOT=${NOVNC_SYSTEM_ROOT:-/usr/share/novnc}

OPENCORE_SOURCE_IMAGE=$UPSTREAM_DIR/OpenCore/OpenCore.qcow2
OPENCORE_PRIVATE_IMAGE=$STATE_DIR/OpenCore-private.qcow2
APPLE_SERVICES_DIR=$STATE_DIR/apple-services
APPLE_SERVICES_MANIFEST=$APPLE_SERVICES_DIR/manifest.txt
if [[ -z "${OPENCORE_IMAGE:-}" ]]; then
  if [[ -f "$OPENCORE_PRIVATE_IMAGE" && ! -e "$APPLE_SERVICES_DIR/disabled" ]]; then
    OPENCORE_IMAGE=$OPENCORE_PRIVATE_IMAGE
  else
    OPENCORE_IMAGE=$OPENCORE_SOURCE_IMAGE
  fi
fi

# These values pin the audited upstream checkout. They may be overridden only
# in the private config after a deliberate upstream review.
EXPECTED_UPSTREAM_COMMIT=${EXPECTED_UPSTREAM_COMMIT:-4c378a4b5e0b219783683012bec680325eb40719}
EXPECTED_OPENCORE_SHA256=${EXPECTED_OPENCORE_SHA256:-6ed36c0c2a4206ccc695f6b1a734a1cc6f94d288b0517c705d351c63cb92a6f3}
EXPECTED_OVMF_CODE_SHA256=${EXPECTED_OVMF_CODE_SHA256:-7decd7fa9965e7f943a1f79d1d05ce6d881540d625cc2a9641a57f89721b4577}
EXPECTED_OVMF_VARS_SHA256=${EXPECTED_OVMF_VARS_SHA256:-6ed987af3a3c155be71665f510eae3e007eda9b8b94afd59d45e91c4a11565cc}

BASE_DMG=$RECOVERY_DIR/BaseSystem.dmg
BASE_IMG=$RUNTIME_ROOT/installer/BaseSystem.img
OVMF_CODE=$UPSTREAM_DIR/OVMF_CODE_4M.fd
OVMF_VARS_SOURCE=$UPSTREAM_DIR/OVMF_VARS-1920x1080.fd
OVMF_VARS_PRIVATE=$STATE_DIR/OVMF_VARS.fd
MAC_FILE=$STATE_DIR/network-mac
UUID_FILE=$STATE_DIR/machine-uuid
VMGENID_FILE=$STATE_DIR/vm-generation-id
QEMU_PID_FILE=$STATE_DIR/qemu.pid
NOVNC_PID_FILE=$STATE_DIR/novnc.pid
QMP_SOCKET=$STATE_DIR/qmp.sock
VNC_PORT=$((5900 + VNC_DISPLAY))
NOVNC_WEB_ROOT=$STATE_DIR/novnc-layout-safe
NOVNC_LAYOUT_PATCH=$REPO_DIR/patches/novnc-1.3.0-layout-safe-keyboard.patch
EXPECTED_NOVNC_RFB_SHA256=${EXPECTED_NOVNC_RFB_SHA256:-331109966c80bef620bcd09242d43dbc05fa83cb44eba439ad20148f86aa479e}
NOVNC_URL="http://$NOVNC_BIND:$NOVNC_PORT/vnc.html?autoconnect=1&resize=scale&quality=6&compression=2&layoutsafe=1"

say() {
  printf '[hackintosh-kvm] %s\n' "$*"
}

warn() {
  printf '[hackintosh-kvm] warning: %s\n' "$*" >&2
}

die() {
  printf '[hackintosh-kvm] error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: hackintosh-kvm.sh COMMAND

Commands:
  fetch           Download an Apple-verified Sequoia recovery image
  prepare         Verify assets and create private sparse disk/state
  apple-services  Build a stable private OpenCore identity (VM must be stopped)
  prepare-novnc  Build the private layout-safe noVNC web root
  verify          Run read-only host and image checks
  install-service Link and reload the manual systemd user service
  run             Run QEMU and one private noVNC proxy in the foreground
  start           Start the linked systemd user service
  stop            Ask the guest to shut down cleanly through QMP
  force-stop      Terminate only the verified project-owned QEMU process
  status          Show process, port, storage, and configuration status
  url             Print the loopback-only noVNC URL
  logs            Follow the systemd user-service journal

Override RAM per launch without editing config:
  HACKINTOSH_KVM_RAM_GIB=24 hackintosh-kvm.sh run
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"
}

systemctl_user() {
  local runtime=/run/user/$(id -u)
  env \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
    systemctl --user "$@"
}

require_uint() {
  local name=$1
  local value=$2
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be an unsigned integer, got: $value"
  (( value > 0 )) || die "$name must be greater than zero"
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

verify_hash() {
  local path=$1
  local expected=$2
  local actual
  [[ -f "$path" ]] || die "required file is missing: $path"
  actual=$(sha256_of "$path")
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for $path"
}

ensure_layout() {
  mkdir -p "$RUNTIME_ROOT" "$RECOVERY_DIR" "$(dirname -- "$DISK_IMAGE")" "$STATE_DIR" "$LOG_DIR"
  chmod 700 "$RUNTIME_ROOT" "$RECOVERY_DIR" "$(dirname -- "$DISK_IMAGE")" "$STATE_DIR" "$LOG_DIR"
}

prepare_novnc_web_root() {
  local source_rfb source_hash patch_hash expected_stamp current_stamp
  local staging previous

  source_rfb=$NOVNC_SYSTEM_ROOT/core/rfb.js
  [[ -f "$source_rfb" ]] || die "system noVNC source is missing: $source_rfb"
  [[ -f "$NOVNC_LAYOUT_PATCH" ]] || die "layout-safe noVNC patch is missing: $NOVNC_LAYOUT_PATCH"

  source_hash=$(sha256_of "$source_rfb")
  patch_hash=$(sha256_of "$NOVNC_LAYOUT_PATCH")
  expected_stamp="$source_hash $patch_hash"
  current_stamp=
  if [[ -r "$NOVNC_WEB_ROOT/.layout-safe-stamp" ]]; then
    current_stamp=$(<"$NOVNC_WEB_ROOT/.layout-safe-stamp")
  fi
  cleanup_stale_novnc_web_roots
  if [[ "$current_stamp" == "$expected_stamp" && -f "$NOVNC_WEB_ROOT/core/rfb.js" ]]; then
    return
  fi
  if [[ "$source_hash" != "$EXPECTED_NOVNC_RFB_SHA256" ]]; then
    if [[ -f "$NOVNC_WEB_ROOT/core/rfb.js" ]]; then
      warn "installed noVNC changed; retaining the last verified private web root until its patch is reviewed"
    else
      warn "installed noVNC changed and no verified private web root exists; using upstream noVNC for remote-access continuity"
      NOVNC_WEB_ROOT=$NOVNC_SYSTEM_ROOT
    fi
    return
  fi

  ensure_layout
  require_command patch
  staging=$(mktemp -d "$STATE_DIR/novnc-layout-safe.new.XXXXXX")
  if ! (
    cp -a "$NOVNC_SYSTEM_ROOT/." "$staging/"
    patch --batch --forward -d "$staging" -p1 <"$NOVNC_LAYOUT_PATCH"
    if command -v node >/dev/null 2>&1; then
      node --check "$staging/core/rfb.js"
    fi
    printf '%s\n' "$expected_stamp" >"$staging/.layout-safe-stamp"
  ); then
    rm -rf -- "$staging"
    die "failed to construct the private layout-safe noVNC web root"
  fi

  previous=$STATE_DIR/novnc-layout-safe.previous.$$.${RANDOM}
  if [[ -e "$NOVNC_WEB_ROOT" ]]; then
    mv -- "$NOVNC_WEB_ROOT" "$previous"
  fi
  if ! mv -- "$staging" "$NOVNC_WEB_ROOT"; then
    [[ ! -e "$previous" ]] || mv -- "$previous" "$NOVNC_WEB_ROOT"
    die "failed to promote the verified layout-safe noVNC web root"
  fi
  if directory_is_process_cwd "$previous"; then
    warn "an active noVNC proxy is retaining the previous web root; restart only that proxy to serve the update"
  else
    rm -rf -- "$previous"
  fi
  say "prepared private layout-safe noVNC web root: $NOVNC_WEB_ROOT"
}

directory_is_process_cwd() {
  local directory=$1 process_cwd target

  [[ -d "$directory" ]] || return 1
  target=$(readlink -f -- "$directory") || return 1
  for process_cwd in /proc/[0-9]*/cwd; do
    [[ "$(readlink -- "$process_cwd" 2>/dev/null || true)" == "$target" ]] && return 0
  done
  return 1
}

cleanup_stale_novnc_web_roots() {
  local previous

  for previous in "$STATE_DIR"/novnc-layout-safe.previous.*; do
    [[ -d "$previous" ]] || continue
    directory_is_process_cwd "$previous" || rm -rf -- "$previous"
  done
}

validate_config() {
  require_uint RAM_GIB "$RAM_GIB"
  require_uint CPU_CORES "$CPU_CORES"
  require_uint CPU_THREADS "$CPU_THREADS"
  require_uint VNC_DISPLAY "$VNC_DISPLAY"
  require_uint NOVNC_PORT "$NOVNC_PORT"
  require_uint SSH_PORT "$SSH_PORT"
  (( RAM_GIB <= 96 )) || die "RAM_GIB exceeds the 96 GiB safety ceiling"
  (( CPU_CORES * CPU_THREADS <= 16 )) || die "requested vCPU count exceeds the 16-vCPU safety ceiling"
  (( VNC_PORT <= 65535 && NOVNC_PORT <= 65535 && SSH_PORT <= 65535 )) || die "a configured port is invalid"
  [[ "$VNC_BIND" == "127.0.0.1" && "$NOVNC_BIND" == "127.0.0.1" ]] || \
    die "VNC and noVNC must remain loopback-only"
  [[ "$DISK_SIZE" =~ ^[1-9][0-9]*[GMTP]$ ]] || die "DISK_SIZE must look like 512G"
}

validate_host() {
  require_command qemu-system-x86_64
  require_command qemu-img
  require_command git
  require_command python3
  require_command sha256sum
  require_command ss
  [[ -c /dev/kvm ]] || die "/dev/kvm is unavailable"
  [[ -r /dev/kvm && -w /dev/kvm ]] || die "the current user cannot use /dev/kvm"
}

verify_upstream() {
  local commit
  [[ -d "$UPSTREAM_DIR/.git" ]] || die "OSX-KVM checkout is missing: $UPSTREAM_DIR"
  commit=$(git -C "$UPSTREAM_DIR" rev-parse HEAD)
  [[ "$commit" == "$EXPECTED_UPSTREAM_COMMIT" ]] || \
    die "OSX-KVM checkout is not the audited commit ($commit)"
  verify_hash "$OPENCORE_SOURCE_IMAGE" "$EXPECTED_OPENCORE_SHA256"
  verify_hash "$OVMF_CODE" "$EXPECTED_OVMF_CODE_SHA256"
  verify_hash "$OVMF_VARS_SOURCE" "$EXPECTED_OVMF_VARS_SHA256"
}

verify_selected_opencore() {
  local expected
  [[ -f "$OPENCORE_IMAGE" ]] || die "selected OpenCore image is missing: $OPENCORE_IMAGE"
  if [[ "$OPENCORE_IMAGE" == "$OPENCORE_SOURCE_IMAGE" ]]; then
    return 0
  fi
  [[ "$OPENCORE_IMAGE" == "$OPENCORE_PRIVATE_IMAGE" ]] || \
    die "OPENCORE_IMAGE must be the audited source or managed private image"
  [[ -s "$APPLE_SERVICES_MANIFEST" ]] || \
    die "private OpenCore manifest is missing; run '$0 apple-services' while the VM is stopped"
  expected=$(sed -n 's/^private_opencore_sha256=//p' "$APPLE_SERVICES_MANIFEST" | head -n 1)
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "private OpenCore manifest is invalid"
  verify_hash "$OPENCORE_PRIVATE_IMAGE" "$expected"
  qemu-img info "$OPENCORE_PRIVATE_IMAGE" >/dev/null || die "private OpenCore image is unreadable"
}

verify_recovery() {
  local chunklist=$RECOVERY_DIR/BaseSystem.chunklist
  [[ -s "$BASE_DMG" && -s "$chunklist" ]] || return 1
  python3 - "$UPSTREAM_DIR/fetch-macOS-v2.py" "$BASE_DMG" "$chunklist" <<'PY'
import contextlib
import importlib.util
import io
import os
import sys

spec = importlib.util.spec_from_file_location("osx_kvm_fetch", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
# Upstream verification asks for terminal width without handling a non-TTY.
# Supply a deterministic width for systemd, SSH, and piped invocations.
module.os.get_terminal_size = lambda *args, **kwargs: os.terminal_size((80, 24))
with contextlib.redirect_stdout(io.StringIO()):
    module.verify_image(sys.argv[2], sys.argv[3])
PY
}

extract_osk() {
  local source_file=$UPSTREAM_DIR/OpenCore-Boot.sh
  local value
  [[ -f "$source_file" ]] || die "upstream OpenCore launcher is missing"
  value=$(sed -n 's/.*isa-applesmc,osk="\([^"]*\)".*/\1/p' "$source_file" | head -n 1)
  [[ -n "$value" ]] || die "could not obtain the private AppleSMC runtime value from upstream"
  printf '%s' "$value"
}

owned_pid() {
  local pid=$1
  local marker=$2
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  tr '\0' '\n' <"/proc/$pid/cmdline" 2>/dev/null | grep -Fq -- "$marker"
}

pid_from_file() {
  local file=$1
  [[ -f "$file" ]] || return 1
  tr -d '[:space:]' <"$file"
}

qemu_pid() {
  local pid
  pid=$(pid_from_file "$QEMU_PID_FILE") || return 1
  owned_pid "$pid" "$DISK_IMAGE" || return 1
  printf '%s\n' "$pid"
}

novnc_pid() {
  local pid
  pid=$(pid_from_file "$NOVNC_PID_FILE") || return 1
  owned_pid "$pid" "$VNC_BIND:$VNC_PORT" || return 1
  printf '%s\n' "$pid"
}

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

ensure_ports_free() {
  local port
  for port in "$VNC_PORT" "$NOVNC_PORT" "$SSH_PORT"; do
    if port_is_listening "$port"; then
      die "TCP port $port is already in use; refusing to disturb its owner"
    fi
  done
}

prepare_identity() {
  if [[ ! -s "$MAC_FILE" ]]; then
    printf '52:54:00:%02x:%02x:%02x\n' \
      "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))" \
      "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))" \
      "$((16#$(od -An -N1 -tx1 /dev/urandom | tr -d ' ')))" >"$MAC_FILE"
  fi
  if [[ ! -s "$UUID_FILE" ]]; then
    require_command uuidgen
    uuidgen >"$UUID_FILE"
  fi
  if [[ ! -s "$VMGENID_FILE" ]]; then
    require_command uuidgen
    uuidgen >"$VMGENID_FILE"
  fi
  [[ "$(<"$UUID_FILE")" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || \
    die "private machine UUID is invalid"
  [[ "$(<"$VMGENID_FILE")" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || \
    die "private VM generation ID is invalid"
  chmod 600 "$MAC_FILE" "$UUID_FILE" "$VMGENID_FILE"
}

prepare_recovery() {
  local tmp_image
  [[ -s "$BASE_DMG" ]] || die "recovery image is missing; run '$0 fetch' first"
  verify_recovery || die "Apple recovery image verification failed; do not boot or overwrite it implicitly"
  if [[ ! -s "$BASE_IMG" || "$BASE_DMG" -nt "$BASE_IMG" ]]; then
    require_command dmg2img
    tmp_image=$BASE_IMG.partial.$$
    rm -f -- "$tmp_image"
    say "converting the verified recovery DMG to a raw QEMU image"
    if ! dmg2img "$BASE_DMG" "$tmp_image"; then
      rm -f -- "$tmp_image"
      die "recovery-image conversion failed"
    fi
    chmod 600 "$tmp_image"
    mv -f -- "$tmp_image" "$BASE_IMG"
  fi
}

prepare_storage() {
  if [[ ! -f "$OVMF_VARS_PRIVATE" ]]; then
    install -m 0600 "$OVMF_VARS_SOURCE" "$OVMF_VARS_PRIVATE"
  fi
  if [[ ! -f "$DISK_IMAGE" ]]; then
    say "creating sparse $DISK_SIZE qcow2 disk at $DISK_IMAGE"
    qemu-img create -f qcow2 -o compat=1.1,lazy_refcounts=on,preallocation=off "$DISK_IMAGE" "$DISK_SIZE"
    chmod 600 "$DISK_IMAGE"
  fi
  if qemu_pid >/dev/null 2>&1; then
    warn "VM is running; skipping the offline qcow2 consistency check"
  else
    qemu-img check -q "$DISK_IMAGE" || die "qcow2 consistency check failed"
  fi
}

write_private_manifest() {
  local manifest=$STATE_DIR/asset-manifest.txt
  {
    printf 'generated_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'upstream_commit=%s\n' "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
    printf 'opencore_source_sha256=%s\n' "$(sha256_of "$OPENCORE_SOURCE_IMAGE")"
    printf 'opencore_selected_sha256=%s\n' "$(sha256_of "$OPENCORE_IMAGE")"
    printf 'ovmf_code_sha256=%s\n' "$(sha256_of "$OVMF_CODE")"
    printf 'ovmf_vars_source_sha256=%s\n' "$(sha256_of "$OVMF_VARS_SOURCE")"
    printf 'base_system_dmg_sha256=%s\n' "$(sha256_of "$BASE_DMG")"
    printf 'base_system_img_sha256=%s\n' "$(sha256_of "$BASE_IMG")"
  } >"$manifest"
  chmod 600 "$manifest"
}

fetch_recovery() {
  validate_config
  ensure_layout
  require_command python3
  verify_upstream
  if [[ -s "$BASE_DMG" && -s "$RECOVERY_DIR/BaseSystem.chunklist" ]]; then
    if verify_recovery; then
      say "existing recovery image passed Apple chunklist verification"
      return 0
    fi
    die "existing recovery files are incomplete or invalid; remove only those two private files before retrying"
  fi
  say "downloading macOS Sequoia recovery directly from Apple"
  python3 "$UPSTREAM_DIR/fetch-macOS-v2.py" \
    --action download \
    --board-id Mac-7BA5B2D9E42DDD94 \
    --mlb 00000000000000000 \
    --os-type default \
    --outdir "$RECOVERY_DIR" \
    --verbose
}

prepare() {
  validate_config
  ensure_layout
  validate_host
  verify_upstream
  verify_selected_opencore
  prepare_recovery
  prepare_storage
  prepare_identity
  write_private_manifest
  say "private VM state is ready"
  say "virtual disk capacity: $DISK_SIZE (qcow2 allocation grows on demand)"
  say "guest memory ceiling for the next launch: ${RAM_GIB} GiB (not preallocated)"
}

verify() {
  local ignore_msrs=unknown
  prepare
  if [[ -r /sys/module/kvm/parameters/ignore_msrs ]]; then
    ignore_msrs=$(< /sys/module/kvm/parameters/ignore_msrs)
  fi
  say "KVM: available"
  say "QEMU: $(qemu-system-x86_64 --version | head -n 1)"
  say "OSX-KVM commit: $(git -C "$UPSTREAM_DIR" rev-parse --short=12 HEAD)"
  say "KVM ignore_msrs: $ignore_msrs"
  if [[ "$ignore_msrs" != "Y" && "$ignore_msrs" != "1" ]]; then
    warn "leave ignore_msrs unchanged for the first evidence-based boot; enable it only if the QEMU log shows an MSR failure"
  fi
  if qemu_pid >/dev/null 2>&1; then
    qemu-img info --force-share "$DISK_IMAGE"
  else
    qemu-img info "$DISK_IMAGE"
  fi
}

run_vm() {
  local osk mac machine_uuid vm_generation_id log_file qemu_child novnc_child rc
  local -a qemu_args

  validate_config
  if qemu_pid >/dev/null 2>&1; then
    die "the project-owned VM is already running"
  fi
  if novnc_pid >/dev/null 2>&1; then
    die "the project-owned noVNC proxy is already running"
  fi
  prepare
  ensure_ports_free
  require_command websockify
  prepare_novnc_web_root

  osk=$(extract_osk)
  mac=$(<"$MAC_FILE")
  machine_uuid=$(<"$UUID_FILE")
  vm_generation_id=$(<"$VMGENID_FILE")
  log_file=$LOG_DIR/qemu-$(date -u +%Y%m%dT%H%M%SZ).log
  ln -sfn "$(basename -- "$log_file")" "$LOG_DIR/latest.log"
  rm -f -- "$QMP_SOCKET"

  qemu_args=(
    -name Hackintosh-Sequoia,process=hackintosh-sequoia
    -enable-kvm
    -m "${RAM_GIB}G"
    -object "memory-backend-ram,id=ram0,size=${RAM_GIB}G,prealloc=off,dump=off"
    -machine q35,memory-backend=ram0,hpet=off
    -cpu "Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check"
    -smp "$((CPU_CORES * CPU_THREADS))",cores="$CPU_CORES",threads="$CPU_THREADS",sockets=1
    -uuid "$machine_uuid"
    -device "vmgenid,guid=$vm_generation_id"
    -device qemu-xhci,id=xhci
    -device usb-kbd,bus=xhci.0
    -device usb-tablet,bus=xhci.0
    -device usb-ehci,id=ehci
    -device "isa-applesmc,osk=$osk"
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$OVMF_VARS_PRIVATE"
    -smbios type=2
    -device ich9-ahci,id=sata
    -drive "id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=$OPENCORE_IMAGE"
    -device ide-hd,bus=sata.2,drive=OpenCoreBoot
    -drive "id=InstallMedia,if=none,format=raw,file=$BASE_IMG"
    -device ide-hd,bus=sata.3,drive=InstallMedia
    -drive "id=MacHDD,if=none,format=qcow2,cache=none,discard=unmap,file=$DISK_IMAGE"
    -device ide-hd,bus=sata.4,drive=MacHDD
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
    -device "virtio-net-pci,netdev=net0,id=net0,mac=$mac"
    -device vmware-svga
    -display none
    -vnc "$VNC_BIND:$VNC_DISPLAY,share=force-shared"
    -qmp "unix:$QMP_SOCKET,server=on,wait=off"
    -monitor none
    -serial none
  )

  cleanup() {
    local live
    if [[ -n "${novnc_child:-}" ]] && owned_pid "$novnc_child" "$VNC_BIND:$VNC_PORT"; then
      kill -TERM "$novnc_child" 2>/dev/null || true
      wait "$novnc_child" 2>/dev/null || true
    fi
    live=$(pid_from_file "$QEMU_PID_FILE" 2>/dev/null || true)
    [[ -z "$live" || "$live" != "${qemu_child:-}" ]] || rm -f -- "$QEMU_PID_FILE"
    live=$(pid_from_file "$NOVNC_PID_FILE" 2>/dev/null || true)
    [[ -z "$live" || "$live" != "${novnc_child:-}" ]] || rm -f -- "$NOVNC_PID_FILE"
    rm -f -- "$QMP_SOCKET"
  }

  forward_signal() {
    if [[ -n "${qemu_child:-}" ]] && owned_pid "$qemu_child" "$DISK_IMAGE"; then
      kill -TERM "$qemu_child" 2>/dev/null || true
    fi
  }

  trap forward_signal INT TERM
  trap cleanup EXIT

  websockify --web="$NOVNC_WEB_ROOT" "$NOVNC_BIND:$NOVNC_PORT" "$VNC_BIND:$VNC_PORT" \
    >>"$LOG_DIR/novnc.log" 2>&1 &
  novnc_child=$!
  printf '%s\n' "$novnc_child" >"$NOVNC_PID_FILE"
  sleep 0.5
  owned_pid "$novnc_child" "$VNC_BIND:$VNC_PORT" || die "noVNC proxy did not start; inspect $LOG_DIR/novnc.log"

  say "starting VM; noVNC: $NOVNC_URL"
  qemu-system-x86_64 "${qemu_args[@]}" >>"$log_file" 2>&1 &
  qemu_child=$!
  printf '%s\n' "$qemu_child" >"$QEMU_PID_FILE"

  set +e
  wait "$qemu_child"
  rc=$?
  set -e
  if (( rc != 0 )); then
    warn "QEMU exited with status $rc; inspect $log_file"
  fi
  return "$rc"
}

start_service() {
  systemctl_user cat hackintosh-kvm.service >/dev/null 2>&1 || \
    die "run '$0 install-service' first"
  systemctl_user start hackintosh-kvm.service
  systemctl_user --no-pager --full status hackintosh-kvm.service
}

install_service() {
  local source=$REPO_DIR/scripts/hackintosh-kvm.service
  local target=$HOME/.config/systemd/user/hackintosh-kvm.service
  [[ -f "$source" ]] || die "service source is missing: $source"
  if [[ -L "$target" && "$(readlink -f -- "$target")" == "$source" ]]; then
    say "systemd user-service link already points to the canonical unit"
  elif [[ -e "$target" || -L "$target" ]]; then
    die "a different unit already occupies $target; refusing to overwrite it"
  else
    systemctl_user link "$source"
  fi
  systemctl_user daemon-reload
  say "service linked but not enabled at boot"
}

qmp_powerdown() {
  [[ -S "$QMP_SOCKET" ]] || die "QMP socket is unavailable; run status before considering force-stop"
  python3 - "$QMP_SOCKET" <<'PY'
import json
import socket
import sys

path = sys.argv[1]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(5)
sock.connect(path)
sock.recv(65536)
for command in ({"execute": "qmp_capabilities"}, {"execute": "system_powerdown"}):
    sock.sendall((json.dumps(command) + "\r\n").encode())
    sock.recv(65536)
sock.close()
PY
  say "ACPI power-button request sent; the guest may take a minute to shut down"
}

force_stop() {
  local pid
  pid=$(qemu_pid) || die "no verified project-owned QEMU process is running"
  warn "sending SIGTERM only to verified project-owned QEMU PID $pid"
  kill -TERM "$pid"
}

status() {
  local pid allocation=missing
  validate_config
  if pid=$(qemu_pid 2>/dev/null); then
    say "QEMU: running (PID $pid)"
  else
    say "QEMU: stopped"
  fi
  if pid=$(novnc_pid 2>/dev/null); then
    say "noVNC: running (PID $pid)"
  else
    say "noVNC: stopped"
  fi
  [[ -f "$DISK_IMAGE" ]] && allocation=$(du -h "$DISK_IMAGE" | awk '{print $1}')
  say "runtime: $RUNTIME_ROOT"
  say "disk: $DISK_IMAGE; capacity $DISK_SIZE; allocated $allocation"
  say "next-launch memory: ${RAM_GIB} GiB; vCPUs: $((CPU_CORES * CPU_THREADS))"
  if [[ "$OPENCORE_IMAGE" == "$OPENCORE_PRIVATE_IMAGE" ]]; then
    say "OpenCore identity: managed private image"
  else
    say "OpenCore identity: audited template image"
  fi
  say "forwarded guest SSH: 127.0.0.1:$SSH_PORT"
  say "noVNC: $NOVNC_URL"
  say "noVNC keyboard: layout-safe punctuation (append layoutsafe=0 to disable)"
}

command=${1:-}
case "$command" in
  fetch) fetch_recovery ;;
  prepare) prepare ;;
  apple-services) exec "$SCRIPT_DIR/hackintosh-kvm-apple-services.sh" prepare ;;
  prepare-novnc) prepare_novnc_web_root ;;
  verify) verify ;;
  install-service) install_service ;;
  run) run_vm ;;
  start) start_service ;;
  stop) qmp_powerdown ;;
  force-stop) force_stop ;;
  status) status ;;
  url) printf '%s\n' "$NOVNC_URL" ;;
  logs) exec journalctl --user -u hackintosh-kvm.service -f ;;
  help|-h|--help) usage ;;
  '') usage; exit 2 ;;
  *) usage >&2; die "unknown command: $command" ;;
esac
