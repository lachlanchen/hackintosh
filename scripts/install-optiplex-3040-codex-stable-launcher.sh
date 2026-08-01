#!/bin/bash

set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

readonly TARGET_APP="/Applications/ChatGPT.app"
readonly EXPECTED_TARGET_ID="com.openai.codex"
readonly EXPECTED_TARGET_TEAM="2DC432GLL2"
readonly TARGET_ICON="$TARGET_APP/Contents/Resources/electron.icns"
readonly LAUNCHER_APP="$HOME/Applications/Codex Stable.app"
readonly LAUNCHER_ID="local.hackintosh.codex-stable"
readonly LAUNCHER_EXECUTABLE="Codex Stable"
readonly LAUNCHER_ICON="CodexStable.icns"
readonly DESKTOP_LINK="$HOME/Desktop/Codex Stable.app"
mode="${1:-install}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

verify_target() {
  local bundle_id
  local team_id

  [ -d "$TARGET_APP" ] || fail "$TARGET_APP is missing"
  [ -f "$TARGET_ICON" ] || fail "$TARGET_ICON is missing"
  /usr/bin/codesign --verify --deep --strict "$TARGET_APP" 2>/dev/null ||
    fail "the Codex desktop signature is invalid"
  bundle_id=$(plist_value "$TARGET_APP/Contents/Info.plist" CFBundleIdentifier)
  [ "$bundle_id" = "$EXPECTED_TARGET_ID" ] ||
    fail "unexpected Codex bundle identifier: $bundle_id"
  team_id=$(
    /usr/bin/codesign -dv --verbose=4 "$TARGET_APP" 2>&1 |
      /usr/bin/sed -n 's/^TeamIdentifier=//p' |
      /usr/bin/head -n 1
  )
  [ "$team_id" = "$EXPECTED_TARGET_TEAM" ] ||
    fail "unexpected Codex signing team: $team_id"
}

write_executable() {
  local destination="$1"

  cat > "$destination" <<'EOF'
#!/bin/bash

set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

readonly TARGET_APP="/Applications/ChatGPT.app"
readonly TARGET_ID="com.openai.codex"
readonly TARGET_TEAM="2DC432GLL2"
readonly LOG_FILE="$HOME/Library/Logs/Codex Stable Launcher.log"

write_log() {
  /bin/mkdir -p "$HOME/Library/Logs"
  printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

notify_failure() {
  /usr/bin/osascript -e \
    'display notification "Launch was stopped; see the launcher log." with title "Codex Stable"' \
    >/dev/null 2>&1 || true
}

main_process_args() {
  local pid

  pid=$(
    /usr/bin/pgrep -f \
      '^/Applications/ChatGPT[.]app/Contents/MacOS/ChatGPT( |$)' |
      /usr/bin/head -n 1
  )
  [ -n "$pid" ] || return 1
  /bin/ps -ww -p "$pid" -o command=
}

has_stable_flags() {
  case "$1" in
    *--disable-gpu-rasterization*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *--disable-zero-copy*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *--disable-gpu-memory-buffer-video-frames*) return 0 ;;
    *) return 1 ;;
  esac
}

verify_target() {
  local bundle_id
  local team_id

  [ -d "$TARGET_APP" ] || return 1
  /usr/bin/codesign --verify --deep --strict "$TARGET_APP" 2>/dev/null ||
    return 1
  bundle_id=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
      "$TARGET_APP/Contents/Info.plist" 2>/dev/null
  )
  [ "$bundle_id" = "$TARGET_ID" ] || return 1
  team_id=$(
    /usr/bin/codesign -dv --verbose=4 "$TARGET_APP" 2>&1 |
      /usr/bin/sed -n 's/^TeamIdentifier=//p' |
      /usr/bin/head -n 1
  )
  [ "$team_id" = "$TARGET_TEAM" ]
}

if ! verify_target; then
  write_log "refused launch: target identity or signature did not verify"
  notify_failure
  exit 1
fi

current_args=$(main_process_args 2>/dev/null || true)
if [ -n "$current_args" ] && has_stable_flags "$current_args"; then
  write_log "activated existing stable process"
  /usr/bin/osascript -e 'tell application id "com.openai.codex" to activate' \
    >/dev/null 2>&1 || true
  exit 0
fi

if [ -n "$current_args" ]; then
  write_log "requesting graceful quit of process without stable flags"
  /usr/bin/osascript -e 'tell application id "com.openai.codex" to quit' \
    >/dev/null 2>&1 || true
  count=0
  while [ "$count" -lt 20 ]; do
    current_args=$(main_process_args 2>/dev/null || true)
    [ -z "$current_args" ] && break
    /bin/sleep 1
    count=$((count + 1))
  done
  if [ -n "$(main_process_args 2>/dev/null || true)" ]; then
    write_log "refused launch: existing process did not quit within 20 seconds"
    notify_failure
    exit 1
  fi
fi

write_log "launching with narrow framebuffer mitigation flags"
/usr/bin/open -na "$TARGET_APP" --args \
  --disable-gpu-rasterization \
  --disable-zero-copy \
  --disable-gpu-memory-buffer-video-frames

count=0
while [ "$count" -lt 20 ]; do
  current_args=$(main_process_args 2>/dev/null || true)
  if [ -n "$current_args" ] && has_stable_flags "$current_args"; then
    write_log "launch verified"
    exit 0
  fi
  /bin/sleep 1
  count=$((count + 1))
done

write_log "launch failed: stable flags were not observed"
/usr/bin/osascript -e 'tell application id "com.openai.codex" to quit' \
  >/dev/null 2>&1 || true
notify_failure
exit 1
EOF
}

write_info_plist() {
  local destination="$1"

  cat > "$destination" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Codex Stable</string>
  <key>CFBundleExecutable</key>
  <string>$LAUNCHER_EXECUTABLE</string>
  <key>CFBundleIconFile</key>
  <string>$LAUNCHER_ICON</string>
  <key>CFBundleIdentifier</key>
  <string>$LAUNCHER_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Codex Stable</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.15</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF
}

assert_owned_launcher() {
  local bundle_id

  [ -d "$LAUNCHER_APP" ] || fail "$LAUNCHER_APP is not an app bundle"
  bundle_id=$(
    plist_value "$LAUNCHER_APP/Contents/Info.plist" CFBundleIdentifier \
      2>/dev/null || true
  )
  [ "$bundle_id" = "$LAUNCHER_ID" ] ||
    fail "refusing to replace unrecognized app at $LAUNCHER_APP"
}

verify_launcher() {
  local expected

  assert_owned_launcher
  [ -x "$LAUNCHER_APP/Contents/MacOS/$LAUNCHER_EXECUTABLE" ] ||
    fail "launcher executable is missing"
  [ -f "$LAUNCHER_APP/Contents/Resources/$LAUNCHER_ICON" ] ||
    fail "launcher icon is missing"
  /usr/bin/codesign --verify --deep --strict "$LAUNCHER_APP" 2>/dev/null ||
    fail "launcher ad-hoc signature is invalid"

  expected=$(mktemp -d "${TMPDIR:-/tmp}/codex-stable-audit.XXXXXX")
  trap 'rm -rf "$expected"' RETURN
  write_executable "$expected/executable"
  write_info_plist "$expected/Info.plist"
  cmp -s "$expected/executable" \
    "$LAUNCHER_APP/Contents/MacOS/$LAUNCHER_EXECUTABLE" ||
    fail "launcher executable has unexpected contents"
  cmp -s "$expected/Info.plist" "$LAUNCHER_APP/Contents/Info.plist" ||
    fail "launcher Info.plist has unexpected contents"
  cmp -s "$TARGET_ICON" "$LAUNCHER_APP/Contents/Resources/$LAUNCHER_ICON" ||
    fail "launcher icon does not match the verified target"
  rm -rf "$expected"
  trap - RETURN

  [ -L "$DESKTOP_LINK" ] || fail "$DESKTOP_LINK is missing"
  [ "$(readlink "$DESKTOP_LINK")" = "$LAUNCHER_APP" ] ||
    fail "$DESKTOP_LINK points somewhere unexpected"
}

audit() {
  local current_args

  verify_target
  printf 'Target: verified %s signed by %s\n' \
    "$EXPECTED_TARGET_ID" "$EXPECTED_TARGET_TEAM"
  printf 'Stable launcher: '
  if [ -e "$LAUNCHER_APP" ] || [ -L "$DESKTOP_LINK" ]; then
    verify_launcher
    printf 'installed and verified\n'
  else
    printf 'missing\n'
  fi
  current_args=$(
    /bin/ps -ww -axo command= |
      /usr/bin/awk \
        '/^\/Applications\/ChatGPT[.]app\/Contents\/MacOS\/ChatGPT( |$)/ { print; exit }'
  )
  printf 'Running mode: '
  case "$current_args" in
    *--disable-gpu-rasterization*--disable-zero-copy*--disable-gpu-memory-buffer-video-frames*)
      printf 'stable flags active\n'
      ;;
    '') printf 'Codex desktop is not running\n' ;;
    *) printf 'ordinary app launch; stable flags are absent\n' ;;
  esac
}

[ "$(uname -s)" = "Darwin" ] || fail "run this script on macOS"
[ "$(id -u)" -ne 0 ] || fail "run as the logged-in desktop user, not root"
case "$mode" in
  install|audit|uninstall) ;;
  *) fail "mode must be install, audit, or uninstall" ;;
esac

if [ "$mode" = "audit" ]; then
  audit
  exit 0
fi

if [ "$mode" = "uninstall" ]; then
  if [ -e "$LAUNCHER_APP" ]; then
    assert_owned_launcher
    rm -rf "$LAUNCHER_APP"
  fi
  if [ -L "$DESKTOP_LINK" ] &&
    [ "$(readlink "$DESKTOP_LINK")" = "$LAUNCHER_APP" ]; then
    rm -f "$DESKTOP_LINK"
  elif [ -e "$DESKTOP_LINK" ]; then
    fail "refusing to remove unrecognized Desktop item: $DESKTOP_LINK"
  fi
  printf 'Removed the Codex Stable launcher. The signed Codex app was unchanged.\n'
  exit 0
fi

verify_target
if [ -e "$LAUNCHER_APP" ]; then
  assert_owned_launcher
fi
if [ -e "$DESKTOP_LINK" ] || [ -L "$DESKTOP_LINK" ]; then
  if ! [ -L "$DESKTOP_LINK" ] ||
    ! [ "$(readlink "$DESKTOP_LINK")" = "$LAUNCHER_APP" ]; then
    fail "refusing to replace unrecognized Desktop item: $DESKTOP_LINK"
  fi
fi

mkdir -p "$HOME/Applications" "$HOME/Desktop"
stage=$(mktemp -d "${TMPDIR:-/tmp}/Codex-Stable.XXXXXX.app")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
write_executable "$stage/Contents/MacOS/$LAUNCHER_EXECUTABLE"
write_info_plist "$stage/Contents/Info.plist"
cp "$TARGET_ICON" "$stage/Contents/Resources/$LAUNCHER_ICON"
chmod 0755 "$stage/Contents/MacOS/$LAUNCHER_EXECUTABLE"
/usr/bin/codesign --force --deep --sign - "$stage" >/dev/null 2>&1

rm -rf "$LAUNCHER_APP"
rm -f "$DESKTOP_LINK"
mv "$stage" "$LAUNCHER_APP"
ln -s "$LAUNCHER_APP" "$DESKTOP_LINK"
trap - EXIT HUP INT TERM

verify_launcher
printf 'Created: %s\n' "$LAUNCHER_APP"
printf 'Shortcut: %s\n' "$DESKTOP_LINK"
printf 'The official Codex app and OpenCore EFI were not modified.\n'
