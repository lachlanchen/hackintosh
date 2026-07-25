# Decode `aapl,panic-info`

Intel macOS panic text stored in NVRAM is not normal compression. XNU's `packA`
routine packs eight 7-bit characters into seven bytes. A raw NVRAM dump
therefore looks binary even though it contains a text panic.

## Extract and Decode on macOS

```bash
nvram -x -p |
  plutil -extract 'aapl,panic-info' raw -o - - |
  base64 -D |
  ./scripts/decode-apple-panic.pl
```

On Linux, use `base64 -d` instead of `base64 -D`.

The decoder reads seven bytes as one little-endian 56-bit word, then emits
eight characters from successive 7-bit fields.

## Preserve Before Clearing

Do not clear NVRAM before decoding the panic. Save only a private copy because
panic logs can contain memory addresses, user paths, hardware identifiers, and
boot arguments. Commit only a sanitized headline and relevant symbols.

## Failure Captured During This Upgrade

```text
assertmsg @AppleIntelController.cpp:27500
AppleIntelSKLGraphicsFramebuffer
AppleIntelFramebufferController::getUnifiedMemorySize()
```

That evidence changed the repair strategy from repeated OCLP patch attempts to
the native WhateverGreen Kaby Lake identity.

