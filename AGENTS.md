# Hackintosh Reference Agent Guide

## Scope

This repository contains sanitized engineering notes and read-only diagnostics
for an owned development workstation. It does not contain a distributable EFI,
Apple software, firmware images, machine identity, or credentials.

## Safety

- Keep the known-good Monterey volume bootable and unchanged.
- Treat Sequoia as the development and experiment volume.
- Preserve a byte-verifiable EFI backup before any bootloader change.
- Make one boot-critical change at a time and validate it before continuing.
- Never erase, repartition, flash firmware, reset NVRAM, or alter Windows boot
  data without a verified recovery path and an explicit operator decision.
- Do not install Tahoe from System Settings. This runbook is validated only for
  Sequoia 15.7.7.
- Do not apply OCLP graphics root patches on this Hackintosh. Skylake graphics
  use the documented WhateverGreen Kaby Lake identity instead.

## Privacy

- Never commit EFI folders, `config.plist`, serials, MLB/ROM/SystemUUID values,
  MAC addresses, host keys, IP addresses, passwords, cookies, Apple account
  state, raw panic blobs, or signing assets.
- Keep machine-specific backups in ignored private storage.
- Redact identifiers before adding diagnostic excerpts.

## Documentation

- Mark claims as verified, inferred, proposed, or failed.
- Include dates and primary source links for changing compatibility facts.
- Update `docs/00-current-state.md` after every successful boot-critical change.
- Update the recovery runbook before removing any working fallback.

