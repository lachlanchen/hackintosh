# Z790 Workstation macOS KVM Profile

Status date: 2026-08-29

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

This verifies that the local DeviceCheck path changed successfully, but Apple
Account sign-in is **not yet complete**. The remaining observed failure is at
the supplied credential/account layer, not a broad guest network outage. Do
not rotate the private identity, reset NVRAM, or automate retries for this
result. Confirm the exact account and password through an Apple-supported path
before one further attempt. A locally coherent identity cannot override an
incorrect credential or an Apple-side account restriction.

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
http://127.0.0.1:6141/vnc.html?autoconnect=1&resize=scale&quality=6&compression=2
```

For a remote client, tunnel it first rather than exposing noVNC:

```bash
ssh -L 6141:127.0.0.1:6141 lachlan@ubuntu-host
```

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
