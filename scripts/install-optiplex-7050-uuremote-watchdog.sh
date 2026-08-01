#!/bin/bash
set -euo pipefail

PATH=/usr/bin:/bin:/usr/sbin:/sbin

readonly LABEL="com.lachlan.optiplex-7050-uuremote-watchdog"
readonly APP_PATH="/Applications/UURemote.app"
readonly EXPECTED_TEAM_ID="PU9BNSBJW7"
readonly INSTALL_ROOT="/usr/local/libexec"
readonly INSTALLED_SCRIPT="${INSTALL_ROOT}/optiplex-7050-uuremote-watchdog.sh"
readonly INSTALLED_PLIST="/Library/LaunchDaemons/${LABEL}.plist"
readonly STATE_DIR="/var/db/${LABEL}"
SOURCE_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SOURCE_DIR
readonly SOURCE_SCRIPT="${SOURCE_DIR}/optiplex-7050-uuremote-watchdog.sh"
readonly SOURCE_PLIST="${SOURCE_DIR}/${LABEL}.plist"

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-optiplex-7050-uuremote-watchdog.sh install
  sudo ./install-optiplex-7050-uuremote-watchdog.sh status
  sudo ./install-optiplex-7050-uuremote-watchdog.sh uninstall

The watchdog never reboots macOS. It waits for five consecutive unhealthy
checks before restarting only UU Remote's current GUI launch agent.
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'Run this command with sudo.\n' >&2
    exit 77
  fi
}

verify_host() {
  local team_id

  [ "$(uname -s)" = "Darwin" ] || {
    printf 'This installer only supports macOS.\n' >&2
    exit 1
  }
  [ -d "$APP_PATH" ] || {
    printf 'UU Remote is not installed at %s.\n' "$APP_PATH" >&2
    exit 1
  }
  codesign --verify --strict "$APP_PATH"
  team_id=$(
    codesign -dv --verbose=2 "$APP_PATH" 2>&1 |
      sed -n 's/^TeamIdentifier=//p' |
      head -n 1
  )
  [ "$team_id" = "$EXPECTED_TEAM_ID" ] || {
    printf 'Unexpected UU Remote TeamIdentifier: %s\n' "$team_id" >&2
    exit 1
  }
}

print_status() {
  launchctl print "system/${LABEL}" 2>/dev/null |
    grep -E 'state =|runs =|last exit code =|pid =' || true
  if [ -r "${STATE_DIR}/heartbeat" ]; then
    printf '\nLatest heartbeat:\n'
    cat "${STATE_DIR}/heartbeat"
  fi
}

action="${1:-}"
case "$action" in
  install)
    require_root
    verify_host
    [ -f "$SOURCE_SCRIPT" ] || {
      printf 'Missing source script: %s\n' "$SOURCE_SCRIPT" >&2
      exit 1
    }
    [ -f "$SOURCE_PLIST" ] || {
      printf 'Missing source plist: %s\n' "$SOURCE_PLIST" >&2
      exit 1
    }
    plutil -lint "$SOURCE_PLIST"
    mkdir -p "$INSTALL_ROOT"
    install -o root -g wheel -m 755 "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT"
    install -o root -g wheel -m 644 "$SOURCE_PLIST" "$INSTALLED_PLIST"
    launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
    launchctl bootstrap system "$INSTALLED_PLIST"
    launchctl enable "system/${LABEL}"
    launchctl kickstart -k "system/${LABEL}"
    sleep 2
    print_status
    ;;
  status)
    require_root
    print_status
    ;;
  uninstall)
    require_root
    launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
    rm -f "$INSTALLED_PLIST" "$INSTALLED_SCRIPT"
    printf 'Removed %s. Logs and state were retained.\n' "$LABEL"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
