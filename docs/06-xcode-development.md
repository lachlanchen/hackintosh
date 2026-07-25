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
- Xcode 26.3, build `17C529`
- Selected developer directory:
  `/Applications/Xcode-26.3.0.app/Contents/Developer`

`xcodes` was verified as a Developer ID-signed universal executable before
installation to `/usr/local/bin/xcodes`.

## Verified Installation

The App Store offers a newer Xcode that Sequoia cannot run. The final universal
26.3 archive was downloaded from the authenticated Apple Developer downloads
service instead. Before expansion:

- the archive reported an Apple software signature;
- SHA-256 was
  `cf87232e0419785170edcfa070b750f28808ec00b489ab540c08b7d197c79ae4`;
- the release-candidate build was deliberately rejected in favor of final
  build `17C529`.

The effective installation sequence was:

```bash
xcodes install 26.3 --path ~/Downloads/Xcode_26.3_Universal.xip \
  --select --experimental-unxip --empty-trash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
xcode-select -p
```

The archive was removed after installation. Authentication to Apple was
completed interactively in a dedicated browser profile. Xcode account,
certificate, and provisioning setup remain separate human-authenticated
steps; do not store credentials or browser cookies in this repository.

## Simulator Policy

Install only the runtime needed by the current GlassAgent target. Simulator
runtimes are large and are not evidence for Bluetooth, CXR SDK, camera,
microphone, background execution, thermal, or power behavior. Those workflows
require a physical iPhone.

This host is Intel. Request the universal simulator variant when the current
Xcode platform supports it:

```bash
xcodebuild -downloadPlatform iOS -architectureVariant universal
```

An arm64-only runtime cannot run on this workstation. Keep at least 25 GB free
before downloading so the compressed payload, installation staging, derived
data, and app build can coexist.

## Verified Project Result

The universal iOS 26.3.1 runtime (`23D8133`) is installed. With Xcode 26.3:

- the LightMind CocoaPods workspace builds unsigned;
- automatic development signing succeeds;
- five unit tests and one orientation UI test pass;
- version `0.2.3` build `5` archives and exports for App Store distribution;
- the exported app has production entitlements.

This proves the host can support temporary iOS development. Simulator evidence
does not replace a physical iPhone, and this unsupported Hackintosh is not the
sole final release authority.

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
