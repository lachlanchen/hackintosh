#!/bin/bash

set -euo pipefail

expected_user="lachlan"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
public_key_path=${1:-"$script_dir/authorized_key.pub"}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "this bootstrap must run in macOS"
[ "$(id -un)" = "$expected_user" ] ||
  fail "run this after Setup Assistant while logged in as $expected_user"
[ -f "$public_key_path" ] || fail "public key is missing: $public_key_path"

public_key=$(sed -n '1p' "$public_key_path")
case "$public_key" in
  ssh-ed25519\ *) ;;
  *) fail "the key must be one OpenSSH Ed25519 public key" ;;
esac
[ "$(wc -l < "$public_key_path" | tr -d ' ')" -eq 1 ] ||
  fail "the public key file must contain exactly one line"

printf 'macOS will request the %s administrator password once.\n' "$expected_user"
sudo -v

umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
if ! grep -Fqx "$public_key" "$HOME/.ssh/authorized_keys"; then
  printf '%s\n' "$public_key" >> "$HOME/.ssh/authorized_keys"
fi

sudo systemsetup -setremotelogin on
sudo scutil --set ComputerName "OptiPlex-3040"
sudo scutil --set LocalHostName "OptiPlex-3040"
sudo scutil --set HostName "OptiPlex-3040"
sudo pmset -a \
  sleep 0 \
  disksleep 0 \
  displaysleep 0 \
  powernap 0 \
  standby 0 \
  autopoweroff 0 \
  womp 1 \
  tcpkeepalive 1 \
  autorestart 1

sudo launchctl enable system/com.openssh.sshd
sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true

printf '\nRemote Login:\n'
sudo systemsetup -getremotelogin
printf '\nPower policy:\n'
pmset -g custom
printf '\nHost identity:\n'
scutil --get ComputerName
scutil --get LocalHostName
printf '\nSSH key fingerprint:\n'
ssh-keygen -lf "$public_key_path"
printf '\nBootstrap complete. Reboot once, then test key-only SSH.\n'
