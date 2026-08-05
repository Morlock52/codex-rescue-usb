<#
.SYNOPSIS
Creates an allowlisted, aggregate summary from a verified evidence package.

.DESCRIPTION
Validates the nine-file Codex Rescue evidence package against manifest.json and
SHA256SUMS.txt, rejects recovery-key files and recovery-password-shaped text,
and writes a new Markdown summary outside the source package. The summary never
copies raw disk, network, BCD, driver, event-log, or BitLocker output.

.EXAMPLE
.\scripts\New-CodexEvidenceSummary.ps1 -EvidenceDirectory 'E:\CodexRescueEvidence'
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [string]$EvidenceDirectory,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$evidenceRoot = [IO.Path]::GetFullPath($EvidenceDirectory)
if (!(Test-Path -LiteralPath $evidenceRoot -PathType Container)) {
    throw "Evidence directory not found: $evidenceRoot"
}

$expectedDiagnosticFiles = @(
    'bcd.txt',
    'bitlocker-status.txt',
    'diskpart.txt',
    'drivers.txt',
    'event-log-index.txt',
    'network.txt',
    'README.txt'
)
$expectedPackageFiles = @($expectedDiagnosticFiles + 'manifest.json' + 'SHA256SUMS.txt')
$actualEntries = @(Get-ChildItem -LiteralPath $evidenceRoot -Force)
if (@($actualEntries | Where-Object { !($_ -is [IO.FileInfo]) }).Count) {
    throw 'The evidence package must not contain directories or other non-file entries. No summary was written.'
}
$actualFiles = @(
    $actualEntries |
        Select-Object -ExpandProperty Name |
        Sort-Object
)
$expectedSorted = @($expectedPackageFiles | Sort-Object)
if (($actualFiles -join "`n") -cne ($expectedSorted -join "`n")) {
    throw 'The evidence package must contain exactly the nine allowlisted files. No summary was written.'
}

$manifestPath = Join-Path $evidenceRoot 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.SchemaVersion -ne 1) {
    throw "Unsupported manifest schema: $($manifest.SchemaVersion)"
}
if ($manifest.CollectionMode -cne 'read-only diagnostics') {
    throw "Unexpected collection mode: $($manifest.CollectionMode)"
}
$manifestEntries = @($manifest.Files)
if ($manifestEntries.Count -ne $expectedDiagnosticFiles.Count) {
    throw "Expected seven diagnostic manifest entries; found $($manifestEntries.Count)."
}

foreach ($name in $expectedDiagnosticFiles) {
    $entry = @($manifestEntries | Where-Object Name -CEQ $name)
    if ($entry.Count -ne 1) {
        throw "Manifest must contain exactly one entry for $name."
    }
    $path = Join-Path $evidenceRoot $name
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [long]$entry[0].Length) {
        throw "Length mismatch for $name."
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -cne [string]$entry[0].Sha256) {
        throw "Manifest hash mismatch for $name."
    }
}

$checksumEntries = @()
foreach ($line in Get-Content -LiteralPath (Join-Path $evidenceRoot 'SHA256SUMS.txt')) {
    if ($line -notmatch '^(?<Hash>[A-Fa-f0-9]{64})  (?<Name>[^\\/:]+)$') {
        throw 'Malformed SHA256SUMS.txt entry.'
    }
    $checksumEntries += [pscustomobject]@{
        Hash = $Matches.Hash.ToUpperInvariant()
        Name = $Matches.Name
    }
}
if ($checksumEntries.Count -ne 8) {
    throw "Expected eight checksum entries; found $($checksumEntries.Count)."
}
$expectedChecksumNames = @($expectedDiagnosticFiles + 'manifest.json' | Sort-Object)
$actualChecksumNames = @($checksumEntries.Name | Sort-Object)
if (($actualChecksumNames -join "`n") -cne ($expectedChecksumNames -join "`n")) {
    throw 'SHA256SUMS.txt contains an unexpected or missing filename.'
}
foreach ($entry in $checksumEntries) {
    $path = Join-Path $evidenceRoot $entry.Name
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -cne $entry.Hash) {
        throw "Checksum-list hash mismatch for $($entry.Name)."
    }
}

$recoveryKeyFiles = @(
    Get-ChildItem -LiteralPath $evidenceRoot -File -Recurse -Force |
        Where-Object Extension -CEQ '.bek'
)
if ($recoveryKeyFiles.Count) {
    throw 'A recovery-key file exists inside the evidence package. No summary was written.'
}
$recoveryPasswordPattern = '(?<!\d)\d{6}(?:-\d{6}){7}(?!\d)'
foreach ($name in $expectedPackageFiles) {
    $text = Get-Content -LiteralPath (Join-Path $evidenceRoot $name) -Raw
    if ($text -match $recoveryPasswordPattern) {
        throw "Recovery-password-shaped text exists in $name. No summary was written."
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $evidenceRoot) 'CodexRescueSummary.md'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$directorySeparator = [IO.Path]::DirectorySeparatorChar
$alternateSeparator = [IO.Path]::AltDirectorySeparatorChar
$evidencePrefix = $evidenceRoot.TrimEnd($directorySeparator, $alternateSeparator) + $directorySeparator
if ($OutputPath.Equals($evidenceRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputPath.StartsWith($evidencePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to write the summary inside the source evidence package.'
}
if ((Test-Path -LiteralPath $OutputPath) -and !$Force) {
    throw "Summary already exists: $OutputPath. Re-run with -Force only after reviewing it."
}

$bitLockerText = Get-Content -LiteralPath (Join-Path $evidenceRoot 'bitlocker-status.txt') -Raw
$bitLockerCommandAvailable = $bitLockerText -notmatch '(?i)not recognized'
$bitLockerVolumeBlocks = ([regex]::Matches($bitLockerText, '(?m)^Volume [A-Z]:')).Count
$bitLockerLockStatusLines = ([regex]::Matches($bitLockerText, '(?m)^\s*Lock Status:')).Count
$eventLogLineCount = @(
    Get-Content -LiteralPath (Join-Path $evidenceRoot 'event-log-index.txt') |
        Where-Object { ![string]::IsNullOrWhiteSpace($_) }
).Count
$totalDiagnosticBytes = [long](
    $manifestEntries |
        Measure-Object -Property Length -Sum
).Sum
$sourceCreatedAtUtcAsRecorded = if ($manifest.CreatedAtUtc -is [datetime]) {
    $manifest.CreatedAtUtc.ToUniversalTime().ToString('o')
}
else {
    [string]$manifest.CreatedAtUtc
}

$summaryLines = @(
    '# Codex Rescue redacted evidence summary',
    '',
    "GeneratedAtUtc: $((Get-Date).ToUniversalTime().ToString('o'))",
    "SourceCreatedAtUtcAsRecorded: $sourceCreatedAtUtcAsRecorded",
    'SourceClockExternallyValidated: false',
    'SourcePackageIntegrityVerified: true',
    "ManifestSchemaVersion: $($manifest.SchemaVersion)",
    "DiagnosticFileCount: $($manifestEntries.Count)",
    "ChecksumEntryCount: $($checksumEntries.Count)",
    "TotalDiagnosticBytes: $totalDiagnosticBytes",
    '',
    '## Safe aggregate status',
    '',
    "- DiskInventoryCaptured: $([bool]($manifestEntries.Name -contains 'diskpart.txt'))",
    "- BootConfigurationCaptured: $([bool]($manifestEntries.Name -contains 'bcd.txt'))",
    "- DriverInventoryCaptured: $([bool]($manifestEntries.Name -contains 'drivers.txt'))",
    "- NetworkInventoryCapturedButWithheld: $([bool]($manifestEntries.Name -contains 'network.txt'))",
    "- EventLogIndexNonBlankLineCount: $eventLogLineCount",
    "- BitLockerCommandAvailable: $bitLockerCommandAvailable",
    "- BitLockerVolumeBlockCount: $bitLockerVolumeBlocks",
    "- BitLockerLockStatusLineCount: $bitLockerLockStatusLines",
    '',
    '## Excluded by design',
    '',
    'RawEvidenceIncluded: false',
    'RawNetworkDetailsIncluded: false',
    'DiskIdentifiersIncluded: false',
    'VolumeLabelsIncluded: false',
    'UserPathsIncluded: false',
    'RecoveryMaterialIncluded: false',
    'AutomaticCodexImport: false',
    'OperatorReviewRequiredBeforeSharing: true',
    '',
    'This summary contains aggregate availability and integrity state only. Review it before placing it in any online or model context.'
)

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write redacted Codex evidence summary')) {
    $parent = Split-Path -Parent $OutputPath
    if (!(Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    $summaryLines | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -Force:$Force
}

[pscustomobject]@{
    SchemaVersion = 1
    OutputPath = $OutputPath
    SourcePackageIntegrityVerified = $true
    RecoveryMaterialIncluded = $false
    RawEvidenceIncluded = $false
    BitLockerCommandAvailable = $bitLockerCommandAvailable
    BitLockerVolumeBlockCount = $bitLockerVolumeBlocks
    OperatorReviewRequired = $true
} | Format-List
