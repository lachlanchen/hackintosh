# Xcode Development Toolchain

## Version Pin

Use universal Xcode 26.3 (`17C529`).

Apple documents that Xcode 26.3:

- requires macOS Sequoia 15.6 or later,
- includes Swift 6.2.3,
- includes the iOS 26.2 SDK,
- supports on-device debugging for iOS 15 and later.

Do not use `xcodes install --latest` on this machine. Current later Xcode
versions require macOS Tahoe and can make the toolchain unusable without an OS
upgrade.

## Verified Bootstrap

- Command Line Tools for Xcode 16.4
- Apple clang 17.0.0
- Apple Git 2.39.5
- `xcodes` 2.0.3 universal binary

`xcodes` was verified as a Developer ID-signed universal executable before
installation to `/usr/local/bin/xcodes`.

## Install

```bash
xcodes install 26.3 --select --experimental-unxip --empty-trash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
xcode-select -p
```

Authentication to Apple must be completed interactively. Do not store Apple
credentials or browser cookies in this repository.

## Simulator Policy

Install only the runtime needed by the current GlassAgent target. Simulator
runtimes are large and are not evidence for Bluetooth, CXR SDK, camera,
microphone, background execution, thermal, or power behavior. Those workflows
require a physical iPhone.

## GlassAgent Checkout

Clone into a normal project directory, not Desktop/Documents/Downloads, because
Xcode's coding-agent privacy permissions can become difficult to recover after
an initial denial.

```bash
mkdir -p ~/Projects
git clone --recurse-submodules git@github.com:lachlanchen/GlassAgent.git \
  ~/Projects/GlassAgent
```

Read the root and submodule `AGENTS.md` files before editing.

