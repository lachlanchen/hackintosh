[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedLiveSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedBackupSha256,

    [Parameter(Mandatory = $true)]
    [string]$BackupName,

    [Parameter(Mandatory = $true)]
    [string]$PreservedUsedName,

    [ValidatePattern('^[D-Zd-z]$')]
    [string]$EfiDriveLetter = 'Z'
)

$ErrorActionPreference = 'Stop'
$efiDrive = '{0}:' -f $EfiDriveLetter.ToUpperInvariant()
$efiRoot = "$efiDrive\"
$mountedHere = $false
$temporaryConfig = $null

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Assert-LeafName([string]$Name, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Name) -or
        [IO.Path]::GetFileName($Name) -ne $Name -or
        $Name -eq '.' -or
        $Name -eq '..' -or
        $Name -eq 'config.plist') {
        throw "$Label must be a safe leaf filename"
    }
}

Assert-LeafName $BackupName 'BackupName'
Assert-LeafName $PreservedUsedName 'PreservedUsedName'
if ($BackupName -eq $PreservedUsedName) {
    throw 'BackupName and PreservedUsedName must differ'
}

try {
    if (Test-Path -LiteralPath $efiRoot) {
        throw "$efiDrive is already mounted; refusing to guess which volume it is"
    }

    & mountvol.exe $efiRoot /S
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to mount the Windows system EFI partition on $efiDrive"
    }
    $mountedHere = $true

    $ocRoot = Join-Path $efiRoot 'EFI\OC'
    $liveConfig = Join-Path $ocRoot 'config.plist'
    $openCoreBinary = Join-Path $ocRoot 'OpenCore.efi'
    $backupConfig = Join-Path $ocRoot $BackupName
    $usedConfig = Join-Path $ocRoot $PreservedUsedName
    $temporaryConfig = Join-Path $ocRoot (
        '.config-restore-{0}.tmp' -f [guid]::NewGuid().ToString('N')
    )

    if (-not (Test-Path -LiteralPath $openCoreBinary -PathType Leaf)) {
        throw "OpenCore.efi was not found at $openCoreBinary"
    }
    if (-not (Test-Path -LiteralPath $liveConfig -PathType Leaf)) {
        throw "OpenCore config was not found at $liveConfig"
    }
    if (-not (Test-Path -LiteralPath $backupConfig -PathType Leaf)) {
        throw "Backup config was not found at $backupConfig"
    }
    if (Test-Path -LiteralPath $usedConfig) {
        throw "Preserved-used path already exists: $usedConfig"
    }

    $liveHash = Get-Sha256 $liveConfig
    $backupHash = Get-Sha256 $backupConfig
    if ($liveHash -ne $ExpectedLiveSha256.ToUpperInvariant()) {
        throw "Live config hash mismatch: expected $ExpectedLiveSha256, got $liveHash"
    }
    if ($backupHash -ne $ExpectedBackupSha256.ToUpperInvariant()) {
        throw "Backup hash mismatch: expected $ExpectedBackupSha256, got $backupHash"
    }

    Copy-Item -LiteralPath $backupConfig -Destination $temporaryConfig
    if ((Get-Sha256 $temporaryConfig) -ne $backupHash) {
        throw 'Staged restore hash mismatch'
    }

    Move-Item -LiteralPath $liveConfig -Destination $usedConfig
    try {
        Move-Item -LiteralPath $temporaryConfig -Destination $liveConfig
        $temporaryConfig = $null
    }
    catch {
        Move-Item -LiteralPath $usedConfig -Destination $liveConfig
        throw
    }

    $restoredHash = Get-Sha256 $liveConfig
    if ($restoredHash -ne $backupHash) {
        $failedConfig = Join-Path $ocRoot (
            '.config-failed-restore-{0}.tmp' -f [guid]::NewGuid().ToString('N')
        )
        Move-Item -LiteralPath $liveConfig -Destination $failedConfig
        Move-Item -LiteralPath $usedConfig -Destination $liveConfig
        Remove-Item -LiteralPath $failedConfig -Force
        throw "Restored hash mismatch; prior live config was put back"
    }

    Write-Output "EFI_DRIVE=$efiDrive"
    Write-Output "LIVE_BEFORE_SHA256=$liveHash"
    Write-Output "BACKUP_SHA256=$backupHash"
    Write-Output "LIVE_AFTER_SHA256=$restoredHash"
    Write-Output "PRESERVED_USED_NAME=$PreservedUsedName"
}
finally {
    if ($temporaryConfig -and (Test-Path -LiteralPath $temporaryConfig)) {
        Remove-Item -LiteralPath $temporaryConfig -Force
    }
    if ($mountedHere) {
        & mountvol.exe $efiRoot /D
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not unmount $efiDrive; inspect it manually"
        }
    }
}
