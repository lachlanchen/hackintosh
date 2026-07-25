# Development Host Bootstrap

Status date: 2026-07-25

## Verified Tools

| Tool | Verified version or state |
| --- | --- |
| Command Line Tools | 16.4 |
| Apple clang | 17.0.0 |
| Apple Git | 2.39.5 |
| `xcodes` | 2.0.3 universal |
| Homebrew | 6.0.12, Intel `/usr/local` prefix |
| XcodeGen | 2.46.0 |
| CocoaPods | 1.17.0 |
| Chrome | notarized universal build, dedicated publication profile |
| Windows App | 11.3.7, notarized Microsoft package |
| Xcode | 26.3 (`17C529`), selected and initialized |
| iOS runtime | 26.3.1 (`23D8133`), universal/Intel-capable |

Homebrew analytics are disabled. The Homebrew shell environment is loaded from
the user's `.zprofile`; the local Codex CLI path remains earlier in `PATH`.

## GlassAgent Checkout

The private GlassAgent repository is checked out beneath `~/Projects`.
Key-based GitHub authentication was verified before cloning. The root checkout
and all top-level submodules match their pinned commits.

One submodule belongs to a separately authorized account. Its clean pinned
checkout and Git object store were transferred over the trusted LAN from an
already verified workstation. No GitHub token, browser cookie, or private key
was copied.

## iOS Workspace

The verified preparation flow is:

```bash
cd ~/Projects/GlassAgent/Glass/apps/lightmind-ios
xcodegen generate
pod install
```

The project uses custom Debug and Release `.xcconfig` files. Each file must
include the matching generated `Pods-LightMind` configuration before app
settings, with the ignored local secrets file included last. CocoaPods then
completes without a base-configuration warning.

The only remaining pod warning at this checkpoint is that the vendor SDK still
depends on deprecated AFNetworking. Treat that as vendor technical debt; do
not replace SDK internals during release setup.

The completed host validation includes unsigned and signed builds, five unit
tests, one orientation UI test, and a signed `0.2.3` build `5` archive/export.
Signing assets, account state, archives, and IPAs remain outside this
repository.

## Xcode Boundary

The current App Store Xcode requires a newer macOS release and is rejected on
Sequoia. Use the official Apple Developer downloads archive for universal Xcode
26.3 (`17C529`). Account password and 2FA entry remain human-controlled.

Verified archive SHA-256:

```text
cf87232e0419785170edcfa070b750f28808ec00b489ab540c08b7d197c79ae4
```

The completed installation used:

```bash
xcodes install 26.3 --path /path/to/Xcode_26.3.xip \
  --select --experimental-unxip --empty-trash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```

Xcode now reports version 26.3, build `17C529`, and is selected at
`/Applications/Xcode-26.3.0.app/Contents/Developer`. The source archive was
deleted after signature and hash verification plus successful installation.

Do not install an unpinned App Store build and do not upgrade to Tahoe to
satisfy the current App Store listing.
