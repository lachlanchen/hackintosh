# Skylake Graphics on Sequoia

## Problem

Apple supports Intel HD530 natively through Monterey, but macOS 13 and newer no
longer ship it as a supported graphics target. Sequoia initially booted with no
accelerated framebuffer.

## Failed Path

OCLP 2.4.1 selected the Intel Skylake and Monterey OpenCL root patch sets. The
patched system panicked during framebuffer initialization:

```text
panic: assertmsg @AppleIntelController.cpp:27500
AppleIntelSKLGraphicsFramebuffer
AppleIntelFramebufferController::getUnifiedMemorySize()
```

The standard 19 MiB stolen-memory and 9 MiB framebuffer-memory properties were
already present. The failure demonstrated that relying on OCLP's legacy
graphics root patch was the wrong integration boundary for this Hackintosh.
Dortania explicitly states that OCLP support is not provided for Hackintoshes.

## Working Path

WhateverGreen supports presenting Skylake graphics as the closest Kaby Lake
model on macOS 13 and newer.

For desktop HD530:

| Meaning | Value |
| --- | --- |
| Physical Skylake device | `0x1912` |
| Closest Kaby Lake device | `0x5912` |
| Kaby desktop platform ID | `0x59120000` |
| OpenCore data for platform ID | `00001259` |
| OpenCore data for device ID | `12590000` |

The existing framebuffer memory values remain:

```text
framebuffer-patch-enable = 01000000
framebuffer-stolenmem    = 00003001
framebuffer-fbmem        = 00009000
```

Because one EFI boots Monterey and Sequoia, `-igfxsklaskbl` is retained. The
configuration was tested on Monterey before Sequoia.

## Verification

```bash
system_profiler SPDisplaysDataType
kextstat | grep -E 'AppleIntelKBLGraphics|WhateverGreen'
ioreg -p IOService -n IGPU -r -l |
  grep -E 'AAPL,ig-platform-id|device-id|VRAM,totalMB'
```

The verified Sequoia result is:

- `AppleIntelKBLGraphics` 23.0.7
- `AppleIntelKBLGraphicsFramebuffer` 23.0.7
- 1536 MB dynamic VRAM
- Metal 3
- sealed system volume

## Performance Notes

The native Kaby driver path is preferable to a downgraded root-patched Skylake
stack because it keeps Apple's Sequoia graphics binaries, the sealed system
volume, and normal kernel collection behavior. Benchmarking should compare GUI
responsiveness, Metal compute, video decode, sleep/wake, and multi-display
behavior before adding optional performance properties such as RPS control.

