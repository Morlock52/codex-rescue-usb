[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ContractFixturePath,
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

function Assert-JsonBoolean {
    param(
        [Parameter(Mandatory = $true)][psobject]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($Object.$Name -isnot [bool]) {
        throw "Discovery property '$Name' must be a JSON boolean."
    }
}

if ($AsJson -and $OutputPath) {
    throw 'Choose either -AsJson or -OutputPath, not both.'
}
if (-not (Test-Path -LiteralPath $ContractFixturePath -PathType Leaf)) {
    throw "Contract fixture was not found: $ContractFixturePath"
}

$rawEvidence = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ContractFixturePath).Path)
foreach ($secretPattern in @(
    '(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)',
    '(?i)\.bek(?:\b|\")',
    '(?i)bearer\s+[a-z0-9._~+\/-]+=*',
    '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
)) {
    if ($rawEvidence -match $secretPattern) {
        throw 'Discovery input contains recovery material or other secret-bearing evidence.'
    }
}

try {
    $evidence = $rawEvidence | ConvertFrom-Json
}
catch {
    throw "Contract fixture is not valid JSON: $($_.Exception.Message)"
}

$expectedProperties = @(
    'SchemaVersion', 'EvidenceSha256', 'EvidenceIntegrityVerified',
    'ContainsRecoveryMaterial', 'ContainsSensitiveRawEvidence', 'StorageHealth',
    'BitLockerState', 'FirmwareType', 'WindowsDirectory', 'WindowsDirectoryVerified',
    'WindowsDiskUniqueId', 'EfiSystemPartition', 'EfiPartitionVerified',
    'EfiFileSystem', 'EfiDiskUniqueId', 'RollbackArtifactType',
    'RollbackArtifactPath', 'RollbackArtifactSha256', 'RollbackArtifactVerified',
    'RollbackRestoreTested'
)
$actualProperties = @($evidence.PSObject.Properties.Name)
$missing = @($expectedProperties | Where-Object { $_ -notin $actualProperties })
$unexpected = @($actualProperties | Where-Object { $_ -notin $expectedProperties })
if ($missing.Count -gt 0) {
    throw "Contract fixture is missing required properties: $($missing -join ', ')"
}
if ($unexpected.Count -gt 0) {
    throw "Contract fixture contains unexpected properties: $($unexpected -join ', ')"
}

foreach ($booleanName in @(
    'EvidenceIntegrityVerified', 'ContainsRecoveryMaterial',
    'ContainsSensitiveRawEvidence', 'WindowsDirectoryVerified',
    'EfiPartitionVerified', 'RollbackArtifactVerified', 'RollbackRestoreTested'
)) {
    Assert-JsonBoolean -Object $evidence -Name $booleanName
}

if ($evidence.SchemaVersion -ne 1) {
    throw 'Only discovery contract schema version 1 is supported.'
}
if ($evidence.EvidenceSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'EvidenceSha256 must be a 64-character SHA-256 hexadecimal digest.'
}
if (-not $evidence.EvidenceIntegrityVerified) {
    throw 'Evidence integrity must be verified before a proposal can be produced.'
}
if ($evidence.ContainsRecoveryMaterial -or $evidence.ContainsSensitiveRawEvidence) {
    throw 'Discovery input contains recovery material or sensitive raw evidence.'
}
if ($evidence.StorageHealth -cne 'Healthy') {
    throw 'Storage health must be Healthy; an unhealthy disk is a stop condition.'
}
if ($evidence.BitLockerState -cne 'Unlocked') {
    throw 'The Windows volume must already be Unlocked; this proposal never handles recovery material.'
}
if ($evidence.FirmwareType -cne 'UEFI') {
    throw 'This contract supports UEFI firmware only.'
}
if ($evidence.WindowsDirectory -notmatch '^[A-WYZ]:\\Windows$' -or -not $evidence.WindowsDirectoryVerified) {
    throw 'WindowsDirectory must be verified, drive-rooted, and cannot use the WinPE X: drive.'
}
if ($evidence.WindowsDiskUniqueId -notmatch '^[A-Za-z0-9._:-]{1,128}$') {
    throw 'WindowsDiskUniqueId is missing or contains unsupported characters.'
}
if ($evidence.EfiSystemPartition -notmatch '^[A-Z]:$' -or $evidence.EfiSystemPartition -in @('C:', 'X:')) {
    throw 'EfiSystemPartition must be an explicit temporary drive letter other than C: or X:.'
}
if (-not $evidence.EfiPartitionVerified -or $evidence.EfiFileSystem -cne 'FAT32') {
    throw 'The EFI System Partition must be independently verified and use FAT32.'
}
if ($evidence.EfiDiskUniqueId -cne $evidence.WindowsDiskUniqueId) {
    throw 'same explicitly identified disk'
}
if ($evidence.RollbackArtifactType -cne 'EfiMicrosoftBootDirectoryBackup') {
    throw 'RollbackArtifactType must be EfiMicrosoftBootDirectoryBackup.'
}
if ($evidence.RollbackArtifactPath -notmatch '^[A-WYZ]:\\.+\.zip$') {
    throw 'RollbackArtifactPath must identify a ZIP archive outside the WinPE X: drive.'
}
if ($evidence.RollbackArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'RollbackArtifactSha256 must be a SHA-256 hexadecimal digest.'
}
if (-not $evidence.RollbackArtifactVerified) {
    throw 'A verified rollback artifact is required.'
}
if (-not $evidence.RollbackRestoreTested) {
    throw 'A restore-tested rollback artifact is required before proposing boot repair.'
}

$arguments = @([string]$evidence.WindowsDirectory, '/s', [string]$evidence.EfiSystemPartition, '/f', 'UEFI', '/v')
$target = [ordered]@{
    WindowsDiskUniqueId = [string]$evidence.WindowsDiskUniqueId
    EfiDiskUniqueId = [string]$evidence.EfiDiskUniqueId
    WindowsDirectory = [string]$evidence.WindowsDirectory
    EfiSystemPartition = [string]$evidence.EfiSystemPartition
    EfiFileSystem = [string]$evidence.EfiFileSystem
}
$targetFingerprint = Get-Sha256Hex -Text ($target | ConvertTo-Json -Compress)
$proposalCore = [ordered]@{
    SchemaVersion = 1
    EvidenceSha256 = ([string]$evidence.EvidenceSha256).ToUpperInvariant()
    Operation = 'windows.bootfiles.rebuild.uefi'
    PermittedExecutable = 'bcdboot.exe'
    Arguments = $arguments
    TargetFingerprint = $targetFingerprint
    RollbackSha256 = ([string]$evidence.RollbackArtifactSha256).ToUpperInvariant()
}
$proposalDigest = Get-Sha256Hex -Text ($proposalCore | ConvertTo-Json -Compress -Depth 4)

$plan = [ordered]@{
    SchemaVersion = 1
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    EvidenceSource = 'ContractFixture'
    LiveEvidence = $false
    EvidenceSha256 = ([string]$evidence.EvidenceSha256).ToUpperInvariant()
    PlanOnly = $true
    ReadyForApproval = $false
    ApprovalRequired = $true
    ApprovalRecorded = $false
    ExecutionAvailable = $false
    WritePerformed = $false
    RequiredConfirmationToken = $null
    Operation = 'windows.bootfiles.rebuild.uefi'
    PermittedExecutable = 'bcdboot.exe'
    Arguments = $arguments
    FirmwareNvramWriteExpected = $false
    BootExRequested = $false
    BootExDecision = 'Excluded; Secure Boot servicing is a separate evidence-gated decision.'
    Target = $target
    TargetFingerprint = $targetFingerprint
    Rollback = [ordered]@{
        ArtifactType = [string]$evidence.RollbackArtifactType
        ArtifactPath = [string]$evidence.RollbackArtifactPath
        ArtifactSha256 = ([string]$evidence.RollbackArtifactSha256).ToUpperInvariant()
        Verified = $true
        RestoreTested = $true
    }
    StopConditions = @(
        'Evidence digest or target fingerprint changes.',
        'Windows and EFI volumes no longer resolve to the same disk.',
        'Storage health is not Healthy or BitLocker is not already Unlocked.',
        'Rollback verification or restore-test evidence is unavailable.',
        'The operator has not reviewed a fresh live-evidence proposal.'
    )
    VerificationPlan = @(
        'Re-run read-only discovery and compare the target fingerprint.',
        'Verify the EFI boot files without changing firmware order.',
        'Boot a disposable test VM and retain its console and evidence bundle.',
        'Exercise the documented rollback before physical-media validation.'
    )
    ProposalDigest = $proposalDigest
}

$json = $plan | ConvertTo-Json -Depth 8
if ($OutputPath) {
    if ([System.IO.Path]::GetExtension($OutputPath) -cne '.json') {
        throw 'OutputPath must use the .json extension.'
    }
    if (Test-Path -LiteralPath $OutputPath) {
        throw "Safety contract refuses to overwrite an existing proposal: $OutputPath"
    }
    $parentPath = Split-Path -Parent $OutputPath
    if (-not $parentPath) { $parentPath = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "Output directory does not exist: $parentPath"
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $outputStream = [System.IO.File]::Open(
        $OutputPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    $writer = $null
    try {
        $writer = New-Object System.IO.StreamWriter($outputStream, $utf8WithoutBom)
        $writer.Write($json)
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        else {
            $outputStream.Dispose()
        }
    }
    Write-Output "Wrote inert UEFI boot-repair proposal: $OutputPath"
}
elseif ($AsJson) {
    Write-Output $json
}
else {
    Write-Output ([pscustomobject]$plan)
}
