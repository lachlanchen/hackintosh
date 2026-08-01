#!/usr/bin/env bash
set -u

PATH=/usr/local/bin:/usr/bin:/bin
umask 077

readonly HOST_ALIAS="${OPTIPLEX_7050_HOST:-glassagent-mac}"
readonly TARGET_MAC="${OPTIPLEX_7050_MAC:-}"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/optiplex-7050-monitor"
readonly MISSES_FILE="${STATE_DIR}/consecutive-misses"
readonly LAST_STATE_FILE="${STATE_DIR}/last-state"
readonly LAST_WAKE_FILE="${STATE_DIR}/last-wake-epoch"
readonly LAST_HEALTH_FILE="${STATE_DIR}/last-remote-health"
readonly WAKE_AFTER_MISSES=3
readonly WAKE_RATE_LIMIT=600

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if command -v flock >/dev/null 2>&1; then
  exec 9>"${STATE_DIR}/lock"
  flock -n 9 || exit 0
fi

log_event() {
  logger -t optiplex-7050-monitor -- "$*"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

read_integer() {
  local path="$1"
  local value=0

  if [ -r "$path" ]; then
    read -r value < "$path" || value=0
  fi
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%s\n' "$value"
}

write_state() {
  local path="$1"
  local value="$2"
  local candidate="${path}.$$"

  printf '%s\n' "$value" > "$candidate"
  mv -f "$candidate" "$path"
}

transition_to() {
  local new_state="$1"
  local old_state=unknown

  if [ -r "$LAST_STATE_FILE" ]; then
    read -r old_state < "$LAST_STATE_FILE" || old_state=unknown
  fi
  if [ "$new_state" != "$old_state" ]; then
    log_event "7050 state changed: ${old_state} -> ${new_state}"
    write_state "$LAST_STATE_FILE" "$new_state"
  fi
}

send_wake_packet() {
  local compact_mac
  local port

  case "$TARGET_MAC" in
    [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) ;;
    *)
      log_event "cannot send Wake-on-LAN: OPTIPLEX_7050_MAC is invalid"
      return 1
      ;;
  esac

  command -v perl >/dev/null 2>&1 || return 1
  command -v nc >/dev/null 2>&1 || return 1
  compact_mac=$(printf '%s' "$TARGET_MAC" | tr -d ':')

  for port in 7 9; do
    perl -e \
      'print(("\xff" x 6) . (pack("H*", $ARGV[0]) x 16));' \
      "$compact_mac" |
      nc -u -b -w1 255.255.255.255 "$port" >/dev/null 2>&1 || true
  done
  log_event "sent a rate-limited Wake-on-LAN request after repeated SSH failure"
}

remote_health=$(
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ServerAliveInterval=3 \
    -o ServerAliveCountMax=1 \
    "$HOST_ALIAS" \
    'printf "time_utc=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; printf "uptime="; uptime; printf "console_user="; stat -f %Su /dev/console 2>/dev/null || printf unknown; printf "\nuu_processes="; pgrep -f "^/Applications/UURemote.app" 2>/dev/null | wc -l | tr -d " "; printf "\n"' \
    2>/dev/null
)
ssh_result=$?

if [ "$ssh_result" -eq 0 ]; then
  printf '%s\n' "$remote_health" > "${LAST_HEALTH_FILE}.$$"
  mv -f "${LAST_HEALTH_FILE}.$$" "$LAST_HEALTH_FILE"
  write_state "$MISSES_FILE" 0
  transition_to online
  exit 0
fi

misses=$(read_integer "$MISSES_FILE")
misses=$((misses + 1))
write_state "$MISSES_FILE" "$misses"
transition_to unreachable

if [ "$misses" -lt "$WAKE_AFTER_MISSES" ]; then
  exit 0
fi

now=$(date +%s)
last_wake=$(read_integer "$LAST_WAKE_FILE")
if [ $((now - last_wake)) -lt "$WAKE_RATE_LIMIT" ]; then
  exit 0
fi

if send_wake_packet; then
  write_state "$LAST_WAKE_FILE" "$now"
fi
