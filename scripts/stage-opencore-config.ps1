[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceConfig,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedSourceSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedLiveSha256,

    [Parameter(Mandatory = $true)]
    [string]$BackupName,

    [Parameter(Mandatory = $true)]
    [string]$PreservedLiveName,

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
Assert-LeafName $PreservedLiveName 'PreservedLiveName'
if ($BackupName -eq $PreservedLiveName) {
    throw 'BackupName and PreservedLiveName must differ'
}

try {
    if (-not (Test-Path -LiteralPath $SourceConfig -PathType Leaf)) {
        throw "Source config does not exist: $SourceConfig"
    }

    $sourceHash = Get-Sha256 $SourceConfig
    if ($sourceHash -ne $ExpectedSourceSha256.ToUpperInvariant()) {
        throw "Source hash mismatch: expected $ExpectedSourceSha256, got $sourceHash"
    }

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
    $preservedConfig = Join-Path $ocRoot $PreservedLiveName
    $temporaryConfig = Join-Path $ocRoot (
        '.config-stage-{0}.tmp' -f [guid]::NewGuid().ToString('N')
    )

    if (-not (Test-Path -LiteralPath $openCoreBinary -PathType Leaf)) {
        throw "OpenCore.efi was not found at $openCoreBinary"
    }
    if (-not (Test-Path -LiteralPath $liveConfig -PathType Leaf)) {
        throw "OpenCore config was not found at $liveConfig"
    }
    if (Test-Path -LiteralPath $preservedConfig) {
        throw "Preserved-live path already exists: $preservedConfig"
    }

    $liveHash = Get-Sha256 $liveConfig
    if ($liveHash -ne $ExpectedLiveSha256.ToUpperInvariant()) {
        throw "Live config hash mismatch: expected $ExpectedLiveSha256, got $liveHash"
    }

    if (-not (Test-Path -LiteralPath $backupConfig)) {
        Copy-Item -LiteralPath $liveConfig -Destination $backupConfig
    }
    if (-not (Test-Path -LiteralPath $backupConfig -PathType Leaf)) {
        throw "Backup is not a regular file: $backupConfig"
    }
    $backupHash = Get-Sha256 $backupConfig
    if ($backupHash -ne $ExpectedLiveSha256.ToUpperInvariant()) {
        throw "Backup hash mismatch: expected $ExpectedLiveSha256, got $backupHash"
    }

    Copy-Item -LiteralPath $SourceConfig -Destination $temporaryConfig
    if ((Get-Sha256 $temporaryConfig) -ne $sourceHash) {
        throw 'Staged-on-EFI config hash mismatch'
    }

    Move-Item -LiteralPath $liveConfig -Destination $preservedConfig
    try {
        Move-Item -LiteralPath $temporaryConfig -Destination $liveConfig
        $temporaryConfig = $null
    }
    catch {
        Move-Item -LiteralPath $preservedConfig -Destination $liveConfig
        throw
    }

    $installedHash = Get-Sha256 $liveConfig
    if ($installedHash -ne $sourceHash) {
        $failedConfig = Join-Path $ocRoot (
            '.config-failed-{0}.tmp' -f [guid]::NewGuid().ToString('N')
        )
        Move-Item -LiteralPath $liveConfig -Destination $failedConfig
        Move-Item -LiteralPath $preservedConfig -Destination $liveConfig
        Remove-Item -LiteralPath $failedConfig -Force
        throw "Installed hash mismatch; original live config was restored"
    }

    Write-Output "EFI_DRIVE=$efiDrive"
    Write-Output "LIVE_BEFORE_SHA256=$liveHash"
    Write-Output "BACKUP_SHA256=$backupHash"
    Write-Output "LIVE_AFTER_SHA256=$installedHash"
    Write-Output "PRESERVED_LIVE_NAME=$PreservedLiveName"
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
