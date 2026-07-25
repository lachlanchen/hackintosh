# Development Host Bootstrap

Status date: 2026-07-26

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
| Python | 3.12.13, selected in login shells |
| OpenJDK | 21.0.12, selected through `JAVA_HOME` |
| Node.js / npm | 22.23.1 / 10.9.8 through NVM |
| Codex CLI | 0.145.0 |
| GitHub CLI | 2.96.0 |
| tmux | 3.7b |
| Android SDK | API 35; build-tools 34.0.0 and 35.0.0 |
| ADB / `scrcpy` | platform-tools 37.0.0 / `scrcpy` 4.1 |

Homebrew analytics are disabled. The Homebrew shell environment is loaded from
the user's `.zprofile`; the local Codex CLI path remains available, while
Homebrew Python 3.12, OpenJDK 21, and the per-user Android SDK are selected
explicitly.

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

## Android And Backend Validation

The lean Android setup uses Homebrew command-line tools and a per-user SDK at
`~/Library/Android/sdk`; Android Studio and a second emulator image are not
required for command-line builds. The verified installed packages are:

```text
build-tools;34.0.0
build-tools;35.0.0
platform-tools 37.0.0
platforms;android-35
```

The first native Mac validation completed with:

```bash
cd ~/Projects/GlassAgent/Glass/apps/lightmind-android
./gradlew --no-daemon testDebugUnitTest assembleDebug
```

Both app modules passed their unit-test and debug-assembly tasks. The isolated
backend environment is:

```text
~/Library/Application Support/GlassAgent/venvs/lightmind-backend
```

All 167 backend tests passed with Python 3.12.13. The same host also passed all
45 PWA checks and all 27 root Toolchains tests. Build outputs, Gradle caches,
SDK packages, and the virtual environment remain local and outside Git.

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
