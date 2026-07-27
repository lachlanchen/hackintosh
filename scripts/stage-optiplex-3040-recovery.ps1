[CmdletBinding()]
param(
    [ValidateSet("Audit", "Apply")]
    [string]$Mode = "Audit",

    [Parameter(Mandatory = $true)]
    [string]$PayloadPath,

    [Parameter(Mandatory = $true)]
    [string]$BackupDirectory,

    [ValidatePattern("^[A-Z]$")]
    [string]$RecoveryDriveLetter = "R"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedModel = "OptiPlex 3040"
$ExpectedDataDisk = "TOSHIBA DT01ACA100"
$ExpectedSystemDisk = "Samsung SSD 860 PRO 256GB"
$ExpectedGOffset = [UInt64]703306137600
$ExpectedGSize = [UInt64]296898002944
$RecoverySize = [UInt64](4GB)
$ExpectedShrunkGSize = [UInt64]($ExpectedGSize - $RecoverySize)
$ExpectedRecoveryOffset = [UInt64]($ExpectedGOffset + $ExpectedShrunkGSize)
$RecoveryLabel = "MACRECOVERY"
$EspType = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd("\") + "\"
    $full = [IO.Path]::GetFullPath($FullPath)
    Assert-True ($full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) `
        "File is outside payload root: $FullPath"
    return $full.Substring($base.Length)
}

function Get-TreeManifest {
    param([string]$Root)

    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $items = @()
    foreach ($file in Get-ChildItem -LiteralPath $resolved -Recurse -File | Sort-Object FullName) {
        $relativePath = Get-RelativePath -BasePath $resolved -FullPath $file.FullName
        if ($relativePath -match '^(System Volume Information|\$RECYCLE\.BIN)(\\|$)') {
            continue
        }
        $items += [pscustomobject]@{
            Path = $relativePath
            Length = [UInt64]$file.Length
            SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return @($items)
}

function Assert-ManifestEqual {
    param(
        [object[]]$Expected,
        [object[]]$Actual
    )

    Assert-True ($Expected.Count -eq $Actual.Count) `
        "Payload file count changed after copy: expected $($Expected.Count), got $($Actual.Count)"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        $left = $Expected[$index]
        $right = $Actual[$index]
        Assert-True ($left.Path -ceq $right.Path) "Payload path mismatch: $($left.Path) != $($right.Path)"
        Assert-True ($left.Length -eq $right.Length) "Payload length mismatch: $($left.Path)"
        Assert-True ($left.SHA256 -eq $right.SHA256) "Payload hash mismatch: $($left.Path)"
    }
}

function Save-PreChangeEvidence {
    param(
        [string]$Directory,
        [string]$Sgdisk
    )

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $snapshot = Join-Path $Directory "before-stage-$timestamp"
    New-Item -ItemType Directory -Path $snapshot | Out-Null

    & bcdedit.exe /export (Join-Path $snapshot "bcd")
    Assert-True ($LASTEXITCODE -eq 0) "BCD export failed"
    (& bcdedit.exe /enum firmware /v) | Set-Content -Encoding UTF8 (Join-Path $snapshot "firmware.txt")
    Get-Disk |
        Sort-Object Number |
        Select-Object Number, FriendlyName, SerialNumber, PartitionStyle, Size, LargestFreeExtent |
        ConvertTo-Json |
        Set-Content -Encoding UTF8 (Join-Path $snapshot "disks.json")
    Get-Partition |
        Sort-Object DiskNumber, PartitionNumber |
        Select-Object DiskNumber, PartitionNumber, DriveLetter, Type, GptType, Size, Offset |
        ConvertTo-Json |
        Set-Content -Encoding UTF8 (Join-Path $snapshot "partitions.json")

    Push-Location $snapshot
    try {
        & $Sgdisk -b "disk0-toshiba.gpt" "0:"
        Assert-True ($LASTEXITCODE -eq 0) "Disk 0 GPT backup failed"
        & $Sgdisk -b "disk1-samsung.gpt" "1:"
        Assert-True ($LASTEXITCODE -eq 0) "Disk 1 GPT backup failed"
    }
    finally {
        Pop-Location
    }

    Get-ChildItem -LiteralPath $snapshot -File |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Length = $_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } |
        ConvertTo-Json |
        Set-Content -Encoding UTF8 (Join-Path $snapshot "SHA256.json")
    return $snapshot
}

$payload = (Resolve-Path -LiteralPath $PayloadPath).Path
$requiredPayload = @(
    "EFI\BOOT\BOOTx64.efi",
    "EFI\OC\OpenCore.efi",
    "EFI\OC\config.plist",
    "com.apple.recovery.boot\BaseSystem.dmg",
    "com.apple.recovery.boot\BaseSystem.chunklist"
)
foreach ($relativePath in $requiredPayload) {
    Assert-True (Test-Path -LiteralPath (Join-Path $payload $relativePath) -PathType Leaf) `
        "Required payload file is missing: $relativePath"
}

$computer = Get-CimInstance Win32_ComputerSystem
Assert-True ($computer.Manufacturer -eq "Dell Inc.") "Refusing non-Dell computer"
Assert-True ($computer.Model -eq $ExpectedModel) "Refusing model '$($computer.Model)'"

$disk0 = Get-Disk -Number 0
$disk1 = Get-Disk -Number 1
Assert-True ($disk0.FriendlyName -eq $ExpectedDataDisk) "Disk 0 identity changed"
Assert-True ($disk1.FriendlyName -eq $ExpectedSystemDisk) "Disk 1 identity changed"
Assert-True ($disk0.PartitionStyle -eq "GPT") "Disk 0 is not GPT"
Assert-True ($disk1.PartitionStyle -eq "GPT") "Disk 1 is not GPT"
Assert-True ($disk0.HealthStatus -eq "Healthy") "Disk 0 is not healthy"
Assert-True ($disk1.HealthStatus -eq "Healthy") "Disk 1 is not healthy"

$sgdisk = "C:\Users\lachlan\Downloads\RecoveryTools\sgdisk64.exe"
Assert-True (Test-Path -LiteralPath $sgdisk -PathType Leaf) "sgdisk64.exe is missing"
(& $sgdisk -v "0:") | Out-Null
Assert-True ($LASTEXITCODE -eq 0) "Disk 0 GPT verification failed"
(& $sgdisk -v "1:") | Out-Null
Assert-True ($LASTEXITCODE -eq 0) "Disk 1 GPT verification failed"

$g = Get-Partition -DriveLetter G
$gVolume = Get-Volume -DriveLetter G
Assert-True ($g.Offset -eq $ExpectedGOffset) "G: offset changed"
Assert-True ($gVolume.FileSystem -eq "NTFS") "G: is not NTFS"
Assert-True ($gVolume.HealthStatus -eq "Healthy") "G: is not healthy"
Assert-True ($gVolume.SizeRemaining -gt (8GB)) "G: has insufficient free space"

$matchingPartitions = @(Get-Partition -DiskNumber 0 | Where-Object {
    $_.GptType -eq $EspType -and
    $_.Offset -eq $ExpectedRecoveryOffset -and
    $_.Size -eq $RecoverySize
})
Assert-True ($matchingPartitions.Count -le 1) "Multiple matching recovery partitions exist"
$recoveryPartition = if ($matchingPartitions.Count -eq 1) { $matchingPartitions[0] } else { $null }
$recoveryVolume = $null

if ($null -eq $recoveryPartition) {
    if ($g.Size -eq $ExpectedGSize) {
        $recoveryState = "Absent"
    }
    elseif ($g.Size -eq $ExpectedShrunkGSize) {
        Assert-True ((Get-Disk -Number 0).LargestFreeExtent -ge $RecoverySize) `
            "G: is shrunk but the expected recovery space is unavailable"
        $recoveryState = "SpaceReserved"
    }
    else {
        throw "G: size does not match either audited staging state"
    }
}
else {
    Assert-True ($g.Size -eq $ExpectedShrunkGSize) "G: size does not match the recovery partition"
    if ($recoveryPartition.DriveLetter) {
        $recoveryVolume = Get-Volume -DriveLetter $recoveryPartition.DriveLetter
        if (
            $recoveryVolume.FileSystem -eq "FAT32" -and
            $recoveryVolume.FileSystemLabel -eq $RecoveryLabel
        ) {
            Assert-True ($recoveryVolume.HealthStatus -eq "Healthy") "MACRECOVERY is not healthy"
            $recoveryState = "Ready"
        }
        elseif (-not $recoveryVolume.FileSystem -or $recoveryVolume.FileSystem -eq "RAW") {
            $recoveryState = "NeedsFormat"
        }
        else {
            throw "The recovery partition contains an unexpected filesystem or label"
        }
    }
    else {
        $recoveryState = "NeedsDriveLetter"
    }
}

$sourceManifest = @(Get-TreeManifest -Root $payload)
$totalBytes = ($sourceManifest | Measure-Object -Property Length -Sum).Sum
Assert-True ($sourceManifest.Count -gt 5) "Payload contains too few files"
Assert-True ([UInt64]$totalBytes -lt ($RecoverySize - 128MB)) "Payload will not fit recovery partition"

$summary = [pscustomobject]@{
    Mode = $Mode
    Computer = $computer.Model
    DataDisk = $disk0.FriendlyName
    SystemDisk = $disk1.FriendlyName
    GOffset = $g.Offset
    GSize = $g.Size
    GFree = $gVolume.SizeRemaining
    RecoveryState = $recoveryState
    PayloadFiles = $sourceManifest.Count
    PayloadBytes = [UInt64]$totalBytes
}
$summary | Format-List

if ($Mode -eq "Audit") {
    Write-Host "Audit passed; no disk or boot state was changed."
    exit 0
}

$snapshot = Save-PreChangeEvidence -Directory $BackupDirectory -Sgdisk $sgdisk
Write-Host "Pre-change evidence: $snapshot"

if ($recoveryState -eq "Absent") {
    $supported = Get-PartitionSupportedSize -DriveLetter G
    Assert-True ($ExpectedShrunkGSize -ge $supported.SizeMin) `
        "Requested G: shrink is below supported minimum"
    Assert-True ($ExpectedShrunkGSize -le $supported.SizeMax) `
        "Requested G: size exceeds supported maximum"
    try {
        Resize-Partition -DriveLetter G -Size $ExpectedShrunkGSize
    }
    catch {
        $gAfterResize = Get-Partition -DriveLetter G
        if ($gAfterResize.Size -ne $ExpectedShrunkGSize) {
            throw
        }
        Write-Warning "Resize committed before Windows reported a console-output error; continuing."
    }
    Assert-True ((Get-Partition -DriveLetter G).Size -eq $ExpectedShrunkGSize) `
        "G: resize postcondition failed"
    $recoveryState = "SpaceReserved"
}

if ($recoveryState -eq "SpaceReserved") {
    try {
        New-Partition -DiskNumber 0 -Size $RecoverySize -GptType $EspType | Out-Null
    }
    catch {
        $createdAfterError = @(Get-Partition -DiskNumber 0 | Where-Object {
            $_.GptType -eq $EspType -and
            $_.Offset -eq $ExpectedRecoveryOffset -and
            $_.Size -eq $RecoverySize
        })
        if ($createdAfterError.Count -ne 1) {
            throw
        }
        Write-Warning "Partition creation committed before Windows reported a console-output error; continuing."
    }
    $recoveryPartition = @(Get-Partition -DiskNumber 0 | Where-Object {
        $_.GptType -eq $EspType -and
        $_.Offset -eq $ExpectedRecoveryOffset -and
        $_.Size -eq $RecoverySize
    })[0]
    Assert-True ($null -ne $recoveryPartition) "Recovery partition creation postcondition failed"
    $recoveryState = "NeedsDriveLetter"
}

if (-not $recoveryPartition) {
    $recoveryPartition = @(Get-Partition -DiskNumber 0 | Where-Object {
        $_.GptType -eq $EspType -and
        $_.Offset -eq $ExpectedRecoveryOffset -and
        $_.Size -eq $RecoverySize
    })[0]
}

if (-not $recoveryPartition.DriveLetter) {
    Assert-True ($null -eq (Get-Volume -DriveLetter $RecoveryDriveLetter -ErrorAction SilentlyContinue)) `
        "Recovery drive letter $RecoveryDriveLetter`: is already used"
    try {
        $recoveryPartition | Set-Partition -NewDriveLetter $RecoveryDriveLetter
    }
    catch {
        $mountedAfterError = Get-Partition -DiskNumber 0 -PartitionNumber $recoveryPartition.PartitionNumber
        if ([string]$mountedAfterError.DriveLetter -ne $RecoveryDriveLetter) {
            throw
        }
        Write-Warning "Drive-letter assignment committed before Windows reported an output error; continuing."
    }
}
else {
    $RecoveryDriveLetter = [string]$recoveryPartition.DriveLetter
}

$recoveryVolume = Get-Volume -DriveLetter $RecoveryDriveLetter
if (
    $recoveryVolume.FileSystem -ne "FAT32" -or
    $recoveryVolume.FileSystemLabel -ne $RecoveryLabel
) {
    Assert-True (-not $recoveryVolume.FileSystem -or $recoveryVolume.FileSystem -eq "RAW") `
        "Refusing to format an unexpected recovery filesystem"
    try {
        Format-Volume -DriveLetter $RecoveryDriveLetter -FileSystem FAT32 `
            -NewFileSystemLabel $RecoveryLabel -Confirm:$false -Force | Out-Null
    }
    catch {
        $formattedAfterError = Get-Volume -DriveLetter $RecoveryDriveLetter
        if (
            $formattedAfterError.FileSystem -ne "FAT32" -or
            $formattedAfterError.FileSystemLabel -ne $RecoveryLabel
        ) {
            throw
        }
        Write-Warning "Format committed before Windows reported a console-output error; continuing."
    }
}

$destination = "$RecoveryDriveLetter`:\"
$systemVolumeInformation = Join-Path $destination "System Volume Information"
$recycleBin = Join-Path $destination '$RECYCLE.BIN'
$robocopyOutput = & robocopy.exe $payload $destination /MIR /COPY:DAT /DCOPY:DAT `
    /R:2 /W:1 /XJ /XD $systemVolumeInformation $recycleBin
$robocopyExit = $LASTEXITCODE
$robocopyOutput | Write-Host
Assert-True ($robocopyExit -le 7) "Robocopy failed with exit code $robocopyExit"

$destinationManifest = @(Get-TreeManifest -Root $destination)
Assert-ManifestEqual -Expected $sourceManifest -Actual $destinationManifest
$sourceManifest |
    ConvertTo-Json |
    Set-Content -Encoding UTF8 (Join-Path $BackupDirectory "staged-payload-manifest.json")

(& $sgdisk -v "0:") | Out-Null
Assert-True ($LASTEXITCODE -eq 0) "Disk 0 GPT verification failed after staging"
$postVolume = Get-Volume -DriveLetter $RecoveryDriveLetter
Assert-True ($postVolume.FileSystemLabel -eq $RecoveryLabel) "Recovery volume label changed"
Assert-True ($postVolume.HealthStatus -eq "Healthy") "Recovery volume is not healthy"

Write-Host "MACRECOVERY staged and hash-verified at $destination"
Write-Host "Firmware boot order was not changed."
