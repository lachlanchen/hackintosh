#!/usr/bin/env bash
set -euo pipefail

echo "== Operating system =="
sw_vers

echo
echo "== Root volume =="
diskutil info / |
  grep -E 'Device Node|Volume Name|APFS Volume Group|FileVault|Sealed'

echo
echo "== APFS capacity =="
diskutil apfs list |
  grep -E 'APFS Container Reference|Capacity Ceiling|Capacity In Use By Volumes|Capacity Not Allocated|Name: +(Mac|Sequoia)'

echo
echo "== Graphics =="
system_profiler SPDisplaysDataType |
  grep -E 'Chipset Model|VRAM|Metal|Resolution'

echo
echo "== Graphics identity =="
ioreg -p IOService -n IGPU -r -l 2>/dev/null |
  grep -E 'AAPL,ig-platform-id|device-id|VRAM,totalMB' |
  head -n 12

echo
echo "== Relevant kexts =="
kextstat |
  grep -E 'Lilu|WhateverGreen|AppleIntel(KBL|SKL)Graphics|IntelMausi' || true

echo
echo "== Network ports =="
networksetup -listallhardwareports

echo
echo "== AWDL =="
ifconfig awdl0 2>/dev/null | head -n 8 || echo "awdl0 absent"

echo
echo "== Developer tools =="
xcode-select -p 2>/dev/null || true
xcodebuild -version 2>/dev/null || true
clang --version 2>/dev/null | head -n 2 || true
git --version 2>/dev/null || true
