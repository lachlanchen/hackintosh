# Recovery Scripts

These helpers are intentionally narrow. They do not discover or modify a
machine's EFI automatically, do not contain machine identity, and do not reboot
an operating system.

## OpenCore config transactions

| Script | Host | Purpose |
| --- | --- | --- |
| `stage-opencore-config.sh` | macOS | Promote a candidate config with hash gates and rollback |
| `restore-opencore-config.sh` | macOS | Restore a known-good config with hash gates and rollback |
| `stage-opencore-config.ps1` | Windows | Promote a candidate through the Windows system EFI |
| `restore-opencore-config.ps1` | Windows | Restore a known-good config through the Windows system EFI |
| `verify-macos-installer.sh` | macOS | Verify a full installer without launching it |
| `surface-book-2-storage-reclaim.sh` | macOS | Audit, plan, or explicitly reclaim the verified Surface Book 2 Ubuntu layout |
| `build-optiplex-3040-efi.py` | Linux | Reproducibly build a private 3040 EFI and validate it with matching OpenCore |
| `stage-optiplex-3040-recovery.ps1` | Windows | Audit or stage the exact 3040 internal recovery partition and payload |
| `boot-optiplex-3040-opencore.ps1` | Windows | Create, audit, arm, or clear the 3040's separate one-time OpenCore BCD path |
| `bootstrap-optiplex-3040-macos.sh` | macOS | Enable key-only SSH and never-sleep behavior after Setup Assistant |
| `hackintosh-kvm.sh` | Linux | Prepare and operate an isolated Sequoia/OpenCore KVM runtime |
| `hackintosh-kvm-apple-services.sh` | Linux | Build, verify, disable, or re-enable one private KVM iServices identity |

## Z790 workstation KVM

`hackintosh-kvm.sh` keeps Apple media, writable firmware state, VM identity,
logs, and the sparse qcow2 disk outside Git. It refuses non-loopback console
bindings, verifies the pinned OSX-KVM/OpenCore/OVMF inputs, and never attaches
a physical disk or GPU.

The companion `hackintosh-kvm.service` is a manual systemd user unit. Link it,
but do not enable it at boot:

```bash
./scripts/hackintosh-kvm.sh install-service
./scripts/hackintosh-kvm.sh verify
./scripts/hackintosh-kvm.sh start
```

See
[`docs/24-z790-kvm-sequoia.md`](../docs/24-z790-kvm-sequoia.md)
for the storage, memory, installation, console, and recovery boundary.

After installation, prepare the Apple-services identity only with the VM
stopped:

```bash
./scripts/hackintosh-kvm.sh apple-services
./scripts/hackintosh-kvm-apple-services.sh verify
```

The helper generates identity values once and refuses to rotate a valid set.
It keeps the config, EFI image, identity, manifest, and original-state backup
outside Git. The source OpenCore image remains hash-pinned and unchanged.
New identities include the two exact, length-preserving Sequoia DeviceCheck
kernel patches documented in the KVM runbook. They are restricted to Darwin
24 and validated with `Count = 1`.

For an existing private identity created before this support was added, stop
the VM and use the idempotent refresh path:

```bash
./scripts/hackintosh-kvm-apple-services.sh refresh
./scripts/hackintosh-kvm-apple-services.sh verify
```

`refresh` preserves an owner-only pre-patch config, EFI, and manifest; rebuilds
and round-trips the private EFI; checks the qcow2 and hashes; and does not
rotate any identity value. The main launcher also persists a separate private
QEMU `vmgenid` value so ordinary guest boots do not invent a new generation
identity.

`rollback` selects that source image and restores the prior QEMU identity on
the next launch; `enable` selects the validated private image again. Neither
operation resets NVRAM or runs while QEMU owns the guest disk.

The macOS scripts require an explicit EFI device. Example shape:

```bash
sudo ./scripts/stage-opencore-config.sh \
  <efi-device> \
  /private/path/to/candidate.plist \
  <candidate-sha256> \
  <current-live-sha256> \
  config.plist.known-good \
  config.plist.before-candidate
```

Restore shape:

```bash
sudo ./scripts/restore-opencore-config.sh \
  <efi-device> \
  <current-candidate-sha256> \
  <known-good-sha256> \
  config.plist.known-good \
  config.plist.used-candidate
```

The PowerShell scripts mount the Windows **system EFI partition** with
`mountvol /S`. This is appropriate only when that partition contains the
intended `EFI\OC\OpenCore.efi` and live `config.plist`. The expected live hash
is a second guard against selecting the wrong EFI, not a substitute for
checking the disk layout.

Run PowerShell from an elevated console:

```powershell
.\scripts\stage-opencore-config.ps1 `
  -SourceConfig C:\Private\candidate.plist `
  -ExpectedSourceSha256 <candidate-sha256> `
  -ExpectedLiveSha256 <current-live-sha256> `
  -BackupName config.plist.known-good `
  -PreservedLiveName config.plist.before-candidate
```

## Refusal behavior

The transaction helpers stop without promotion when:

- a hash is malformed or unexpected;
- a source, live, backup, or OpenCore binary is missing;
- a rollback filename is unsafe or already exists;
- the candidate changes during staging;
- the target does not look like an OpenCore EFI;
- final verification fails.

When final verification fails, the prior live config is moved back into place.
The script unmounts an EFI only when it mounted that EFI itself.

## Full-installer verification

Verify the exact target version and build before any installation:

```bash
./scripts/verify-macos-installer.sh \
  "/Applications/Install macOS Sequoia.app" \
  15.7.7 \
  24G720
```

The script mounts `SharedSupport.dmg` read-only and detaches it on exit. It
requires the expected version/build in internal MobileAsset metadata, verifies
the complete disk image and critical Apple executables, records the payload
SHA-256, and prints the installer's real `startosinstall --usage`.

Some Apple InstallAssistant wrappers use obsolete custom resource-envelope
rules and fail whole-app strict verification. The script reports that result
but still requires the independent disk-image, metadata, and critical-binary
checks. It never re-signs or modifies Apple's installer.

## Surface Book 2 storage reclaim

The Surface Book 2 helper is read-only in its normal modes:

```bash
sudo ./scripts/surface-book-2-storage-reclaim.sh audit disk0
sudo ./scripts/surface-book-2-storage-reclaim.sh plan disk0
```

It is intentionally locked to the exact verified geometry and signatures
documented in
[`docs/16-surface-book-2-storage-and-picker.md`](../docs/16-surface-book-2-storage-and-picker.md).
It detects that the misleadingly APFS-typed 98.7 GB partition and the later
131.4 GB Linux partition are both members of `vg-ubuntu`.

Its explicit `apply` mode permanently destroys Ubuntu. Before doing so, it
requires AC power, the current Sequoia APFS store, unchanged EFI and Windows
identities, a new absolute metadata-backup directory, and two matching
confirmations. It can add only the adjacent 98.7 GB to macOS; space behind
Windows remains free for a later separate decision.

## OptiPlex 3040 recovery staging

Read
[`docs/12-optiplex-3040-adaptation.md`](../docs/12-optiplex-3040-adaptation.md)
before using these machine-locked helpers. They are intentionally not generic
partitioning tools.

`build-optiplex-3040-efi.py` requires an extracted OpenCore release and exactly
the seven named kext sources. It generates the Apple-format identity only when
the private identity file is absent, reuses that identity on every later
build, emits a SHA-256 manifest named after the output directory, and refuses
any `ocvalidate` issue. Run `--help` for the complete arguments.

Copy the private EFI, Apple recovery folder, and macOS bootstrap into one
private Windows payload directory. Audit before apply:

```powershell
.\stage-optiplex-3040-recovery.ps1 `
  -Mode Audit `
  -PayloadPath C:\Private\3040\payload `
  -BackupDirectory C:\Private\3040\backups
```

Apply mode is locked to the audited Dell model, two disk models, `G:` offset,
and either the exact pre-stage or resumable intermediate geometry. It saves
GPT and BCD evidence before writing. It can only shrink the end of `G:` by
4 GiB, create the expected ESP, and hash-verify the copied tree. It does not
alter boot order or reboot:

```powershell
.\stage-optiplex-3040-recovery.ps1 `
  -Mode Apply `
  -PayloadPath C:\Private\3040\payload `
  -BackupDirectory C:\Private\3040\backups
```

Create and inspect the BCD entry separately. `Create` does not arm or reboot:

```powershell
.\boot-optiplex-3040-opencore.ps1 `
  -Mode Create `
  -StateDirectory C:\Private\3040\state

.\boot-optiplex-3040-opencore.ps1 `
  -Mode Audit `
  -StateDirectory C:\Private\3040\state
```

Only with a physical display and keyboard ready, use `-Mode Arm`, independently
inspect `{bootmgr}`, and then restart. `Arm` selects OpenCore once; it does not
request the restart. `Clear` removes only that pending one-time sequence.

After Setup Assistant creates `lachlan`, run the staged macOS bootstrap and
enter the administrator password once:

```bash
./bootstrap-optiplex-3040-macos.sh ./authorized_key.pub
```

The bootstrap refuses another OS or user, installs only the supplied Ed25519
public key, enables Remote Login, sets the 3040 hostname, disables sleep, and
prints its final SSH and power state. It does not create an account or store a
password.

## Validation

Before committing changes:

```bash
bash -n scripts/*.sh
git diff --check
```

The Bash helpers are kept compatible with the Bash 3.2 shipped by Sonoma and
were syntax-checked there without mounting or changing an EFI. Both PowerShell
helpers were parsed successfully by Windows PowerShell 5.1 without mounting or
changing an EFI.

## Other scripts

- `audit-macos.sh` captures a read-only OS, APFS, graphics, network, developer
  tool, and power baseline.
- `decode-apple-panic.pl` decodes packed panic data preserved from NVRAM.

Read the matching recovery document before running any write-capable helper.
