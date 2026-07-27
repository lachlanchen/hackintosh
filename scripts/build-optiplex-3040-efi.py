#!/usr/bin/env python3
"""Build a private, validated OpenCore EFI for the audited OptiPlex 3040."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import uuid
from pathlib import Path


APPLE_BOOT_GUID = "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102"
APPLE_NVRAM_GUID = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
MODEL = "iMac17,1"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build an OptiPlex 3040 Monterey/Sequoia EFI. Machine identity is "
            "stored outside the EFI and must remain private."
        )
    )
    parser.add_argument(
        "--opencore",
        required=True,
        type=Path,
        help="Extracted OpenCore release directory containing Docs and X64",
    )
    parser.add_argument(
        "--kext",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="Top-level kext source; supply each required kext once",
    )
    parser.add_argument("--output", required=True, type=Path, help="Output EFI directory")
    parser.add_argument(
        "--identity-file",
        required=True,
        type=Path,
        help="Private JSON identity file; generated once and reused",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing output directory, never the identity file",
    )
    return parser.parse_args()


def parse_kexts(values: list[str]) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"invalid --kext value: {value!r}")
        name, raw_path = value.split("=", 1)
        if not name.endswith(".kext") or not name:
            raise ValueError(f"kext name must end in .kext: {name!r}")
        path = Path(raw_path).expanduser().resolve()
        if name in result:
            raise ValueError(f"duplicate kext name: {name}")
        if not (path / "Contents" / "Info.plist").is_file():
            raise FileNotFoundError(f"invalid kext source for {name}: {path}")
        result[name] = path
    required = {
        "Lilu.kext",
        "VirtualSMC.kext",
        "SMCProcessor.kext",
        "WhateverGreen.kext",
        "AppleALC.kext",
        "RealtekRTL8111.kext",
        "RestrictEvents.kext",
    }
    missing = sorted(required - result.keys())
    extra = sorted(result.keys() - required)
    if missing or extra:
        raise ValueError(f"kext set mismatch; missing={missing}, unexpected={extra}")
    return result


def run_checked(command: list[str]) -> str:
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return result.stdout.strip()


def generate_identity(macserial: Path) -> dict[str, str]:
    output = run_checked([str(macserial), "-m", MODEL, "-n", "1"])
    match = re.search(r"^([A-Z0-9]+)\s+\|\s+([A-Z0-9]+)$", output, re.MULTILINE)
    if not match:
        raise RuntimeError(f"could not parse macserial output: {output!r}")
    rom = bytearray(secrets.token_bytes(6))
    rom[0] = (rom[0] | 0x02) & 0xFE
    return {
        "model": MODEL,
        "serial": match.group(1),
        "mlb": match.group(2),
        "system_uuid": str(uuid.uuid4()).upper(),
        "rom": rom.hex(),
    }


def load_or_create_identity(path: Path, macserial: Path) -> dict[str, str]:
    if path.exists():
        identity = json.loads(path.read_text(encoding="ascii"))
    else:
        identity = generate_identity(macserial)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".new")
        temporary.write_text(json.dumps(identity, indent=2) + "\n", encoding="ascii")
        os.chmod(temporary, 0o600)
        temporary.replace(path)
    expected = {"model", "serial", "mlb", "system_uuid", "rom"}
    if set(identity) != expected or identity["model"] != MODEL:
        raise ValueError(f"identity file has an unexpected schema or model: {path}")
    if not re.fullmatch(r"[0-9a-fA-F]{12}", identity["rom"]):
        raise ValueError(f"identity ROM must be six hexadecimal bytes: {path}")
    uuid.UUID(identity["system_uuid"])
    return identity


def copy_file(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def configure_values(target: dict, values: dict) -> None:
    unknown = sorted(values.keys() - target.keys())
    if unknown:
        raise KeyError(f"settings are absent from this OpenCore schema: {unknown}")
    target.update(values)


def kext_entry(bundle_path: str, kext_path: Path, comment: str) -> dict:
    info = plistlib.load((kext_path / "Contents" / "Info.plist").open("rb"))
    executable = info.get("CFBundleExecutable", "")
    executable_path = f"Contents/MacOS/{executable}" if executable else ""
    if executable_path and not (kext_path / executable_path).is_file():
        raise FileNotFoundError(f"{bundle_path}: missing {executable_path}")
    return {
        "Arch": "Any",
        "BundlePath": bundle_path,
        "Comment": comment,
        "Enabled": True,
        "ExecutablePath": executable_path,
        "MaxKernel": "",
        "MinKernel": "",
        "PlistPath": "Contents/Info.plist",
    }


def build_config(
    sample: Path,
    identity: dict[str, str],
    kext_paths: dict[str, Path],
) -> dict:
    with sample.open("rb") as stream:
        config = plistlib.load(stream)
    for key in [key for key in config if key.startswith("#WARNING")]:
        del config[key]

    config["ACPI"]["Add"] = [
        {
            "Comment": "Generic desktop EC and USB power device",
            "Enabled": True,
            "Path": "SSDT-EC-USBX.aml",
        },
        {
            "Comment": "Enable XCPM plugin-type on the detected processor path",
            "Enabled": True,
            "Path": "SSDT-PLUG.aml",
        },
    ]
    config["ACPI"]["Delete"] = []
    config["ACPI"]["Patch"] = []
    configure_values(
        config["ACPI"]["Quirks"],
        {
            "FadtEnableReset": False,
            "NormalizeHeaders": False,
            "RebaseRegions": False,
            "ResetHwSig": False,
            "ResetLogoStatus": True,
            "SyncTableIds": False,
        },
    )

    config["Booter"]["MmioWhitelist"] = []
    config["Booter"]["Patch"] = []
    configure_values(
        config["Booter"]["Quirks"],
        {
            "AllowRelocationBlock": False,
            "AvoidRuntimeDefrag": True,
            "DevirtualiseMmio": False,
            "DisableSingleUser": False,
            "DisableVariableWrite": False,
            "DiscardHibernateMap": False,
            "EnableSafeModeSlide": True,
            "EnableWriteUnprotector": True,
            "FixupAppleEfiImages": False,
            "ForceBooterSignature": False,
            "ForceExitBootServices": False,
            "ProtectMemoryRegions": False,
            "ProtectSecureBoot": False,
            "ProtectUefiServices": False,
            "ProvideCustomSlide": True,
            "ProvideMaxSlide": 0,
            "RebuildAppleMemoryMap": False,
            "ResizeAppleGpuBars": -1,
            "SetupVirtualMap": True,
            "SignalAppleOS": False,
            "SyncRuntimePermissions": True,
        },
    )

    config["DeviceProperties"]["Add"] = {
        "PciRoot(0x0)/Pci(0x2,0x0)": {
            "AAPL,ig-platform-id": bytes.fromhex("00001259"),
            "device-id": bytes.fromhex("12590000"),
            "device_type": "VGA compatible controller",
            "framebuffer-fbmem": bytes.fromhex("00009000"),
            "framebuffer-patch-enable": bytes.fromhex("01000000"),
            "framebuffer-stolenmem": bytes.fromhex("00003001"),
            "hda-gfx": "onboard-1",
        }
    }
    config["DeviceProperties"]["Delete"] = {}

    kext_order = [
        ("Lilu.kext", "Lilu patching framework"),
        ("VirtualSMC.kext", "Apple SMC emulation"),
        ("SMCProcessor.kext", "CPU sensor plugin"),
        ("WhateverGreen.kext", "Intel graphics support"),
        ("AppleALC.kext", "ALC255 audio support"),
        ("RealtekRTL8111.kext", "Realtek RTL8111 Ethernet"),
        ("RestrictEvents.kext", "Unsupported-model update compatibility"),
    ]
    config["Kernel"]["Add"] = [
        kext_entry(name, kext_paths[name], comment) for name, comment in kext_order
    ]
    config["Kernel"]["Block"] = []
    config["Kernel"]["Force"] = []
    config["Kernel"]["Patch"] = []
    configure_values(
        config["Kernel"]["Emulate"],
        {
            "Cpuid1Data": b"",
            "Cpuid1Mask": b"",
            "DummyPowerManagement": False,
            "MaxKernel": "",
            "MinKernel": "",
        },
    )
    configure_values(
        config["Kernel"]["Quirks"],
        {
            "AppleCpuPmCfgLock": False,
            "AppleXcpmCfgLock": True,
            "AppleXcpmExtraMsrs": False,
            "AppleXcpmForceBoost": False,
            "CustomSMBIOSGuid": True,
            "DisableIoMapper": True,
            "DisableLinkeditJettison": True,
            "DisableRtcChecksum": True,
            "ExtendBTFeatureFlags": False,
            "ExternalDiskIcons": False,
            "ForceAquantiaEthernet": False,
            "ForceSecureBootScheme": False,
            "IncreasePciBarSize": False,
            "LapicKernelPanic": False,
            "LegacyCommpage": False,
            "PanicNoKextDump": True,
            "PowerTimeoutKernelPanic": True,
            "ProvideCurrentCpuInfo": False,
            "SetApfsTrimTimeout": -1,
            "ThirdPartyDrives": False,
            "XhciPortLimit": False,
        },
    )
    config["Kernel"]["Scheme"]["KernelArch"] = "Auto"
    config["Kernel"]["Scheme"]["KernelCache"] = "Auto"

    config["Misc"]["BlessOverride"] = []
    config["Misc"]["Entries"] = []
    config["Misc"]["Tools"] = []
    configure_values(
        config["Misc"]["Boot"],
        {
            "ConsoleAttributes": 0,
            "HibernateMode": "None",
            "HibernateSkipsPicker": False,
            "HideAuxiliary": False,
            "InstanceIdentifier": "",
            "LauncherOption": "Disabled",
            "LauncherPath": "Default",
            "PickerAttributes": 1,
            "PickerAudioAssist": False,
            "PickerMode": "Builtin",
            "PickerVariant": "Auto",
            "PollAppleHotKeys": True,
            "ShowPicker": True,
            "TakeoffDelay": 0,
            "Timeout": 10,
        },
    )
    configure_values(
        config["Misc"]["Debug"],
        {
            "AppleDebug": True,
            "ApplePanic": True,
            "DisableWatchDog": True,
            "DisplayDelay": 0,
            "DisplayLevel": 2147483650,
            "LogModules": "*",
            "SysReport": False,
            "Target": 67,
        },
    )
    configure_values(
        config["Misc"]["Security"],
        {
            "AllowSetDefault": True,
            "ApECID": 0,
            "AuthRestart": False,
            "BlacklistAppleUpdate": True,
            "DmgLoading": "Signed",
            "EnablePassword": False,
            "ExposeSensitiveData": 6,
            "HaltLevel": 2147483648,
            "PasswordHash": b"",
            "PasswordSalt": b"",
            "ScanPolicy": 0,
            "SecureBootModel": "Disabled",
            "Vault": "Optional",
        },
    )
    configure_values(
        config["Misc"]["Serial"],
        {
            "Init": False,
            "Override": False,
        },
    )

    config["NVRAM"]["Add"] = {
        APPLE_BOOT_GUID: {
            "DefaultBackgroundColor": bytes.fromhex("00000000"),
            "UIScale": bytes.fromhex("FF"),
        },
        APPLE_NVRAM_GUID: {
            "boot-args": (
                "-v keepsyms=1 debug=0x100 alcid=11 "
                "-igfxsklaskbl -no_compat_check revpatch=sbvmm"
            ),
            "csr-active-config": bytes.fromhex("00000000"),
            "prev-lang:kbd": b"en-US:0",
            "run-efi-updater": "No",
        },
    }
    config["NVRAM"]["Delete"] = {
        APPLE_BOOT_GUID: ["DefaultBackgroundColor", "UIScale"],
        APPLE_NVRAM_GUID: [
            "boot-args",
            "csr-active-config",
            "prev-lang:kbd",
            "run-efi-updater",
        ],
    }
    configure_values(
        config["NVRAM"],
        {
            "LegacyOverwrite": False,
            "LegacySchema": {},
            "WriteFlash": True,
        },
    )

    generic = config["PlatformInfo"]["Generic"]
    configure_values(
        generic,
        {
            "AdviseFeatures": False,
            "MaxBIOSVersion": False,
            "MLB": identity["mlb"],
            "ProcessorType": 0,
            "ROM": bytes.fromhex(identity["rom"]),
            "SpoofVendor": True,
            "SystemMemoryStatus": "Auto",
            "SystemProductName": MODEL,
            "SystemSerialNumber": identity["serial"],
            "SystemUUID": identity["system_uuid"],
        },
    )
    configure_values(
        config["PlatformInfo"],
        {
            "Automatic": True,
            "CustomMemory": False,
            "UpdateDataHub": True,
            "UpdateNVRAM": True,
            "UpdateSMBIOS": True,
            "UpdateSMBIOSMode": "Custom",
            "UseRawUuidEncoding": False,
        },
    )
    if "Memory" in config["PlatformInfo"]:
        config["PlatformInfo"]["Memory"]["Devices"] = []

    configure_values(
        config["UEFI"]["APFS"],
        {
            "EnableJumpstart": True,
            "GlobalConnect": False,
            "HideVerbose": True,
            "JumpstartHotPlug": False,
            "MinDate": -1,
            "MinVersion": -1,
        },
    )
    config["UEFI"]["Drivers"] = [
        {
            "Arguments": "",
            "Comment": "OpenCore runtime services",
            "Enabled": True,
            "LoadEarly": False,
            "Path": "OpenRuntime.efi",
        },
        {
            "Arguments": "",
            "Comment": "Open-source HFS+ filesystem driver",
            "Enabled": True,
            "LoadEarly": False,
            "Path": "OpenHfsPlus.efi",
        },
        {
            "Arguments": "",
            "Comment": "Auxiliary Reset NVRAM picker entry",
            "Enabled": True,
            "LoadEarly": False,
            "Path": "ResetNvramEntry.efi",
        },
    ]
    configure_values(
        config["UEFI"]["Input"],
        {
            "KeyFiltering": False,
            "KeyForgetThreshold": 5,
            "KeySupport": True,
            "KeySupportMode": "Auto",
            "KeySwap": False,
            "PointerSupport": False,
            "PointerSupportMode": "",
            "TimerResolution": 50000,
        },
    )
    configure_values(
        config["UEFI"]["Output"],
        {
            "ClearScreenOnModeSwitch": False,
            "ConsoleMode": "",
            "DirectGopRendering": False,
            "ForceResolution": False,
            "GopBurstMode": False,
            "GopPassThrough": "Disabled",
            "IgnoreTextInGraphics": False,
            "InitialMode": "Auto",
            "ProvideConsoleGop": True,
            "ReconnectGraphicsOnConnect": False,
            "ReplaceTabWithSpace": False,
            "Resolution": "Max",
            "SanitiseClearScreen": False,
            "TextRenderer": "BuiltinGraphics",
            "UIScale": -1,
            "UgaPassThrough": False,
        },
    )
    configure_values(
        config["UEFI"]["Quirks"],
        {
            "ActivateHpetSupport": False,
            "DisableSecurityPolicy": False,
            "EnableVectorAcceleration": True,
            "EnableVmx": False,
            "ExitBootServicesDelay": 0,
            "ForceOcWriteFlash": False,
            "ForgeUefiSupport": False,
            "IgnoreInvalidFlexRatio": False,
            "ReleaseUsbOwnership": True,
            "ReloadOptionRoms": False,
            "RequestBootVarRouting": True,
            "ResizeGpuBars": -1,
            "ResizeUsePciRbIo": False,
            "ShimRetainProtocol": False,
            "TscSyncTimeout": 0,
            "UnblockFsConnect": False,
        },
    )
    config["UEFI"]["ReservedMemory"] = []
    return config


def manifest_path(root: Path) -> Path:
    return root.parent / f"{root.name}.SHA256SUMS"


def write_manifest(root: Path) -> Path:
    lines: list[str] = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(root).as_posix()}")
    output = manifest_path(root)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")
    return output


def main() -> int:
    args = arguments()
    opencore = args.opencore.expanduser().resolve()
    output = args.output.expanduser().resolve()
    identity_file = args.identity_file.expanduser().resolve()
    sample = opencore / "Docs" / "Sample.plist"
    macserial = opencore / "Utilities" / "macserial" / "macserial.linux"
    ocvalidate = opencore / "Utilities" / "ocvalidate" / "ocvalidate.linux"
    for required in (sample, macserial, ocvalidate):
        if not required.is_file():
            raise FileNotFoundError(required)
    kexts = parse_kexts(args.kext)
    identity = load_or_create_identity(identity_file, macserial)

    if output.exists():
        if not args.force:
            raise FileExistsError(f"output exists; pass --force to replace it: {output}")
        shutil.rmtree(output)
    (output / "BOOT").mkdir(parents=True)
    (output / "OC" / "ACPI").mkdir(parents=True)
    (output / "OC" / "Drivers").mkdir(parents=True)
    (output / "OC" / "Kexts").mkdir(parents=True)

    copy_file(opencore / "X64" / "EFI" / "BOOT" / "BOOTx64.efi", output / "BOOT" / "BOOTx64.efi")
    copy_file(opencore / "X64" / "EFI" / "OC" / "OpenCore.efi", output / "OC" / "OpenCore.efi")
    for name in ("OpenRuntime.efi", "OpenHfsPlus.efi", "ResetNvramEntry.efi"):
        copy_file(opencore / "X64" / "EFI" / "OC" / "Drivers" / name, output / "OC" / "Drivers" / name)
    for name in ("SSDT-EC-USBX.aml", "SSDT-PLUG.aml"):
        copy_file(opencore / "Docs" / "AcpiSamples" / "Binaries" / name, output / "OC" / "ACPI" / name)
    for name, source in kexts.items():
        shutil.copytree(source, output / "OC" / "Kexts" / name)

    config = build_config(sample, identity, kexts)
    config_path = output / "OC" / "config.plist"
    with config_path.open("wb") as stream:
        plistlib.dump(config, stream, fmt=plistlib.FMT_XML, sort_keys=False)
    os.chmod(config_path, 0o600)

    validation = subprocess.run(
        [str(ocvalidate), str(config_path)],
        text=True,
        capture_output=True,
    )
    sys.stdout.write(validation.stdout)
    sys.stderr.write(validation.stderr)
    if validation.returncode:
        raise RuntimeError("ocvalidate rejected the generated config")
    manifest = write_manifest(output)
    print(f"Built and validated: {output}")
    print(f"Identity reused from: {identity_file}")
    print(f"Manifest: {manifest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
