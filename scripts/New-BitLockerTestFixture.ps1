<#
.SYNOPSIS
Creates a disposable BitLocker data-volume and external-key fixture.

.DESCRIPTION
Destructively initializes two explicitly selected RAW virtual disks, encrypts
the data disk with BitLocker, writes the external recovery key to the separate
key disk, locks the data volume, and records only non-secret validation state.
Use this script only in a disposable test VM.

.PARAMETER DataDiskNumber
Disk number of the new 3 GiB RAW virtual data disk.

.PARAMETER KeyDiskNumber
Disk number of the new 1 GiB RAW virtual key disk.

.PARAMETER ConfirmationToken
Must exactly match CREATE DISPOSABLE BITLOCKER FIXTURE <data> <key>.

.EXAMPLE
.\scripts\New-BitLockerTestFixture.ps1 -DataDiskNumber 1 -KeyDiskNumber 2 -ConfirmationToken 'CREATE DISPOSABLE BITLOCKER FIXTURE 1 2' -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 128)]
    [int]$DataDiskNumber,

    [Parameter(Mandatory)]
    [ValidateRange(1, 128)]
    [int]$KeyDiskNumber,

    [Parameter(Mandatory)]
    [string]$ConfirmationToken,

    [string]$OutputDirectory = 'C:\CodexRescueVmAudit\BitLockerFixture'
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}
if ($DataDiskNumber -eq $KeyDiskNumber) {
    throw 'The data and key disks must be different.'
}

$requiredToken = "CREATE DISPOSABLE BITLOCKER FIXTURE $DataDiskNumber $KeyDiskNumber"
if ($ConfirmationToken -cne $requiredToken) {
    throw "Confirmation token mismatch. Required: $requiredToken"
}

$dataDisk = Get-Disk -Number $DataDiskNumber -ErrorAction Stop
$keyDisk = Get-Disk -Number $KeyDiskNumber -ErrorAction Stop
foreach ($disk in @($dataDisk, $keyDisk)) {
    if ($disk.IsBoot -or $disk.IsSystem) {
        throw "Refusing boot or system disk $($disk.Number)."
    }
    if ($disk.PartitionStyle -ne 'RAW') {
        throw "Disk $($disk.Number) is not RAW. No existing disk may be reused."
    }
}

$gib = 1GB
if ($dataDisk.Size -lt (2.9 * $gib) -or $dataDisk.Size -gt (3.1 * $gib)) {
    throw "Data disk $DataDiskNumber is not the expected disposable 3 GiB disk."
}
if ($keyDisk.Size -lt (0.9 * $gib) -or $keyDisk.Size -gt (1.1 * $gib)) {
    throw "Key disk $KeyDiskNumber is not the expected disposable 1 GiB disk."
}

$targetDescription = "RAW data disk $DataDiskNumber and RAW key disk $KeyDiskNumber"
if (!$PSCmdlet.ShouldProcess($targetDescription, 'Initialize, format, encrypt, and lock disposable BitLocker fixture')) {
    return
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$bitLockerPolicyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'
if (!(Test-Path $bitLockerPolicyPath)) {
    New-Item -Path $bitLockerPolicyPath | Out-Null
}
New-ItemProperty -Path $bitLockerPolicyPath -Name 'PreventDeviceEncryption' -PropertyType DWord -Value 1 -Force | Out-Null

$dataPartition = Initialize-Disk -Number $DataDiskNumber -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -AssignDriveLetter
$keyPartition = Initialize-Disk -Number $KeyDiskNumber -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -AssignDriveLetter

$dataVolume = $dataPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'CODEX-BL-TEST' -Confirm:$false
$keyVolume = $keyPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'CODEX-BL-KEY' -Confirm:$false
$dataRoot = "$($dataVolume.DriveLetter):\"
$keyRoot = "$($keyVolume.DriveLetter):\"

'Codex Rescue disposable BitLocker fixture. No customer data.' |
    Set-Content -Encoding ASCII -LiteralPath (Join-Path $dataRoot 'RECOVERY-TEST.txt')
New-Item -ItemType File -Path (Join-Path $keyRoot 'CODEX_BITLOCKER.KEY') -Force | Out-Null

$dataBitLocker = Get-BitLockerVolume -MountPoint "$($dataVolume.DriveLetter):"
$keyBitLocker = Get-BitLockerVolume -MountPoint "$($keyVolume.DriveLetter):"
if ($dataBitLocker.VolumeStatus -ne 'FullyDecrypted' -or $keyBitLocker.VolumeStatus -ne 'FullyDecrypted') {
    throw 'Windows began automatic device encryption. Both disposable volumes must be fully decrypted before the explicit protector is created.'
}

Enable-BitLocker -MountPoint "$($dataVolume.DriveLetter):" -RecoveryKeyProtector -RecoveryKeyPath $keyRoot `
    -EncryptionMethod XtsAes128 -UsedSpaceOnly -SkipHardwareTest -Confirm:$false | Out-Null

$deadline = (Get-Date).AddMinutes(3)
do {
    Start-Sleep -Seconds 2
    $bitLocker = Get-BitLockerVolume -MountPoint "$($dataVolume.DriveLetter):"
} until ($bitLocker.VolumeStatus -eq 'FullyEncrypted' -or (Get-Date) -ge $deadline)
if ($bitLocker.VolumeStatus -ne 'FullyEncrypted') {
    throw "BitLocker encryption did not complete before $deadline."
}
$encryptionState = $bitLocker.VolumeStatus.ToString()

$keyBitLocker = Get-BitLockerVolume -MountPoint "$($keyVolume.DriveLetter):"
if ($keyBitLocker.VolumeStatus -ne 'FullyDecrypted') {
    throw 'The external key volume is not fully decrypted. Refusing to continue.'
}

$externalKeyFiles = @(Get-ChildItem -LiteralPath $keyRoot -Filter '*.bek' -File -Recurse -Force)
if ($externalKeyFiles.Count -ne 1) {
    throw 'The key drive must contain exactly one external .bek recovery-key file.'
}
$fixtureFileSha256 = (Get-FileHash -LiteralPath (Join-Path $dataRoot 'RECOVERY-TEST.txt') -Algorithm SHA256).Hash

& manage-bde.exe -lock "$($dataVolume.DriveLetter):" -ForceDismount | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "BitLocker lock failed with exit code $LASTEXITCODE."
}
$bitLocker = Get-BitLockerVolume -MountPoint "$($dataVolume.DriveLetter):"
if ($bitLocker.LockStatus -ne 'Locked') {
    throw 'The disposable data volume did not reach the locked state.'
}

$result = [ordered]@{
    SchemaVersion = 1
    CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    DataDiskNumber = $DataDiskNumber
    DataDiskSize = $dataDisk.Size
    DataVolumeLabel = $dataVolume.FileSystemLabel
    KeyDiskNumber = $KeyDiskNumber
    KeyDiskSize = $keyDisk.Size
    KeyVolumeLabel = $keyVolume.FileSystemLabel
    ExternalKeyFileCount = $externalKeyFiles.Count
    EncryptionState = $encryptionState
    LockState = $bitLocker.LockStatus.ToString()
    KeyVolumeEncryptionState = $keyBitLocker.VolumeStatus.ToString()
    FixtureFileSha256 = $fixtureFileSha256
    ContainsRecoveryMaterial = $false
}
$result | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'fixture-result.json')
$result
