<#
.SYNOPSIS
Plans or executes owner-authorized BitLocker salvage with repair-bde.

.DESCRIPTION
Supports only an owner-supplied .bek and an optional matching key package. The
original recovery-material filenames are never passed to a child process or
written to receipts. Apply stages fixed generic names in an administrator-only
temporary directory, overwrites one separately confirmed disposable output,
and verifies a pre-agreed non-secret marker.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode,

    [Parameter(Mandatory)][int]$SourceDiskNumber,
    [Parameter(Mandatory)][int]$OutputDiskNumber,
    [Parameter(Mandatory)][ValidatePattern('^[D-WY-Zd-wy-z]$')][string]$SourceDrive,
    [Parameter(Mandatory)][ValidatePattern('^[D-WY-Zd-wy-z]$')][string]$OutputDrive,
    [Parameter(Mandatory)][string]$RecoveryMaterialDirectory,
    [Parameter(Mandatory)][string]$KnownMarkerRelativePath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$KnownMarkerSha256,
    [string]$ConfirmationPhrase,
    [string]$OutputReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DiskFingerprint {
    param([Parameter(Mandatory)]$Disk)
    if ([string]::IsNullOrWhiteSpace([string]$Disk.UniqueId) -or [string]::IsNullOrWhiteSpace([string]$Disk.SerialNumber)) {
        throw 'Both disks require stable hardware identities.'
    }
    $value = [ordered]@{
        Number = $Disk.Number
        UniqueId = [string]$Disk.UniqueId
        SerialNumber = [string]$Disk.SerialNumber
        Size = [uint64]$Disk.Size
    } | ConvertTo-Json -Compress
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Get-SalvageDiskPair {
    if ($SourceDiskNumber -eq $OutputDiskNumber) { throw 'Source and output disks must be distinct.' }
    $SourceDisk = Get-Disk -Number $SourceDiskNumber -ErrorAction Stop
    $OutputDisk = Get-Disk -Number $OutputDiskNumber -ErrorAction Stop
    if ($SourceDisk.IsBoot -or $SourceDisk.IsSystem) { throw 'Refusing a boot or system source disk.' }
    if ($OutputDisk.IsBoot -or $OutputDisk.IsSystem) { throw 'Refusing a boot or system output disk.' }
    if ($SourceDisk.IsOffline -or $OutputDisk.IsOffline -or $SourceDisk.IsReadOnly -or $OutputDisk.IsReadOnly) {
        throw 'Source and output disks must be online and writable.'
    }
    if ($OutputDisk.Size -lt $SourceDisk.Size) { throw 'Output disk must be at least as large as the source disk.' }
    $sourcePartition = Get-Partition -DriveLetter $SourceDrive
    $outputPartition = Get-Partition -DriveLetter $OutputDrive
    if ($sourcePartition.DiskNumber -ne $SourceDiskNumber -or $outputPartition.DiskNumber -ne $OutputDiskNumber) {
        throw 'Drive letters do not match the selected disk identities.'
    }
    $outputItems = @(Get-ChildItem -LiteralPath "$OutputDrive`:" -Force -ErrorAction Stop | Where-Object {
        $_.Name -notin @('System Volume Information', '$RECYCLE.BIN')
    })
    if ($outputItems.Count -gt 0) { throw 'The output disk is not blank and disposable.' }
    [pscustomobject]@{
        SourceDisk = $SourceDisk
        OutputDisk = $OutputDisk
        SourceFingerprint = Get-DiskFingerprint -Disk $SourceDisk
        OutputFingerprint = Get-DiskFingerprint -Disk $OutputDisk
    }
}

if ($KnownMarkerRelativePath -match '(^[\\/])|(^|[\\/])\.\.([\\/]|$)') {
    throw 'Known marker path must be a safe relative path.'
}
if (!(Test-Path -LiteralPath $RecoveryMaterialDirectory -PathType Container)) {
    throw 'The owner-supplied recovery-material directory was not found.'
}
$bekFiles = @(Get-ChildItem -LiteralPath $RecoveryMaterialDirectory -Filter '*.bek' -File)
$keyPackages = @(Get-ChildItem -LiteralPath $RecoveryMaterialDirectory -Filter '*.kpg' -File)
if ($bekFiles.Count -ne 1 -or $keyPackages.Count -gt 1) {
    throw 'Recovery-material directory must contain exactly one .bek and at most one key package.'
}

$disks = Get-SalvageDiskPair
$suffix = $disks.OutputFingerprint.Substring($disks.OutputFingerprint.Length - 8)
$expectedPhrase = "OVERWRITE SALVAGE DISK $OutputDiskNumber $suffix"
$plan = [ordered]@{
    SchemaVersion = 1
    ContractType = 'ActionPlanV1'
    ActionType = 'SalvageBitLocker'
    SourceDiskNumber = $SourceDiskNumber
    OutputDiskNumber = $OutputDiskNumber
    SourceFingerprint = $disks.SourceFingerprint
    OutputFingerprint = $disks.OutputFingerprint
    OutputCapacityBytes = [uint64]$disks.OutputDisk.Size
    OutputWillBeCompletelyOverwritten = $true
    RecoveryKeyFileCount = 1
    KeyPackageSupplied = ($keyPackages.Count -eq 1)
    RecoveryMaterialNamesIncluded = $false
    RequiredConfirmationPhrase = $expectedPhrase
    WritePerformed = $false
}
if ($Mode -ceq 'Plan') { return [pscustomobject]$plan }

if (!(Test-Administrator)) { throw 'Apply requires an elevated Windows PowerShell session.' }
if ($ConfirmationPhrase -cne $expectedPhrase) { throw 'The target-bound confirmation phrase does not match.' }
if ([string]::IsNullOrWhiteSpace($OutputReceiptPath) -or (Test-Path -LiteralPath $OutputReceiptPath)) {
    throw 'A new non-target OutputReceiptPath is required.'
}
$receiptFullPath = [IO.Path]::GetFullPath($OutputReceiptPath)
if ($receiptFullPath -match '^([A-Za-z]):\\') {
    $receiptPartition = Get-Partition -DriveLetter $Matches[1] -ErrorAction SilentlyContinue
    if ($null -ne $receiptPartition -and $receiptPartition.DiskNumber -eq $OutputDiskNumber) {
        throw 'OutputReceiptPath must be on non-target storage.'
    }
}

# Identity changed means approval is invalid; this Re-scan is immediately before repair-bde.exe.
$rechecked = Get-SalvageDiskPair
if ($rechecked.SourceFingerprint -cne $disks.SourceFingerprint -or
    $rechecked.OutputFingerprint -cne $disks.OutputFingerprint) {
    throw 'Identity changed; approval is invalid.'
}
if (!$PSCmdlet.ShouldProcess(
    "output disk $OutputDiskNumber fingerprint $suffix",
    'Completely overwrite output with BitLocker salvage')) { return }

$stageRoot = Join-Path $env:ProgramData ("CodexRescue\EphemeralSalvage-{0}" -f [guid]::NewGuid().ToString('N'))
$stagedBek = Join-Path $stageRoot 'recovery-material.bek'
$stagedPackage = Join-Path $stageRoot 'key-package.kpg'
New-Item -ItemType Directory -Force $stageRoot | Out-Null
try {
    & icacls.exe $stageRoot '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to protect ephemeral recovery-material staging.' }
    try {
        Copy-Item -LiteralPath $bekFiles[0].FullName -Destination $stagedBek
        if ($keyPackages.Count -eq 1) { Copy-Item -LiteralPath $keyPackages[0].FullName -Destination $stagedPackage }
    }
    catch {
        throw 'Failed to stage owner-supplied recovery material; original names were suppressed.'
    }

    $arguments = @("$SourceDrive`:", "$OutputDrive`:", '-rk', $stagedBek)
    if ($keyPackages.Count -eq 1) { $arguments += @('-kp', $stagedPackage) }
    $arguments += '-f'
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\repair-bde.exe') -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { throw "BitLocker salvage failed with normalized exit code $($process.ExitCode)." }
}
finally {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$markerPath = Join-Path "$OutputDrive`:" $KnownMarkerRelativePath
if (!(Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'The known non-secret marker was not recovered.' }
$markerHash = (Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
if ($markerHash -cne $KnownMarkerSha256.ToUpperInvariant()) { throw 'The recovered marker hash does not match.' }

$receipt = [ordered]@{
    SchemaVersion = 1
    ContractType = 'ActionReceiptV1'
    ActionType = 'SalvageBitLocker'
    Result = 'Succeeded'
    NormalizedErrorCode = 'NONE'
    SourceFingerprint = $disks.SourceFingerprint
    OutputFingerprint = $disks.OutputFingerprint
    ChangesMade = @('Completely overwrote approved salvage output', 'Verified known non-secret marker')
    KnownMarkerVerified = $true
    RecoveryMaterialRetained = $false
    RecoveryMaterialNamesIncluded = $false
    RestartState = 'NotRequired'
    PrivacyDeclaration = 'No key contents, recovery-material names, key-package identifiers, or secret-bearing command output are included.'
    CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputReceiptPath -Encoding UTF8
[pscustomobject]$receipt
