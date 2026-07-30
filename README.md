[English](README.md) · [العربية](i18n/README.ar.md) · [Español](i18n/README.es.md) · [Français](i18n/README.fr.md) · [日本語](i18n/README.ja.md) · [한국어](i18n/README.ko.md) · [Tiếng Việt](i18n/README.vi.md) · [中文 (简体)](i18n/README.zh-Hans.md) · [中文（繁體）](i18n/README.zh-Hant.md) · [Deutsch](i18n/README.de.md) · [Русский](i18n/README.ru.md)

# Hackintosh Sequoia Recovery Lab

Private operator reference for a Dell OptiPlex 7050 dual-boot development
workstation upgraded from macOS Monterey to macOS Sequoia without sacrificing
the working Monterey recovery system.

> This is an unsupported configuration. Apple licenses macOS and Xcode for
> Apple-branded hardware. The repository documents interoperability and
> recovery work on an owned machine; it does not include Apple software,
> proprietary firmware, or a ready-to-use EFI.

## Verified Result

| Area | Verified state on 2026-07-25 |
| --- | --- |
| Recovery OS | Monterey 12.7.6 (`21H1320`), preserved and bootable |
| Development OS | Sequoia 15.7.7 (`24G720`), sealed system volume |
| Bootloader | OpenCore 1.0.7 |
| CPU / GPU | Intel i5-6500 / HD Graphics 530 |
| Graphics path | HD530 presented as Kaby Lake HD630 through WhateverGreen |
| Acceleration | 1536 MB dynamic VRAM, Apple Kaby Lake driver, Metal 3 |
| Storage | Monterey and Sequoia share one APFS container dynamically |
| Network | Intel Ethernet verified; AirDrop unavailable without AWDL Wi-Fi |
| iOS toolchain | Xcode 26.3, iOS 26.3.1 runtime, signed archive/export verified |
| Updates | Manual installation only; Tahoe is outside the validated boundary |

The decisive fix was to avoid OCLP graphics root patching on the Hackintosh.
The HD530 is instead identified as Kaby Lake device `0x5912`, allowing Sequoia
to use its native Apple Kaby Lake graphics driver.

## Documentation

| Document | Purpose |
| --- | --- |
| [Current state](docs/00-current-state.md) | Exact verified operating boundary |
| [Upgrade chronology](docs/01-upgrade-chronology.md) | Work from first audit to stable Sequoia |
| [Recovery runbook](docs/02-recovery-runbook.md) | How to recover from a failed boot |
| [OpenCore design](docs/03-opencore-design.md) | Bootloader, kext, and policy decisions |
| [Skylake graphics](docs/04-skylake-graphics.md) | Panic analysis and native-driver fix |
| [Storage and dual boot](docs/05-storage-and-dual-boot.md) | APFS clone and Windows boundaries |
| [Xcode development](docs/06-xcode-development.md) | Pinned development toolchain |
| [Wireless and AirDrop](docs/07-wireless-and-airdrop.md) | Current limitation and hardware options |
| [Update policy](docs/08-update-policy.md) | Safe maintenance checkpoints |
| [Panic decoding](docs/09-panic-decoding.md) | Decode packed `aapl,panic-info` |
| [Development host bootstrap](docs/10-development-host-bootstrap.md) | Package and project-tool setup |
| [Remote access](docs/11-remote-access.md) | LAN SSH, Screen Sharing, and RDP boundaries |
| [OptiPlex 3040 adaptation](docs/12-optiplex-3040-adaptation.md) | Hardware-first process for a second machine |
| [Surface Book 2 Sequoia readiness](docs/13-surface-book-2-sequoia-readiness.md) | Sanitized audit, unattended-boot finding, and safe upgrade boundary |
| [Surface Book 2 upgrade runbook](docs/14-surface-book-2-upgrade-runbook.md) | Recovery-first boot routing, APFS layout, input patch, tools, and validation |
| [Surface Book 2 Sequoia result](docs/15-surface-book-2-sequoia-upgrade-result.md) | Completed in-place upgrade, installer behavior, and post-reboot validation |
| [Surface Book 2 storage and picker](docs/16-surface-book-2-storage-and-picker.md) | Verified Ubuntu LVM topology, clean picker policy, and guarded future reclaim |
| [Surface Book 2 space audit](docs/17-surface-book-2-space-audit.md) | Ranked, non-destructive cleanup and external-storage plan |
| [Dell BIOS updates](docs/18-dell-bios-update.md) | Guarded firmware inventory, update, and recovery workflow |
| [OptiPlex 3040 Monterey freeze handoff](docs/20-optiplex-3040-monterey-freeze-handoff.md) | Framebuffer evidence, failed handoff recovery, reversible picker cleanup, and CLI fallback |
| [Sources](docs/sources.md) | Primary documentation used |

## Repository Boundary

This repository intentionally excludes:

- EFI binaries and machine-specific `config.plist`
- SMBIOS serial, MLB, ROM, SystemUUID, host keys, and network addresses
- macOS/Xcode installers and OCLP payloads
- credentials, cookies, signing certificates, and Apple account state
- raw panic, diagnostic, and unified-log data

Read-only diagnostics and identity-free, hash-gated recovery transactions live
in [`scripts/`](scripts/README.md). Machine-specific recovery artifacts remain
in encrypted or ignored local storage.

## Support

| GitHub Sponsors | Donate | PayPal | Stripe |
| --- | --- | --- | --- |
| [Sponsor Lachlan Chen](https://github.com/sponsors/lachlanchen) | [LazyingArt support](https://chat.lazying.art/donate) | [PayPal](https://paypal.me/RongzhouChen) | [Stripe](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

Build less. Recover deliberately.
