[CmdletBinding()]
param(
    [ValidateSet("Audit", "Create", "Arm", "Clear")]
    [string]$Mode = "Audit",

    [ValidatePattern("^[A-Z]$")]
    [string]$RecoveryDriveLetter = "R",

    [Parameter(Mandatory = $true)]
    [string]$StateDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Description = "OpenCore OptiPlex 3040 Recovery"
$ExpectedModel = "OptiPlex 3040"
$ExpectedLabel = "MACRECOVERY"
$StateFile = Join-Path $StateDirectory "opencore-bcd-id.txt"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-BcdEdit {
    param([string[]]$Arguments)

    $output = & bcdedit.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Read-EntryId {
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        throw "OpenCore BCD state file is missing: $StateFile"
    }
    $id = (Get-Content -LiteralPath $StateFile -TotalCount 1).Trim()
    Assert-True ($id -match '^\{[0-9a-fA-F-]{36}\}$') "Invalid BCD identifier in $StateFile"
    return $id
}

function Assert-Entry {
    param([string]$Id)

    $entry = (Invoke-BcdEdit -Arguments @("/enum", $Id, "/v")) -join "`n"
    Assert-True ($entry -match [regex]::Escape($Description)) "BCD entry description changed"
    Assert-True ($entry -match '(?im)^device\s+partition=') "BCD entry has no partition device"
    Assert-True ($entry -match '(?im)^path\s+\\EFI\\BOOT\\BOOTx64\.efi\s*$') `
        "BCD entry path is not OpenCore"
    return $entry
}

$computer = Get-CimInstance Win32_ComputerSystem
Assert-True ($computer.Manufacturer -eq "Dell Inc.") "Refusing non-Dell computer"
Assert-True ($computer.Model -eq $ExpectedModel) "Refusing model '$($computer.Model)'"

$volume = Get-Volume -DriveLetter $RecoveryDriveLetter -ErrorAction SilentlyContinue
Assert-True ($null -ne $volume) "Recovery drive $RecoveryDriveLetter`: is not mounted"
Assert-True ($volume.FileSystemLabel -eq $ExpectedLabel) "Recovery volume label changed"
Assert-True ($volume.FileSystem -eq "FAT32") "Recovery volume is not FAT32"
Assert-True ($volume.HealthStatus -eq "Healthy") "Recovery volume is not healthy"
$bootFile = "$RecoveryDriveLetter`:\EFI\BOOT\BOOTx64.efi"
Assert-True (Test-Path -LiteralPath $bootFile -PathType Leaf) "OpenCore bootstrap is missing: $bootFile"

New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null

if ($Mode -eq "Create") {
    if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
        $id = Read-EntryId
        Assert-Entry -Id $id | Out-Null
        Write-Host "Existing OpenCore BCD entry is valid: $id"
        exit 0
    }

    $created = (Invoke-BcdEdit -Arguments @(
        "/create",
        "/d",
        $Description,
        "/application",
        "BOOTAPP"
    )) -join "`n"
    $match = [regex]::Match($created, '\{[0-9a-fA-F-]{36}\}')
    Assert-True $match.Success "Could not parse the created BCD identifier"
    $id = $match.Value

    try {
        Invoke-BcdEdit -Arguments @(
            "/set",
            $id,
            "device",
            "partition=$RecoveryDriveLetter`:"
        ) | Out-Null
        Invoke-BcdEdit -Arguments @(
            "/set",
            $id,
            "path",
            "\EFI\BOOT\BOOTx64.efi"
        ) | Out-Null
        Invoke-BcdEdit -Arguments @(
            "/displayorder",
            $id,
            "/addfirst"
        ) | Out-Null
        Assert-Entry -Id $id | Out-Null

        $temporary = "$StateFile.new"
        $id | Set-Content -LiteralPath $temporary -Encoding ASCII
        Move-Item -LiteralPath $temporary -Destination $StateFile
    }
    catch {
        & bcdedit.exe /delete $id /cleanup | Out-Null
        throw
    }

    Write-Host "Created and verified OpenCore BCD entry: $id"
    Write-Host "No one-time boot was armed and no reboot was requested."
    exit 0
}

$id = Read-EntryId
Assert-Entry -Id $id | Out-Null

if ($Mode -eq "Arm") {
    Invoke-BcdEdit -Arguments @("/bootsequence", $id) | Out-Null
    $bootManager = (Invoke-BcdEdit -Arguments @("/enum", "{bootmgr}", "/v")) -join "`n"
    Assert-True ($bootManager -match "(?im)^bootsequence\s+$([regex]::Escape($id))\s*$") `
        "The one-time OpenCore boot sequence was not recorded"
    Write-Host "Armed one-time OpenCore boot: $id"
    Write-Host "The following boot returns to the normal Windows default."
    Write-Host "No reboot was requested."
    exit 0
}

if ($Mode -eq "Clear") {
    $output = & bcdedit.exe /deletevalue "{bootmgr}" bootsequence 2>&1
    if ($LASTEXITCODE -ne 0 -and (($output -join "`n") -notmatch "Element not found")) {
        throw "Could not clear one-time boot sequence: $($output -join [Environment]::NewLine)"
    }
    Write-Host "One-time boot sequence is clear."
    exit 0
}

$bootManager = (Invoke-BcdEdit -Arguments @("/enum", "{bootmgr}", "/v")) -join "`n"
$armed = $bootManager -match "(?im)^bootsequence\s+$([regex]::Escape($id))\s*$"
[pscustomobject]@{
    Computer = $computer.Model
    RecoveryVolume = "$RecoveryDriveLetter`:"
    BootFile = $bootFile
    BcdIdentifier = $id
    OneTimeBootArmed = $armed
} | Format-List
Write-Host "Audit passed; no boot state was changed."
