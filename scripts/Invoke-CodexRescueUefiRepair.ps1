<#
.SYNOPSIS
Prepares, applies, or rolls back one evidence-gated UEFI BCDBoot repair.

.DESCRIPTION
Prepare discovers exactly one Windows and EFI partition, backs up the EFI tree
and BCD evidence to a different disk, hashes the backup, proves the archive can
be expanded, and emits a target-bound plan. Apply revalidates all evidence and
runs only BCDBoot for that Windows/EFI pair. Rollback restores only the backed
up Microsoft boot subtree after separate target-bound approval.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Apply', 'Rollback')]
    [string]$Mode,

    [string]$BackupDirectory,

    [string]$PlanPath,

    [string]$ConfirmationPhrase,

    [string]$OutputReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$efiGptType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    }
    finally { $algorithm.Dispose() }
}

function Get-RepairTarget {
    $WindowsCandidates = @(Get-Partition | Where-Object DriveLetter | Where-Object {
        Test-Path -LiteralPath "$($_.DriveLetter):\Windows\System32\config\SYSTEM" -PathType Leaf
    })
    if ($WindowsCandidates.Count -ne 1) {
        throw 'Windows discovery is ambiguous; exactly one verified installation is required.'
    }
    $EfiCandidates = @(Get-Partition | Where-Object {
        [string]$_.GptType -ieq $efiGptType
    } | Where-Object {
        $volume = $_ | Get-Volume -ErrorAction SilentlyContinue
        $null -ne $volume -and [string]$volume.FileSystem -ceq 'FAT32'
    })
    if ($EfiCandidates.Count -ne 1) {
        throw 'EFI discovery is ambiguous; exactly one FAT32 system partition is required.'
    }
    if ($WindowsCandidates[0].DiskNumber -ne $EfiCandidates[0].DiskNumber) {
        throw 'The Windows and EFI candidates must be on the same explicitly identified disk.'
    }
    $disk = Get-Disk -Number $WindowsCandidates[0].DiskNumber
    if ($disk.IsOffline -or $disk.IsReadOnly -or [string]$disk.HealthStatus -cne 'Healthy') {
        throw 'The selected disk must be online, writable, and Healthy.'
    }
    $identity = [ordered]@{
        DiskNumber = $disk.Number
        DiskUniqueId = [string]$disk.UniqueId
        DiskSerialNumber = [string]$disk.SerialNumber
        WindowsPartition = $WindowsCandidates[0].PartitionNumber
        WindowsDrive = [string]$WindowsCandidates[0].DriveLetter
        EfiPartition = $EfiCandidates[0].PartitionNumber
        EfiOffset = [uint64]$EfiCandidates[0].Offset
    }
    [pscustomobject]@{
        Windows = $WindowsCandidates[0]
        Efi = $EfiCandidates[0]
        Disk = $disk
        TargetFingerprint = Get-Sha256Text -Text ($identity | ConvertTo-Json -Compress)
    }
}

function Use-EfiMount {
    param(
        [Parameter(Mandatory)]$Partition,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $existingVolume = $Partition | Get-Volume
    if (![string]::IsNullOrWhiteSpace([string]$existingVolume.DriveLetter)) {
        return & $Action "$($existingVolume.DriveLetter):\"
    }
    $mountRoot = Join-Path $env:ProgramData ("CodexRescue\EfiMount-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $mountRoot | Out-Null
    Add-PartitionAccessPath -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -AccessPath $mountRoot
    try { return & $Action $mountRoot }
    finally {
        Remove-PartitionAccessPath -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -AccessPath $mountRoot -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $mountRoot -Force -ErrorAction SilentlyContinue
    }
}

function Read-VerifiedPlan {
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or !(Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
        throw 'Apply and Rollback require the plan produced by Prepare.'
    }
    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    if ($plan.SchemaVersion -ne 1 -or $plan.ActionType -cne 'RepairUefi' -or !$plan.BackupVerified) {
        throw 'The repair plan or BackupManifest is invalid.'
    }
    if (!(Test-Path -LiteralPath $plan.BackupArchivePath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $plan.BackupArchivePath -Algorithm SHA256).Hash -cne $plan.BackupArchiveSha256) {
        throw 'The rollback archive is missing or changed.'
    }
    $verificationDirectory = Join-Path ([IO.Path]::GetTempPath()) ("CodexRescueRollbackVerify-{0}" -f [guid]::NewGuid())
    try {
        Expand-Archive -LiteralPath $plan.BackupArchivePath -DestinationPath $verificationDirectory
        $expandedManifestPath = Join-Path $verificationDirectory 'BackupManifest.json'
        if (!(Test-Path -LiteralPath $expandedManifestPath -PathType Leaf)) {
            throw 'The rollback archive cannot be read or lacks its BackupManifest.'
        }
        $expandedManifest = Get-Content -LiteralPath $expandedManifestPath -Raw | ConvertFrom-Json
        if ($expandedManifest.SchemaVersion -ne 1 -or
            $expandedManifest.TargetFingerprint -cne $plan.TargetFingerprint -or
            $expandedManifest.RecoveryMaterialIncluded -isnot [bool] -or
            $expandedManifest.RecoveryMaterialIncluded) {
            throw 'BackupManifest does not match the repair plan.'
        }
        foreach ($file in @($expandedManifest.Files)) {
            if ([string]$file.RelativePath -match '(^[\\/])|(^|[\\/])\.\.([\\/]|$)') {
                throw 'BackupManifest contains an unsafe path.'
            }
            $expandedFile = Join-Path $verificationDirectory ([string]$file.RelativePath)
            if (!(Test-Path -LiteralPath $expandedFile -PathType Leaf) -or
                (Get-FileHash -LiteralPath $expandedFile -Algorithm SHA256).Hash -cne $file.Sha256) {
                throw 'BackupManifest content hash verification failed.'
            }
        }
    }
    finally { Remove-Item -LiteralPath $verificationDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    return $plan
}

if (!(Test-Administrator)) { throw 'This workflow requires an elevated Windows PowerShell session.' }

if ($Mode -ceq 'Prepare') {
    if ([string]::IsNullOrWhiteSpace($BackupDirectory) -or (Test-Path -LiteralPath $BackupDirectory)) {
        throw 'Prepare requires a new BackupDirectory on non-target storage.'
    }
    $targets = Get-RepairTarget
    $backupFullPath = [IO.Path]::GetFullPath($BackupDirectory)
    if ($backupFullPath -notmatch '^([A-Za-z]):\\') { throw 'BackupDirectory must be drive-rooted.' }
    $backupPartition = Get-Partition -DriveLetter $Matches[1] -ErrorAction Stop
    if ($backupPartition.DiskNumber -eq $targets.Disk.Number) {
        throw 'BackupDirectory must be on non-target storage.'
    }
    New-Item -ItemType Directory -Path $backupFullPath | Out-Null
    $payload = Join-Path $backupFullPath 'payload'
    New-Item -ItemType Directory -Path $payload | Out-Null
    Use-EfiMount -Partition $targets.Efi -Action {
        param($efiRoot)
        $efiTree = Join-Path $payload 'EfiTree'
        New-Item -ItemType Directory -Path $efiTree | Out-Null
        Copy-Item -Path (Join-Path $efiRoot '*') -Destination $efiTree -Recurse -Force
        $bcdPath = Join-Path $efiRoot 'EFI\Microsoft\Boot\BCD'
        if (!(Test-Path -LiteralPath $bcdPath -PathType Leaf)) { throw 'EFI BCD store was not found.' }
        & bcdedit.exe '/store' $bcdPath '/enum' 'all' | Set-Content -LiteralPath (Join-Path $payload 'bcd-evidence.txt') -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw 'BCD evidence enumeration failed.' }
    }
    $files = @(Get-ChildItem -LiteralPath $payload -File -Recurse -Force | ForEach-Object {
        [ordered]@{
            RelativePath = $_.FullName.Substring($payload.Length).TrimStart('\')
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            Size = $_.Length
        }
    })
    $BackupManifest = [ordered]@{
        SchemaVersion = 1
        TargetFingerprint = $targets.TargetFingerprint
        Files = $files
        RecoveryMaterialIncluded = $false
    }
    $manifestPath = Join-Path $backupFullPath 'BackupManifest.json'
    $BackupManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $payload 'BackupManifest.json')
    $archivePath = "$backupFullPath.zip"
    if (Test-Path -LiteralPath $archivePath) { throw 'Rollback archive path already exists.' }
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $archivePath
    $proofDirectory = Join-Path ([IO.Path]::GetTempPath()) ("CodexRescueBackupProof-{0}" -f [guid]::NewGuid())
    try {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $proofDirectory
        if (!(Test-Path -LiteralPath (Join-Path $proofDirectory 'BackupManifest.json') -PathType Leaf)) {
            throw 'Backup read proof failed.'
        }
    }
    finally { Remove-Item -LiteralPath $proofDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    $suffix = $targets.TargetFingerprint.Substring($targets.TargetFingerprint.Length - 8)
    $plan = [ordered]@{
        SchemaVersion = 1
        ContractType = 'ActionPlanV1'
        ActionType = 'RepairUefi'
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        DiskNumber = $targets.Disk.Number
        WindowsPartitionNumber = $targets.Windows.PartitionNumber
        EfiPartitionNumber = $targets.Efi.PartitionNumber
        WindowsDrive = [string]$targets.Windows.DriveLetter
        TargetFingerprint = $targets.TargetFingerprint
        BackupArchivePath = $archivePath
        BackupArchiveSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        BackupVerified = $true
        RequiredConfirmationPhrase = "REPAIR UEFI $suffix"
        RequiredRollbackPhrase = "ROLLBACK UEFI $suffix"
        WritePerformed = $false
    }
    $PlanPath = Join-Path $backupFullPath 'repair-plan.json'
    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PlanPath -Encoding UTF8
    return [pscustomobject]$plan
}

$savedPlan = Read-VerifiedPlan
$currentTargets = Get-RepairTarget
if ($currentTargets.TargetFingerprint -cne $savedPlan.TargetFingerprint) {
    throw 'Identity changed; the prepared approval is invalid.'
}
$requiredPhrase = if ($Mode -ceq 'Rollback') { $savedPlan.RequiredRollbackPhrase } else { $savedPlan.RequiredConfirmationPhrase }
if ($ConfirmationPhrase -cne $requiredPhrase) { throw 'The target-bound confirmation phrase does not match.' }
if ([string]::IsNullOrWhiteSpace($OutputReceiptPath) -or (Test-Path -LiteralPath $OutputReceiptPath)) {
    throw 'A new non-target OutputReceiptPath is required.'
}
$receiptFullPath = [IO.Path]::GetFullPath($OutputReceiptPath)
if ($receiptFullPath -match '^([A-Za-z]):\\') {
    $receiptPartition = Get-Partition -DriveLetter $Matches[1] -ErrorAction SilentlyContinue
    if ($null -ne $receiptPartition -and $receiptPartition.DiskNumber -eq $currentTargets.Disk.Number) {
        throw 'OutputReceiptPath must be on non-target storage.'
    }
}
$actionDescription = if ($Mode -ceq 'Apply') { 'Run minimal BCDBoot repair' } else { 'Rollback Microsoft boot subtree' }
if (!$PSCmdlet.ShouldProcess("UEFI target $($savedPlan.TargetFingerprint)", $actionDescription)) { return }

Use-EfiMount -Partition $currentTargets.Efi -Action {
    param($efiRoot)
    if ($Mode -ceq 'Apply') {
        $arguments = @("$($savedPlan.WindowsDrive):\Windows", '/s', $efiRoot.TrimEnd('\'), '/f', 'UEFI', '/v')
        & bcdboot.exe @arguments | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "bcdboot.exe failed with exit code $LASTEXITCODE." }
    }
    else {
        $restoreRoot = Join-Path ([IO.Path]::GetTempPath()) ("CodexRescueRollback-{0}" -f [guid]::NewGuid())
        try {
            Expand-Archive -LiteralPath $savedPlan.BackupArchivePath -DestinationPath $restoreRoot
            $savedMicrosoftBoot = Join-Path $restoreRoot 'EfiTree\EFI\Microsoft\Boot'
            if (!(Test-Path -LiteralPath $savedMicrosoftBoot -PathType Container)) { throw 'Rollback package lacks the Microsoft boot subtree.' }
            $currentMicrosoftBoot = Join-Path $efiRoot 'EFI\Microsoft\Boot'
            $failedState = Join-Path $efiRoot ("EFI\Microsoft\Boot.failed-{0}" -f (Get-Date -Format 'yyyyMMddHHmmss'))
            if (Test-Path -LiteralPath $currentMicrosoftBoot) { Move-Item -LiteralPath $currentMicrosoftBoot -Destination $failedState }
            Copy-Item -LiteralPath $savedMicrosoftBoot -Destination $currentMicrosoftBoot -Recurse
        }
        finally { Remove-Item -LiteralPath $restoreRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $bcdPath = Join-Path $efiRoot 'EFI\Microsoft\Boot\BCD'
    if (!(Test-Path -LiteralPath $bcdPath -PathType Leaf)) { throw 'Post-action BCD store is missing.' }
    & bcdedit.exe '/store' $bcdPath '/enum' '{bootmgr}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Post-action BCD verification failed.' }
}

$receipt = [ordered]@{
    SchemaVersion = 1
    ContractType = 'ActionReceiptV1'
    ActionType = if ($Mode -ceq 'Apply') { 'RepairUefi' } else { 'RollbackUefi' }
    Result = 'Succeeded'
    NormalizedErrorCode = 'NONE'
    TargetFingerprint = [string]$savedPlan.TargetFingerprint
    BackupArchiveSha256 = [string]$savedPlan.BackupArchiveSha256
    ChangesMade = if ($Mode -ceq 'Apply') { @('Rebuilt selected UEFI boot files with BCDBoot') } else { @('Restored backed-up Microsoft UEFI boot subtree') }
    RestartState = 'RequiredForBootTest'
    PrivacyDeclaration = 'No credentials or recovery material are included.'
    CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputReceiptPath -Encoding UTF8
[pscustomobject]$receipt
