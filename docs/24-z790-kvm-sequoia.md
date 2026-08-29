# Z790 Workstation macOS KVM Profile

Status date: 2026-08-29

This is a separate virtual-machine profile for the Ubuntu workstation. It does
not replace or modify the physical OptiPlex and Surface Hackintosh records in
this repository.

## Outcome and boundary

The selected target is **macOS Sequoia**, not Tahoe. The repository's tested
maintenance boundary is Sequoia 15.7.7, while Tahoe remains outside that
boundary. The recovery image is downloaded directly from Apple's catalog and
verified by Apple's chunklist through the audited OSX-KVM fetcher. The image
used on 2026-08-29 identifies itself as Sequoia 15.4.1 (`24E263`); updating the
installed guest to 15.7.7 is a later, separate checkpoint.

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

On 2026-08-29 the Apple-verified Sequoia 15.4.1 recovery completed both
installation stages and booted the installed virtual disk into Setup
Assistant. The run stopped at **Select Your Country or Region**: installation
is complete, while region, keyboard, Apple ID, migration, and local-account
choices remain intentionally user-owned.

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
UUID and MAC address, QMP socket, PIDs, and an asset manifest. None belongs in
Git. The OpenCore image is attached with QEMU snapshot mode so the audited
source image remains unchanged.

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
- `systemd-analyze --user verify scripts/hackintosh-kvm.service`
- `./scripts/hackintosh-kvm.sh verify`
- confirm ports 2224, 5941, and 6141 are loopback-only
- confirm the 512 GB image remains sparse with `qemu-img info` and `du`
- confirm no physical `/dev/*` disk or VFIO device appears in the QEMU command
- keep recovery media, Apple software, identities, logs, and images outside Git

## Compatibility conclusion

Sequoia is appropriate for this software-rendered VM. Tahoe can be fetched by
current OSX-KVM and OpenCore has Tahoe-related compatibility work, but that is
not equivalent to a tested workstation profile. Validate Sequoia first and
clone the qcow2 before any future Tahoe experiment.
