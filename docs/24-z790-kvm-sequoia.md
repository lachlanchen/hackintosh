# Z790 Workstation macOS KVM Profile

Status date: 2026-08-30

This is a separate virtual-machine profile for the Ubuntu workstation. It does
not replace or modify the physical OptiPlex and Surface Hackintosh records in
this repository.

## Outcome and boundary

The selected target is **macOS Sequoia**, not Tahoe. The recovery image is
downloaded directly from Apple's catalog and verified by Apple's chunklist
through the audited OSX-KVM fetcher. The recovery environment used on
2026-08-29 identifies itself as Sequoia 15.4.1 (`24E263`), but the online
installer delivered Sequoia 15.7.9 (`24G830`). Apple identifies 15.7.9 as a
security update recommended for Sequoia users. There is no reason to downgrade
this guest to the earlier 15.7.7 checkpoint.

This is an unsupported interoperability experiment. Apple's Sequoia license
restricts macOS virtualization to Apple-branded computers. The profile is
documented for reproducibility and does not make the host Apple-supported.

The profile deliberately does not:

- pass through a physical disk, GPU, USB controller, or host EFI;
- change the Ubuntu bootloader, firmware, CPU-core policy, or NVIDIA setup;
- create a TAP bridge or alter host/router firewall rules;
- expose VNC, noVNC, or guest SSH beyond host loopback;
- start automatically at boot.

## Verified installation result

On 2026-08-29 the Apple-verified recovery completed both installation stages
and booted the installed virtual disk into Setup Assistant. Setup Assistant
was completed and `sw_vers` verified Sequoia 15.7.9 (`24G830`). Apple Account
sign-in initially returned **Verification Failed — An unknown error occurred**;
the evidence and repair boundary are recorded below.

The first stage downloaded and prepared the system in Recovery, then OpenCore
automatically selected the installer volume after reboot. The second stage
completed without a manual boot-picker intervention and reached Setup
Assistant. The private qcow2 had a 512 GiB virtual capacity and 32.8 GiB of
physical allocation at that checkpoint. The QEMU/noVNC service remained
active, all three forwarded listeners remained bound to `127.0.0.1`, and the
host retained roughly 77 GiB of available memory.

## Verified host audit

| Area | Observed state | Decision |
| --- | --- | --- |
| Host | Ubuntu 24.04.4 LTS, Linux 6.8, Intel Core i9-14900K | KVM acceleration is available through `/dev/kvm` |
| Memory | 128 GB physical RAM | Guest defaults to a 16 GiB ceiling |
| VM storage | SATA-mounted ext4 filesystem at `/home/lachlan/UbuntuSDA` | Keep all large/private runtime files here |
| Graphics | Intel UHD 770 and two NVIDIA RTX 4090 cards | Do not pass through any host GPU |
| Display | QEMU `vmware-svga` | Functional framebuffer only; no Metal acceleration |
| QEMU | Ubuntu QEMU 8.2.2 | Meets current OSX-KVM requirements |
| OpenCore source | OSX-KVM commit `4c378a4b5e0b219783683012bec680325eb40719` | Pinned and hash-verified before launch |

Neither graphics option is a viable modern macOS passthrough target. Dortania
lists Ada Lovelace/NVIDIA RTX 4090 as unsupported by every macOS release and
lists Raptor Lake UHD 770 as unsupported. The virtual display is therefore a
stability choice, not a performance path.

## Storage and memory semantics

The private default runtime is:

```text
/home/lachlan/UbuntuSDA/VirtualMachines/Hackintosh-KVM
```

The macOS disk has a **512 GB virtual capacity** but is qcow2 with
`preallocation=off`. It consumes only metadata initially and grows as blocks
are written. `qemu-img info` and `du` show virtual versus physical usage.

Memory is subtly different. The guest sees a fixed 16 GiB ceiling for one
launch. QEMU's `memory-backend-ram` uses `prealloc=off`, so RAM is physically
backed on demand, but macOS does not provide a dependable balloon/hotplug path
for this profile. Change the next launch without editing files:

```bash
HACKINTOSH_KVM_RAM_GIB=24 ./scripts/hackintosh-kvm.sh run
```

That is configurable, demand-backed memory—not automatic guest RAM resizing.

## Private layout

The Git repository contains only scripts and notes. Runtime state stays on the
SATA disk:

```text
Hackintosh-KVM/
├── disks/macOS-Sequoia.qcow2
├── installer/BaseSystem.img
├── installer/com.apple.recovery.boot/
├── logs/
├── state/
└── upstream/OSX-KVM/
```

The private `state/` directory contains writable OVMF NVRAM, a generated VM
UUID and MAC address, a separately generated stable VM generation ID, QMP
socket, PIDs, and an asset manifest. None belongs in Git. The OpenCore image is
attached with QEMU snapshot mode so the audited source image remains unchanged.

## Apple Account identity repair

The initial Apple Account failure exposed two concrete local defects:

- the audited OSX-KVM template still contained its public placeholder serial,
  MLB, all-zero SystemUUID, and fixed example ROM;
- macOS exposed the working Ethernet service as `en0`, but `ioreg` found no
  `built-in` property. QEMU's live PCI topology placed `net0` at
  `PciRoot(0x0)/Pci(0x4,0x0)`, a path absent from the template properties.

Dortania's iServices guidance requires a coherent SystemProductName, serial,
MLB, SystemUUID, ROM, and built-in `en0`. The repair therefore keeps
`iMac19,1`, generates one private serial pair with the official OpenCore 1.0.7
`macserial`, synchronizes the ROM with a stable Apple-OUI QEMU MAC, uses one
SystemUUID for both QEMU and OpenCore, and injects `built-in = 01` at the
observed PCI path.

Run this only while the guest is stopped:

```bash
./scripts/hackintosh-kvm.sh apple-services
./scripts/hackintosh-kvm-apple-services.sh verify
```

The builder is intentionally idempotent: once its private identity validates,
another `prepare` refuses to rotate it. It validates the plist with the
matching OpenCore 1.0.7 `ocvalidate`, round-trips the config through the EFI
filesystem, checks the rebuilt qcow2, and records only hashes and non-secret
metadata in a private manifest. Serial, MLB, ROM, UUID, MAC, config, EFI image,
and pre-change OVMF backup remain mode `0600` under the private SATA runtime.

The original hash-pinned OpenCore image is never modified. A complete stopped
guest-disk copy named for the 15.7.9 pre-repair checkpoint supplies the data
rollback. For an OpenCore identity rollback, stop the guest and run:

```bash
./scripts/hackintosh-kvm-apple-services.sh rollback
```

That preserves the private image, restores the prior QEMU MAC/UUID, and makes
the launcher select the audited template on the next boot. Re-enable the
validated private identity with `enable`, again only while stopped. No NVRAM
reset was performed during the verified repair.

The first retry with the repaired identity still failed. Unified AuthKit logs
then narrowed the next fault precisely:

- `en0` was the default route and reported `IOBuiltin = Yes`;
- Apple's OpenID endpoint returned HTTP 200 and the guest clock was correct;
- `akd` failed Anisette/device provisioning with `ADIGetIDMSRouting -45061`,
  `AKAnisetteError -8008`, and BAA attestation `-10000`;
- the provisioning-start request succeeded, but provisioning-finish returned
  HTTP 401 and surfaced as the generic verification dialog.

This evidence rules out DNS, routing, and a missing built-in Ethernet property.
It does not prove an Apple-side account ban: a stale first-boot AuthKit cache,
an incorrectly entered account name, or rejected attestation can produce the
same user-facing dialog. The small `~/Library/Caches/com.apple.akd` directory
was therefore archived privately, removed, and allowed to regenerate during a
clean guest reboot. No account database, keychain, or OpenCore NVRAM was
deleted. That cache refresh alone did not clear the DeviceCheck failure.

### Sequoia DeviceCheck compatibility patch

The next change was boot-critical and was made only after preserving the
working private OpenCore image and config. The two exact, length-preserving
kernel cstring swaps were audited from
[`osx-proxmox-next` v0.31.2 at commit `0f5a16a`](https://github.com/lucid-fabrics/osx-proxmox-next/tree/0f5a16ad1e294f6d4c0c67e976be323fd3a13eb5).
Before applying them, each source byte sequence was verified to occur exactly
once in the installed Sequoia kernel. OpenCore constrains both patches to
Darwin 24 (`24.0.0` through `24.99.99`) with `Count = 1`; they are not enabled
for Sonoma, Tahoe, or an unknown future kernel.

The pair swaps the names exposed by the real `hv_vmm_present` and
`hibernatecount` kernel objects. After the clean reboot, the verified guest
reported `kern.hv_vmm_present = 0` and `kern.hibernatecount = 1`. This removed
the earlier BAA provisioning failure from the observed authentication path.
It remains an unsupported compatibility patch, not Apple support for a KVM
guest.

Existing private identities can be upgraded only while the guest is stopped:

```bash
./scripts/hackintosh-kvm-apple-services.sh refresh
./scripts/hackintosh-kvm-apple-services.sh verify
```

`refresh` refuses a running VM, validates the current private identity first,
keeps one owner-only pre-patch config/EFI/manifest backup, rebuilds and
round-trips the EFI, runs the matching `ocvalidate`, checks both config and
image hashes, and does not rotate serial, MLB, ROM, MAC, or SystemUUID. New
identities receive the same scoped patches during `prepare`.

The launcher also now creates one stable private `vm-generation-id` and passes
it through QEMU's `vmgenid` device on every boot. It is generated once, format
validated, stored mode `0600`, and is independent of the OpenCore identity.

### Verified post-patch authentication boundary

A single post-patch retry used a visibly verified account field and the
expected masked password character count. The result was different from the
pre-patch DeviceCheck failure:

- DNS, IPv4/IPv6 path selection, TCP, and TLS 1.3 succeeded on `en0`;
- `akd` sent the request and received HTTP 200;
- the earlier Anisette `-8008`, BAA `-10000`, provisioning-finish HTTP 401,
  and server `-22410` evidence did not recur in this attempt;
- SRP authentication then failed with `AKAuthenticationServerError -20101`,
  and the UI reported that the Apple Account or password was incorrect;
- no 2FA prompt was reached and the rejected password was cleared from the
  visible form afterward.

This verified that the local DeviceCheck path changed successfully, but sign-in
was not complete at that checkpoint. The operator subsequently completed the
Apple Account login manually. An authenticated App Store purchase and download
of Xcode 26.3 then independently verified the Media & Purchases path. This does
not claim that every iCloud service was exercised. The lesson remains the same:
do not rotate the private identity, reset NVRAM, or automate credential retries
after a credential-layer rejection.

## Xcode 26.3 and a storage-scoped Apple SDK workstation

Apple's current App Store listing offered Xcode 26.6, which cannot run on
Sequoia. Apple's compatibility table instead identifies Xcode 26.3 as the last
release supported on Sequoia 15.6 or later. The App Store's **Download an older
version** path therefore selected Xcode 26.3 (`17C529`).

The 2.93 GB download completed repeatedly, but installation failed
deterministically. `installd` crashed with `EXC_BAD_ACCESS`/`SIGSEGV` inside
PackageKit while
`actualFileInstallPathsViolatingReadOnlySystemLocationsEvaluatingDestinationPath`
enumerated the Xcode package. App Store surfaced that crash only as
`PKInstallErrorDomain Code=200`, “An error occurred connecting to the
installation service.” Free space exceeded 500 GB at the check, the package
download completed, App Store authentication succeeded, and the same stack
recurred through both `mas` and the native App Store. This was therefore a
PackageKit analyzer defect in this guest, not a disk, account, or download
failure.

The successful fallback retained the authenticated App Store package before
PackageKit removed its temporary directory. While `mas install 497799835` was
downloading, a root shell hard-linked the package and its small receipt from
the current user's App Store cache into an owner-only capture directory. A
hard link did not duplicate the multi-gigabyte file blocks. After the expected
installer crash, the retained package was a normal XAR archive rather than the
encrypted CDN object and passed:

```bash
pkgutil --check-signature Xcode-26.3-AppStore.pkg
shasum -a 256 Xcode-26.3-AppStore.pkg
```

`pkgutil` reported **signed by Apple for the App Store** with a trusted
timestamp. The retained package SHA-256 was
`89d9e6b90fead5da4b40fda0b26a8f32e2f9889fb0b2d9c594c3820c13b1af58`.
A direct unauthenticated CDN copy is not equivalent: that object remained
encrypted, was not a readable XAR/package, and was deleted.

The package itself was expanded without invoking the crashing installer. Its
payload is Apple's `pbzx` archive format, which Sequoia's own `aa` utility can
read:

```bash
pkgutil --expand Xcode-26.3-AppStore.pkg Xcode-26.3-expanded
mkdir -m 700 Xcode-26.3-staging
aa extract \
  -i Xcode-26.3-expanded/Xcode.pkg/Payload \
  -d Xcode-26.3-staging \
  -t 4 -wt 2 -enable-dedup -enable-holes

spctl --assess --type execute -vv \
  Xcode-26.3-staging/Applications/Xcode.app
codesign --verify --deep --strict --verbose=2 \
  Xcode-26.3-staging/Applications/Xcode.app
```

Gatekeeper accepted the result as a Mac App Store application with origin
**Apple Mac OS Application Signing**. Deep verification reported `valid on
disk` and `satisfies its Designated Requirement`. Only then was the bundle
moved atomically to `/Applications/Xcode.app`, selected, licensed, and prepared:

```bash
sudo mv Xcode-26.3-staging/Applications/Xcode.app /Applications/Xcode.app
sudo chown -R root:wheel /Applications/Xcode.app
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```

The verified result is Xcode 26.3 build `17C529`. `xcodebuild -showsdks`
confirms that the application already contains macOS 26.2, iOS 26.2, and
watchOS 26.2 device and simulator SDKs. SDKs must not be removed from inside
the signed application to save space. Separate simulator runtimes are managed
independently. This guest requests only the Intel-compatible universal iOS and
watchOS runtimes; it does not use `-downloadAllPlatforms` and does not download
tvOS or visionOS runtimes.

The two scoped runtimes were installed and registered with Apple's supported
command-line path:

```bash
xcodebuild -downloadPlatform iOS -architectureVariant universal
xcodebuild -downloadPlatform watchOS -architectureVariant universal
xcrun simctl list runtimes
```

The verified result is iOS 26.3.1 (`23D8133`) and watchOS 26.2 (`23S303`),
both advertising `x86_64` and `arm64` support. The Xcode bundle occupies about
11 GiB. The iOS runtime image and its Intel dyld cache occupy about 14.0 GiB;
the watchOS equivalents occupy about 7.5 GiB. Those caches are part of making
the universal runtimes executable on this Intel guest, not abandoned download
files. No Xcode, `.dmg`, or `.simruntime` artifact remained in Downloads, and
the guest retained about 448 GiB free after installation.

`xcrun swift` reported Swift 6.2.4, `xcrun clang` reported Apple Clang 17, and
a one-line Swift program executed successfully. `simctl` registration is
verified, but simulator boot and graphics performance are deliberately not
claimed: the guest uses a software framebuffer without Metal acceleration.
Use a physical Apple device for final performance-sensitive validation.

The package capture, expanded payload, and staging directories used 5,759,332
KiB and were deleted after the installed Xcode passed first-launch setup. They
contained only reproducible installer artifacts, not user data. The sparse VM
had about 467 GiB free before simulator runtime installation.

### iCloud local-storage boundary

iCloud Drive remains enabled, but `com.apple.bird` reports
`optimize-storage = 1`. The guest currently has zero locally downloaded iCloud
Drive files and a zero-size Photos library, so there was nothing to evict.
This preserves cloud access without spending guest disk space today.

Apple's supported action for a synchronized item is Finder's **Remove
Download**. Never use `rm` to make an iCloud item online-only: deleting a synced
item can remove it from iCloud and other devices. Optimize Mac Storage may keep
recent files locally when capacity is abundant; strict “never download” would
require disabling **Sync this Mac**, which was deliberately not done here.

## Guest login, power, wallpaper, and private access

The existing macOS account was retained; no duplicate user was created.
FileVault was already off, so automatic login could be enabled. Guest
credentials, the dedicated SSH private key, known-host entry, AuthKit log, and
cache backup are owner-only files under the private runtime `state/private/`
directory. They are excluded from Git and must never be copied into an issue,
commit, or public handoff.

The verified post-reboot state was:

- automatic login returned directly to the existing desktop and restored its
  open windows;
- `pmset` reported system sleep, display sleep, disk sleep, standby,
  hibernation, and Power Nap as zero/off;
- both screen-saver idle settings were zero;
- a static built-in wallpaper was applied from the logged-in GUI session;
- OpenSSH returned on host loopback port 2224 after reboot;
- OpenCore remembered `Macintosh HD` after selecting it once with
  Control+Enter at the picker.

`systemsetup -setremotelogin on` was not used because Sequoia requires Terminal
Full Disk Access for that command. Instead, the built-in
`/System/Library/LaunchDaemons/ssh.plist` was enabled and bootstrapped through
`launchctl`, and a dedicated key was installed. This avoids granting Terminal
broad disk access and leaves SSH reachable only through QEMU's loopback-only
forward.

Prefer the interactive command below for automatic login because `-password -`
keeps the secret out of shell history and process arguments:

```bash
sudo sysadminctl -autologin set -userName <short-name> -password -
```

On this guest, `sysadminctl` returned `SACSetAutoLoginPassword error:22` even
though the account password and secure token were valid. The fallback wrote
the standard loginwindow auto-login credential from the private password and
set `autoLoginUser`; `sysadminctl -autologin status` then verified the result.
That credential is reversible obfuscation, not encryption. Automatic login is
therefore convenient but intentionally weakens local-at-console security.

## Installation workflow

Install the Ubuntu-side dependencies:

```bash
sudo apt install qemu-system-x86 qemu-utils ovmf dmg2img \
  p7zip-full genisoimage swtpm novnc websockify
```

Create the private config at
`~/.config/hackintosh-kvm/config.env`:

```bash
RUNTIME_ROOT=/home/lachlan/UbuntuSDA/VirtualMachines/Hackintosh-KVM
RAM_GIB=16
DISK_SIZE=512G
CPU_CORES=4
CPU_THREADS=2
VNC_DISPLAY=41
NOVNC_PORT=6141
SSH_PORT=2224
```

The current runtime already contains the pinned upstream checkout. For a clean
reconstruction, clone OSX-KVM recursively into `upstream/OSX-KVM`, check out
the documented commit, and verify its submodules before fetching Apple media.

The helper passes the audited Sequoia board identifier, an anonymous MLB, and
`os-type=default` explicitly. It does not rely on OSX-KVM's `--shortname`
argument in `--action download` mode because upstream does not consume that
argument on that code path.

OSX-KVM's chunk verifier also asks the operating system for terminal width
without handling a non-interactive shell. The wrapper supplies a deterministic
80-column width under systemd/SSH and still executes the complete signed
chunklist verification; it does not bypass or weaken image validation.

Then run:

```bash
./scripts/hackintosh-kvm.sh fetch
./scripts/hackintosh-kvm.sh verify
./scripts/hackintosh-kvm.sh prepare-novnc
./scripts/hackintosh-kvm.sh install-service
./scripts/hackintosh-kvm.sh start
```

The service is linked but intentionally not enabled. This prevents a heavy VM
from consuming resources after an unattended host reboot.

The helper targets `/run/user/UID/bus` when talking to the user manager. This
avoids a multi-session desktop caveat where an XRDP shell's generic
`DBUS_SESSION_BUS_ADDRESS` points at a different session bus and plain
`systemctl --user` returns a misleading D-Bus error.

Open the private console from a browser running on the Ubuntu host:

```text
http://127.0.0.1:6141/vnc.html?autoconnect=1&resize=scale&quality=6&compression=2&layoutsafe=1
```

For a remote client, tunnel it first rather than exposing noVNC:

```bash
ssh -L 6141:127.0.0.1:6141 lachlan@ubuntu-host
```

### Layout-safe punctuation across nested JIS/US remote paths

The verified operator path can cross a Japanese MacBook keyboard or phone,
UU Remote, a Windows RDP client, Ubuntu X11, a browser, noVNC, QEMU, and
finally macOS. The active Ubuntu desktop correctly uses XKB `jp`, while QEMU
exposes a generic USB keyboard with country code zero and macOS uses its
ABC/U.S. layout. Ordinary letters share positions, but punctuation does not.
For example, JIS Shift+7 means apostrophe, while the same physical position in
the U.S. layout means ampersand.

QEMU's extended RFB key event sends the browser's physical keycode and assumes
the guest layout matches the client layout. Switching all of Ubuntu or macOS
to JIS would improve one controller while breaking the phone, Windows/US
keyboard, or another remote route. Disabling the extension and sending only
keysyms also failed a controlled test: QEMU selected the approximate U.S. key
position but did not synthesize the needed Shift state.

The scoped solution leaves every operating-system layout unchanged. A small
patch to noVNC 1.3.0 maps only printable ASCII punctuation from the intended
keysym to an explicit U.S. virtual-key chord before QEMU. If the source Shift
state differs, it is temporarily normalized, the punctuation chord is sent,
and held Shift keys are restored. Letters, navigation, CJK input methods, and
any key used with Control, Alt, or Command/Meta retain upstream handling.

The launcher verifies the exact upstream `rfb.js` hash, applies
[`novnc-1.3.0-layout-safe-keyboard.patch`](../patches/novnc-1.3.0-layout-safe-keyboard.patch)
to a private 1.2 MiB web root under ignored VM state, checks JavaScript syntax,
and promotes it atomically. It never edits `/usr/share/novnc`. Repeating
`prepare-novnc` is idempotent. If a later package update changes upstream
noVNC, the launcher retains the last verified private copy; if no such copy
exists, it falls back to upstream noVNC rather than blocking VM startup.

websockify serves from its process working directory. Regeneration therefore
retains any previous 1.2 MiB web root still held by a live proxy. Restart only
that proxy to activate the update; a later preparation removes the stale root
after it is no longer in use. QEMU and macOS do not need to restart.

The controlled acceptance string included letters plus:

```text
'@[]\;:/?=+-_!#$%^&*()
```

The full string was visually verified in TextEdit through both a direct RFB
prototype and the patched browser. A deliberately mismatched JIS event—source
`Shift+7`, intended apostrophe—arrived as apostrophe, and unshifted `@` plus
brackets also passed. The unsaved test document was closed, its project-owned
TextEdit process was stopped, and Safari was restored. No guest document or
global keyboard preference changed.

Append `layoutsafe=0` to the URL for immediate upstream behavior. This is a
rollback switch, not a second keyboard installation. Non-ASCII composition is
still the responsibility of the chosen macOS input method. For a credential
containing punctuation, clipboard paste over the private SSH/GUI boundary is
also safer than repeated login attempts through an unverified key path.

In macOS Recovery:

1. open Disk Utility;
2. show all devices;
3. select only the blank QEMU disk;
4. erase it as GUID/APFS and name it `Macintosh HD`;
5. install macOS to that virtual disk;
6. allow installer reboots and choose the macOS installer/disk in OpenCore
   until Setup Assistant appears.

In the verified run, OpenCore selected the correct installer target
automatically. Keep the console visible during future installs because that
default is useful evidence, not a guarantee for every NVRAM state.

Never select a host block device: none should be present in this profile.

## Operation and recovery

```bash
./scripts/hackintosh-kvm.sh status
./scripts/hackintosh-kvm.sh url
./scripts/hackintosh-kvm.sh stop
./scripts/hackintosh-kvm.sh logs
./scripts/hackintosh-kvm-apple-services.sh status
```

`stop` sends an ACPI power-button request over the private QMP socket. Use
`force-stop` only when the guest is unresponsive; it verifies the PID against
the exact private qcow2 path before sending `SIGTERM`.

The guest network uses QEMU user-mode NAT. After enabling Remote Login inside
macOS, guest port 22 is reachable only at `127.0.0.1:2224` on Ubuntu. The
profile adds no Layer-2 presence and cannot alter the router.

If boot fails with an explicit unhandled-MSR error, capture the QEMU log first.
Only then consider `kvm.ignore_msrs=1`; do not change host KVM policy merely
because an upstream sample suggests it.

## Reproducibility checklist

- `bash -n scripts/hackintosh-kvm.sh`
- `bash -n scripts/hackintosh-kvm-apple-services.sh`
- `systemd-analyze --user verify scripts/hackintosh-kvm.service`
- `./scripts/hackintosh-kvm.sh verify`
- `./scripts/hackintosh-kvm-apple-services.sh verify`
- confirm ports 2224, 5941, and 6141 are loopback-only
- confirm the 512 GB image remains sparse with `qemu-img info` and `du`
- confirm no physical `/dev/*` disk or VFIO device appears in the QEMU command
- keep recovery media, Apple software, identities, logs, and images outside Git

## Compatibility conclusion

Sequoia 15.7.9 is the verified software-rendered VM boundary. Tahoe can be
fetched by current OSX-KVM and OpenCore has Tahoe-related compatibility work,
but that is not equivalent to a tested workstation profile. Clone the stopped
qcow2 before any future Tahoe experiment.

Primary changing references:

- [Apple: macOS Sequoia 15.7.9 security content](https://support.apple.com/en-ca/148171)
- [Dortania: fixing iMessage and other services](https://dortania.github.io/OpenCore-Post-Install/universal/iservices.html)
- [OpenCorePkg releases](https://github.com/acidanthera/OpenCorePkg/releases)
- [Apple: Xcode system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Apple: work with iCloud Drive files](https://support.apple.com/guide/mac-help/-mchl1a02d711/mac)
- [Apple: optimize Mac storage](https://support.apple.com/guide/mac-help/optimize-storage-space-sysp4ee93ca4/mac)
- [noVNC API: physical `code` versus symbolic `keysym`](https://novnc.com/noVNC/docs/API.html)
- [QEMU extended key event protocol](https://github.com/TigerVNC/tigervnc/blob/master/doc/rfbproto.rst)
- [QEMU keycodemap database](https://github.com/qemu/keycodemapdb/blob/master/data/README)
