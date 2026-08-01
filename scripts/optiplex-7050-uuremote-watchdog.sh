#!/bin/bash
set -u

PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

readonly APP_PATH="/Applications/UURemote.app"
readonly EXPECTED_TEAM_ID="PU9BNSBJW7"
readonly DAEMON_LABEL="com.netease.uuremote.daemon"
readonly AGENT_LABEL="com.netease.uuremote.agent"
readonly AGENT_PLIST="/Library/LaunchAgents/com.netease.uuremote.agent.plist"
readonly STATE_DIR="/var/db/com.lachlan.optiplex-7050-uuremote-watchdog"
readonly FAILURE_FILE="${STATE_DIR}/consecutive-failures"
readonly HEARTBEAT_FILE="${STATE_DIR}/heartbeat"
readonly MIN_BOOT_AGE=180
readonly FAILURE_LIMIT=5
readonly SIMULATOR_PROCESS_LIMIT=100
readonly LOAD_LIMIT=100

log_event() {
  logger -t optiplex-7050-uuremote-watchdog -- "$*"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

read_failures() {
  local value

  value=0
  if [ -r "$FAILURE_FILE" ]; then
    read -r value < "$FAILURE_FILE" || value=0
  fi
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%s\n' "$value"
}

write_failures() {
  local value="$1"
  local candidate="${FAILURE_FILE}.$$"

  printf '%s\n' "$value" > "$candidate"
  mv -f "$candidate" "$FAILURE_FILE"
}

verify_uuremote() {
  local team_id

  [ -d "$APP_PATH" ] || return 1
  codesign --verify --strict "$APP_PATH" >/dev/null 2>&1 || return 1
  team_id=$(
    codesign -dv --verbose=2 "$APP_PATH" 2>&1 |
      sed -n 's/^TeamIdentifier=//p' |
      head -n 1
  )
  [ "$team_id" = "$EXPECTED_TEAM_ID" ]
}

process_ids_for_path() {
  local user_id="$1"
  local pattern="$2"

  pgrep -u "$user_id" -f "$pattern" 2>/dev/null || true
}

established_connection_count() {
  local process_ids="$1"
  local process_id
  local count=0
  local current

  for process_id in $process_ids; do
    current=$(
      lsof -nP -a -p "$process_id" -iTCP -sTCP:ESTABLISHED 2>/dev/null |
        awk 'NR > 1 { count++ } END { print count + 0 }'
    )
    count=$((count + current))
  done
  printf '%s\n' "$count"
}

write_heartbeat() {
  local console_user="$1"
  local user_id="$2"
  local agent_pid="$3"
  local server_pid="$4"
  local connection_count="$5"
  local failures="$6"
  local simulator_processes="$7"
  local fileprovider_cpu="$8"
  local boot_uuid
  local candidate="${HEARTBEAT_FILE}.$$"
  local data_free_kb
  local load_average

  boot_uuid=$(sysctl -n kern.bootsessionuuid 2>/dev/null || printf 'unknown')
  load_average=$(sysctl -n vm.loadavg 2>/dev/null || printf 'unknown')
  data_free_kb=$(
    df -k /System/Volumes/Data 2>/dev/null |
      awk 'NR == 2 { print $4 }'
  )

  {
    printf 'time_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'boot_uuid=%s\n' "$boot_uuid"
    printf 'console_user=%s\n' "$console_user"
    printf 'console_uid=%s\n' "$user_id"
    printf 'agent_pid=%s\n' "$agent_pid"
    printf 'server_pid=%s\n' "$server_pid"
    printf 'established_tcp=%s\n' "$connection_count"
    printf 'consecutive_failures=%s\n' "$failures"
    printf 'simulator_runtime_processes=%s\n' "$simulator_processes"
    printf 'fileprovider_cpu_percent=%s\n' "$fileprovider_cpu"
    printf 'load_average=%s\n' "$load_average"
    printf 'data_free_kb=%s\n' "${data_free_kb:-unknown}"
  } > "$candidate"
  mv -f "$candidate" "$HEARTBEAT_FILE"
}

shutdown_runaway_simulator() {
  local console_user="$1"
  local user_id="$2"
  local simulator_processes="$3"
  local load_one="$4"
  local developer_dir
  local home_dir

  if [ "$simulator_processes" -lt "$SIMULATOR_PROCESS_LIMIT" ]; then
    return 0
  fi
  if ! awk -v load="$load_one" -v limit="$LOAD_LIMIT" \
    'BEGIN { exit !(load >= limit) }'; then
    return 0
  fi

  developer_dir=$(xcode-select -p 2>/dev/null || true)
  [ -d "$developer_dir" ] || {
    log_event "simulator pressure exceeded limits, but no active Xcode was found"
    return 1
  }
  home_dir=$(dscl . -read "/Users/${console_user}" NFSHomeDirectory 2>/dev/null |
    awk '{ print $2 }')
  [ -n "$home_dir" ] || home_dir="/Users/${console_user}"

  if launchctl asuser "$user_id" \
    sudo -u "$console_user" \
    env \
      HOME="$home_dir" \
      DEVELOPER_DIR="$developer_dir" \
      /usr/bin/xcrun simctl shutdown all >/dev/null 2>&1; then
    log_event \
      "shut down runaway Simulator: processes=${simulator_processes} load1=${load_one}"
    return 0
  fi

  log_event \
    "failed to shut down runaway Simulator: processes=${simulator_processes} load1=${load_one}"
  return 1
}

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run as root through launchd.\n' >&2
  exit 77
fi

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

boot_time=$(
  sysctl -n kern.boottime 2>/dev/null |
    sed -n 's/.*sec = \([0-9][0-9]*\).*/\1/p'
)
now=$(date +%s)
case "$boot_time" in
  ''|*[!0-9]*) boot_age=0 ;;
  *) boot_age=$((now - boot_time)) ;;
esac

if ! launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
  if verify_uuremote; then
    if launchctl kickstart "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
      log_event "restarted missing UU system daemon"
    else
      log_event "could not restart missing UU system daemon"
    fi
  else
    log_event "refused daemon repair because UU signature validation failed"
  fi
fi

console_user=$(stat -f '%Su' /dev/console 2>/dev/null || printf 'none')
case "$console_user" in
  ''|root|loginwindow|_mbsetupuser|none)
    write_failures 0
    write_heartbeat "$console_user" 0 none none 0 0 0 0
    exit 0
    ;;
esac

user_id=$(id -u "$console_user" 2>/dev/null || printf '0')
case "$user_id" in
  ''|*[!0-9]*|0) exit 0 ;;
esac
if [ "$user_id" -lt 500 ]; then
  exit 0
fi

agent_pids=$(
  process_ids_for_path "$user_id" \
    '^/Applications/UURemote\.app/Contents/MacOS/UURemoteService -agent$'
)
server_pids=$(
  process_ids_for_path "$user_id" \
    '^/Applications/UURemote\.app/Contents/Helpers/UURemoteServer$'
)
all_pids=$(printf '%s\n%s\n' "$agent_pids" "$server_pids" | awk 'NF')
connection_count=$(established_connection_count "$all_pids")
failures=$(read_failures)
simulator_processes=$(
  pgrep -f '/CoreSimulator/.*/RuntimeRoot/' 2>/dev/null |
    wc -l |
    tr -d ' '
)
fileprovider_pid=$(pgrep -u "$user_id" -x fileproviderd 2>/dev/null | head -n 1)
if [ -n "$fileprovider_pid" ]; then
  fileprovider_cpu=$(
    ps -p "$fileprovider_pid" -o '%cpu=' 2>/dev/null |
      awk '{ print $1 + 0 }'
  )
else
  fileprovider_cpu=0
fi
load_one=$(
  sysctl -n vm.loadavg 2>/dev/null |
    sed 's/[{}]//g' |
    awk '{ print $1 }'
)
case "$load_one" in
  ''|*[!0-9.]*) load_one=0 ;;
esac

write_heartbeat \
  "$console_user" \
  "$user_id" \
  "${agent_pids:-none}" \
  "${server_pids:-none}" \
  "$connection_count" \
  "$failures" \
  "$simulator_processes" \
  "$fileprovider_cpu"

if [ "$boot_age" -lt "$MIN_BOOT_AGE" ]; then
  write_failures 0
  exit 0
fi

shutdown_runaway_simulator \
  "$console_user" \
  "$user_id" \
  "$simulator_processes" \
  "$load_one" || true

if [ -n "$agent_pids" ] &&
   [ -n "$server_pids" ] &&
   [ "$connection_count" -gt 0 ]; then
  if [ "$failures" -gt 0 ]; then
    log_event "UU recovered after ${failures} unhealthy checks"
  fi
  write_failures 0
  exit 0
fi

if ! curl --fail --silent --show-error --max-time 8 \
  --output /dev/null \
  'https://www.apple.com/library/test/success.html'; then
  if [ "$failures" -eq 0 ]; then
    log_event "UU appears unhealthy, but internet validation failed; leaving it untouched"
  fi
  write_failures 0
  exit 0
fi

failures=$((failures + 1))
write_failures "$failures"

if [ "$failures" -lt "$FAILURE_LIMIT" ]; then
  if [ "$failures" -eq 1 ]; then
    log_event "UU health check failed; waiting for persistent failure before repair"
  fi
  exit 0
fi

if ! verify_uuremote; then
  log_event "refused agent repair because UU signature validation failed"
  exit 1
fi

if launchctl print "gui/${user_id}/${AGENT_LABEL}" >/dev/null 2>&1; then
  repair_command="kickstart"
  launchctl kickstart -k "gui/${user_id}/${AGENT_LABEL}" >/dev/null 2>&1
  repair_result=$?
else
  repair_command="bootstrap"
  launchctl bootstrap "gui/${user_id}" "$AGENT_PLIST" >/dev/null 2>&1
  repair_result=$?
fi

if [ "$repair_result" -eq 0 ]; then
  log_event "${repair_command} repaired UU after ${failures} consecutive unhealthy checks"
  write_failures 0
  exit 0
fi

log_event "${repair_command} failed after ${failures} consecutive unhealthy checks"
exit 1
