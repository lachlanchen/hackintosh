# Wireless, Bluetooth, and AirDrop

## Current Detection

Verified after USB insertion:

- Realtek USB Wi-Fi `0bda:8176`, exposed only as an 802.11n USB device
- UGREEN `2b89:8a11`, identifying as `UGREEN MIC-CM770 2.4G`, not Bluetooth HCI
- a Broadcom `BCM_4350C2` Bluetooth controller reports off with no active address
- no macOS Wi-Fi hardware port
- no `awdl0` interface

The Realtek adapter may support ordinary Wi-Fi through a third-party USB
driver, but it cannot provide Apple's AWDL interface. It therefore cannot
enable AirDrop, Handoff, or Continuity.

## Hardware Options

### AirDrop Priority

A BCM94360CD-based PCIe card, commonly sold as Fenvi FV-T919/T919, is the most
widely used desktop option. The package must include:

- Wi-Fi/BT card
- antennas
- matching full-height or low-profile bracket
- internal USB cable for the Bluetooth side

On Sonoma and Sequoia, legacy Broadcom wireless requires maintained patches.
That introduces a root/EFI maintenance obligation and should be tested only on
Sequoia with Monterey preserved.

### Ordinary Wi-Fi/Bluetooth Priority

Intel AX200/AX210 hardware with OpenIntelWireless can provide practical network
and Bluetooth support, but it does not provide complete AWDL services and is
not a reliable AirDrop solution.

### Lowest-Risk Transfer

Until the real Mac mini arrives, prefer Ethernet plus SMB, LocalSend, or another
LAN transfer tool. This avoids weakening Sequoia's sealed-system/update design
for a convenience feature.

## Acceptance Test for a Future Card

1. Device appears in PCI and USB inventory.
2. Wi-Fi hardware port appears in `networksetup`.
3. Bluetooth has a non-null address.
4. `awdl0` exists and becomes active.
5. AirDrop works both directions with a known-good Apple device.
6. Sleep/wake, cold boot, and OTA update behavior remain stable.

