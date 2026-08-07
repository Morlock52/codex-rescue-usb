<#
.SYNOPSIS
Plans or writes one verified Codex Rescue ISO to one removable USB disk.

.DESCRIPTION
Plan is read-only. Apply revalidates the signed-build verification JSON, ISO
hash, target properties, stable disk identity, and target-bound confirmation
immediately before clearing the selected disk. The writer uses only Windows
storage cmdlets and emits an ActionReceiptV1-shaped JSON receipt.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$IsoPath,

    [Parameter(Mandatory)]
    [string]$VerificationPath,

    [Parameter(Mandatory)]
    [ValidateRange(0, 4096)]
    [int]$DiskNumber,

    [string]$ConfirmationPhrase,

    [string]$OutputReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$maximumFat32FileSize = [uint64]4294967295
$maximumFat32PartitionSize = [uint64](32GB - 16MB)

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TargetFingerprint {
    param([Parameter(Mandatory)]$Disk)
    if ([string]::IsNullOrWhiteSpace([string]$Disk.UniqueId) -or
        [string]::IsNullOrWhiteSpace([string]$Disk.SerialNumber)) {
        throw 'The selected disk has no stable UniqueId or SerialNumber.'
    }
    $identity = [ordered]@{
        Number = [int]$Disk.Number
        UniqueId = [string]$Disk.UniqueId
        SerialNumber = [string]$Disk.SerialNumber
        FriendlyName = [string]$Disk.FriendlyName
        BusType = [string]$Disk.BusType
        Size = [uint64]$Disk.Size
    } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($identity)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '') }
    finally { $hash.Dispose() }
}

function Get-ValidatedUsbDisk {
    $diskMatches = @(Get-Disk -Number $DiskNumber -ErrorAction Stop)
    if ($diskMatches.Count -ne 1) {
        throw 'Exactly one selected disk must resolve.'
    }
    $disk = $diskMatches[0]
    if ($disk.IsBoot -or $disk.IsSystem) { throw 'Refusing a boot or system disk.' }
    if ($disk.IsOffline) { throw 'Refusing an offline disk.' }
    if ($disk.IsReadOnly) { throw 'Refusing a read-only disk.' }
    if ([string]$disk.BusType -cne 'USB') { throw 'BusType must be USB.' }
    if ([string]$disk.FriendlyName -match '(?i)virtual|vhd|qemu|vmware') {
        throw 'Refusing a virtual disk.'
    }
    if ([uint64]$disk.Size -lt 1GB) { throw 'Refusing USB media smaller than 1 GiB.' }

    $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    foreach ($pageFile in $pageFiles) {
        if ([string]$pageFile.Name -match '^([A-Za-z]):\\') {
            $driveLetter = $Matches[1]
            $pagePartition = Get-Partition -DriveLetter $driveLetter -ErrorAction SilentlyContinue
            if ($null -ne $pagePartition -and $pagePartition.DiskNumber -eq $disk.Number) {
                throw 'Refusing a page-file disk.'
            }
        }
    }
    return $disk
}

function Read-Verification {
    param(
        [Parameter(Mandatory)][string]$IsoFile,
        [Parameter(Mandatory)][string]$VerificationFile
    )
    if (!(Test-Path -LiteralPath $IsoFile -PathType Leaf) -or
        [IO.Path]::GetExtension($IsoFile) -ine '.iso') {
        throw 'A local ISO file is required.'
    }
    if (!(Test-Path -LiteralPath $VerificationFile -PathType Leaf)) {
        throw 'The ISO verification JSON is required.'
    }
    $verification = Get-Content -LiteralPath $VerificationFile -Raw | ConvertFrom-Json
    if ($verification.SchemaVersion -ne 1 -or
        $verification.VerificationSucceeded -isnot [bool] -or
        !$verification.VerificationSucceeded -or
        $verification.ContainsRecoveryMaterial -isnot [bool] -or
        $verification.ContainsRecoveryMaterial) {
        throw 'VerificationSucceeded must be true and recovery material must be absent.'
    }
    $actualIsoHash = (Get-FileHash -LiteralPath $IsoFile -Algorithm SHA256).Hash
    if ($verification.IsoSha256 -cne $actualIsoHash) {
        throw 'IsoSha256 does not match the selected ISO.'
    }
    return [pscustomobject]@{ Receipt = $verification; IsoSha256 = $actualIsoHash }
}

$verifiedIso = Read-Verification -IsoFile $IsoPath -VerificationFile $VerificationPath
$disk = Get-ValidatedUsbDisk
$fingerprint = Get-TargetFingerprint -Disk $disk
$fingerprintSuffix = $fingerprint.Substring($fingerprint.Length - 8)
$expectedPhrase = "ERASE USB DISK $DiskNumber $fingerprintSuffix"
$plan = [ordered]@{
    SchemaVersion = 1
    ContractType = 'ActionPlanV1'
    ActionType = 'WriteUsb'
    ArtifactId = [string]$verifiedIso.Receipt.ArtifactId
    IsoSha256 = $verifiedIso.IsoSha256
    TrustPath = [string]$verifiedIso.Receipt.TrustPath
    DiskNumber = $disk.Number
    Model = [string]$disk.FriendlyName
    Serial = [string]$disk.SerialNumber
    Bus = [string]$disk.BusType
    CapacityBytes = [uint64]$disk.Size
    TargetFingerprint = $fingerprint
    RequiredConfirmationPhrase = $expectedPhrase
    Destructive = $true
    WritePerformed = $false
}
if ($Mode -ceq 'Plan') {
    return [pscustomobject]$plan
}

if (!(Test-Administrator)) { throw 'Apply requires an elevated Windows PowerShell session.' }
if ($ConfirmationPhrase -cne $expectedPhrase) {
    throw "ConfirmationPhrase must exactly match the target-bound phrase shown by Plan."
}
if ([string]::IsNullOrWhiteSpace($OutputReceiptPath) -or
    [IO.Path]::GetExtension($OutputReceiptPath) -ine '.json' -or
    (Test-Path -LiteralPath $OutputReceiptPath)) {
    throw 'Apply requires a new .json OutputReceiptPath on non-target storage.'
}
$receiptFullPath = [IO.Path]::GetFullPath($OutputReceiptPath)
$receiptParent = Split-Path -Parent $receiptFullPath
if (!(Test-Path -LiteralPath $receiptParent -PathType Container)) {
    throw 'OutputReceiptPath parent directory does not exist.'
}
if ($receiptFullPath -match '^([A-Za-z]):\\') {
    $receiptPartition = Get-Partition -DriveLetter $Matches[1] -ErrorAction SilentlyContinue
    if ($null -ne $receiptPartition -and $receiptPartition.DiskNumber -eq $DiskNumber) {
        throw 'The action receipt must be stored on non-target storage.'
    }
}

$isoMounted = $false
try {
    $image = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -PassThru
    $isoMounted = $true
    $isoVolumes = @($image | Get-Volume)
    if ($isoVolumes.Count -ne 1 -or [string]::IsNullOrWhiteSpace($isoVolumes[0].DriveLetter)) {
        throw 'The verified ISO must expose exactly one volume.'
    }
    $isoRoot = "$($isoVolumes[0].DriveLetter):\"
    $sourceFiles = @(Get-ChildItem -LiteralPath $isoRoot -File -Recurse -Force)
    $oversized = @($sourceFiles | Where-Object Length -gt $maximumFat32FileSize)
    if ($oversized.Count -gt 0) {
        throw 'The ISO contains a file larger than the FAT32 limit.'
    }

    # Re-scan immediately before the destructive command; approval is target-bound.
    $recheckedDisk = Get-ValidatedUsbDisk
    $recheckedFingerprint = Get-TargetFingerprint -Disk $recheckedDisk
    if ($recheckedFingerprint -cne $fingerprint) {
        throw 'Identity changed during Re-scan; approval is invalid.'
    }
    if (!$PSCmdlet.ShouldProcess(
        "USB disk $DiskNumber fingerprint $fingerprintSuffix",
        'Clear, initialize GPT, create FAT32 media, copy, and verify')) {
        return
    }

    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $DiskNumber -PartitionStyle GPT | Out-Null
    $partitionSize = [Math]::Min([uint64]($recheckedDisk.Size - 32MB), $maximumFat32PartitionSize)
    $partition = New-Partition -DiskNumber $DiskNumber -Size $partitionSize -AssignDriveLetter
    $volume = Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel 'CODEX_RESCUE' -Confirm:$false
    if ([string]::IsNullOrWhiteSpace([string]$volume.DriveLetter)) {
        throw 'The new FAT32 volume has no drive letter.'
    }
    $targetRoot = "$($volume.DriveLetter):\"
    if ($receiptFullPath.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The action receipt must be stored on non-target storage.'
    }

    Copy-Item -Path (Join-Path $isoRoot '*') -Destination $targetRoot -Recurse -Force

    $readback = foreach ($sourceFile in $sourceFiles) {
        $relative = $sourceFile.FullName.Substring($isoRoot.Length)
        $targetFile = Join-Path $targetRoot $relative
        if (!(Test-Path -LiteralPath $targetFile -PathType Leaf)) {
            throw "Readback file is missing: $relative"
        }
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash
        if ($sourceHash -cne $targetHash) {
            throw "Readback hash failed: $relative"
        }
        [ordered]@{ RelativePath = $relative; Sha256 = $targetHash }
    }

    $receipt = [ordered]@{
        SchemaVersion = 1
        ContractType = 'ActionReceiptV1'
        ActionType = 'WriteUsb'
        Result = 'Succeeded'
        NormalizedErrorCode = 'NONE'
        TargetFingerprint = $fingerprint
        IsoSha256 = $verifiedIso.IsoSha256
        ArtifactId = [string]$verifiedIso.Receipt.ArtifactId
        ChangesMade = @('Cleared selected USB disk', 'Created GPT/FAT32 media', 'Copied verified ISO payload')
        ReadbackFileCount = @($readback).Count
        Readback = @($readback)
        RestartState = 'NotRequired'
        PrivacyDeclaration = 'No credentials, recovery material, command output, or file contents are included.'
        CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputReceiptPath -Encoding UTF8
    [pscustomobject]$receipt
}
finally {
    if ($isoMounted) {
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    }
}
