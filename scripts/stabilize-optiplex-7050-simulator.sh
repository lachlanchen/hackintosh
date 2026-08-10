#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: stabilize-optiplex-7050-simulator.sh <status|stabilize|restore-ui>

  status      Read the current guard settings and GPU-renderer processes.
  stabilize   Shut down every simulator and disable framebuffer compositing.
  restore-ui  Shut down every simulator and restore Apple's default renderer.

This script does not delete devices, runtimes, app data, or DerivedData.
EOF
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' "error: this guard must run on macOS" >&2
    exit 1
  fi
}

read_default() {
  local domain="$1"
  local key="$2"

  if ! /usr/bin/defaults read "$domain" "$key" 2>/dev/null; then
    printf '%s\n' "<unset>"
  fi
}

show_status() {
  printf 'renderer_policy='
  read_default com.apple.CoreSimulator FramebufferServerRendererPolicy
  printf 'restore_windows='
  read_default com.apple.iphonesimulator NSQuitAlwaysKeepsWindows
  printf 'ignore_saved_state='
  read_default com.apple.iphonesimulator ApplePersistenceIgnoreState
  printf '%s\n' 'gpu_renderer_processes:'
  /usr/bin/pgrep -lf 'SimMetalHost|SimRenderServer|/Simulator.app/' || true
}

shutdown_simulators() {
  local simctl

  simctl="$(/usr/bin/xcrun --find simctl)"
  "$simctl" shutdown all
  /usr/bin/killall -TERM Simulator 2>/dev/null || true
  /usr/bin/killall -TERM SimMetalHost 2>/dev/null || true
  /usr/bin/killall -TERM SimRenderServer 2>/dev/null || true
  /bin/sleep 2
}

stabilize() {
  shutdown_simulators
  /usr/bin/defaults write \
    com.apple.CoreSimulator FramebufferServerRendererPolicy -string none
  /usr/bin/defaults write \
    com.apple.iphonesimulator NSQuitAlwaysKeepsWindows -bool false
  /usr/bin/defaults write \
    com.apple.iphonesimulator ApplePersistenceIgnoreState -bool true
  show_status
}

restore_ui() {
  shutdown_simulators
  /usr/bin/defaults delete \
    com.apple.CoreSimulator FramebufferServerRendererPolicy 2>/dev/null || true
  /usr/bin/defaults delete \
    com.apple.iphonesimulator ApplePersistenceIgnoreState 2>/dev/null || true
  /usr/bin/defaults write \
    com.apple.iphonesimulator NSQuitAlwaysKeepsWindows -bool false
  show_status
}

main() {
  require_macos

  case "${1:-status}" in
    status)
      show_status
      ;;
    stabilize)
      stabilize
      ;;
    restore-ui)
      restore_ui
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
