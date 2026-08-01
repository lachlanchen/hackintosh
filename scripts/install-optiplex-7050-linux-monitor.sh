#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_DIR
readonly CONFIG_PATH="${HOME}/.config/optiplex-7050-monitor.conf"
readonly LIBEXEC_PATH="${HOME}/.local/libexec/monitor-optiplex-7050-from-linux.sh"
readonly UNIT_DIR="${HOME}/.config/systemd/user"

usage() {
  cat <<'EOF'
Usage:
  ./install-optiplex-7050-linux-monitor.sh \
    --host <ssh-alias> \
    --mac <ethernet-mac>

The SSH alias must already use key-only authentication. The MAC address is
stored only in the user's private configuration, not in the repository.
EOF
}

host_alias=
target_mac=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host)
      host_alias="${2:-}"
      shift 2
      ;;
    --mac)
      target_mac="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

case "$host_alias" in
  ''|*[!A-Za-z0-9._-]*)
    printf 'Invalid SSH alias.\n' >&2
    exit 64
    ;;
esac
case "$target_mac" in
  [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) ;;
  *)
    printf 'Invalid Ethernet MAC address.\n' >&2
    exit 64
    ;;
esac

ssh -o BatchMode=yes -o ConnectTimeout=5 "$host_alias" true

install -d -m 700 "$(dirname "$CONFIG_PATH")"
install -d -m 755 "$(dirname "$LIBEXEC_PATH")" "$UNIT_DIR"
install -m 755 \
  "${SCRIPT_DIR}/monitor-optiplex-7050-from-linux.sh" \
  "$LIBEXEC_PATH"
install -m 644 \
  "${SCRIPT_DIR}/optiplex-7050-monitor.service" \
  "${UNIT_DIR}/optiplex-7050-monitor.service"
install -m 644 \
  "${SCRIPT_DIR}/optiplex-7050-monitor.timer" \
  "${UNIT_DIR}/optiplex-7050-monitor.timer"

umask 077
{
  printf 'OPTIPLEX_7050_HOST=%s\n' "$host_alias"
  printf 'OPTIPLEX_7050_MAC=%s\n' "$target_mac"
} > "$CONFIG_PATH"

systemctl --user daemon-reload
systemctl --user enable --now optiplex-7050-monitor.timer
systemctl --user start optiplex-7050-monitor.service
systemctl --user --no-pager status optiplex-7050-monitor.timer
