<#
.SYNOPSIS
Creates an allowlisted, aggregate summary from a verified evidence package.

.DESCRIPTION
Validates either the legacy nine-file or current ten-file Codex Rescue evidence
package against manifest.json and SHA256SUMS.txt, rejects recovery-key files and
recovery-password-shaped text, and writes a new Markdown summary outside the
source package. The summary never copies raw disk, network, BCD, driver,
event-log, offline-Windows, or BitLocker output.

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

function Assert-ExplicitFalse {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or
        $property.Value -isnot [bool] -or
        $property.Value -ne $false) {
        throw "$Context must declare $PropertyName as the Boolean value false."
    }
}

$baseDiagnosticFiles = @(
    'bcd.txt',
    'bitlocker-status.txt',
    'diskpart.txt',
    'drivers.txt',
    'event-log-index.txt',
    'network.txt',
    'README.txt'
)
$offlineWindowsInventoryFile = 'windows-installations.json'
$legacyPackageFiles = @($baseDiagnosticFiles + 'manifest.json' + 'SHA256SUMS.txt')
$currentPackageFiles = @(
    $baseDiagnosticFiles + $offlineWindowsInventoryFile + 'manifest.json' + 'SHA256SUMS.txt'
)
$actualEntries = @(Get-ChildItem -LiteralPath $evidenceRoot -Force)
if (@($actualEntries | Where-Object { !($_ -is [IO.FileInfo]) }).Count) {
    throw 'The evidence package must not contain directories or other non-file entries. No summary was written.'
}
$actualFiles = @(
    $actualEntries |
        Select-Object -ExpandProperty Name |
        Sort-Object
)
$legacySorted = @($legacyPackageFiles | Sort-Object)
$currentSorted = @($currentPackageFiles | Sort-Object)
if (($actualFiles -join "`n") -ceq ($currentSorted -join "`n")) {
    $expectedDiagnosticFiles = @($baseDiagnosticFiles + $offlineWindowsInventoryFile)
    $expectedPackageFiles = $currentPackageFiles
}
elseif (($actualFiles -join "`n") -ceq ($legacySorted -join "`n")) {
    $expectedDiagnosticFiles = $baseDiagnosticFiles
    $expectedPackageFiles = $legacyPackageFiles
}
else {
    throw 'The evidence package must contain exactly the nine-file legacy or ten-file current allowlist. No summary was written.'
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
    throw "Expected $($expectedDiagnosticFiles.Count) diagnostic manifest entries; found $($manifestEntries.Count)."
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
$expectedChecksumCount = $expectedDiagnosticFiles.Count + 1
if ($checksumEntries.Count -ne $expectedChecksumCount) {
    throw "Expected $expectedChecksumCount checksum entries; found $($checksumEntries.Count)."
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
$offlineWindowsInventoryCaptured = $expectedDiagnosticFiles -contains $offlineWindowsInventoryFile
$offlineWindowsInstallationCount = 0
$offlineUserProfileCount = 0
$autopilotEventLogPresentCount = 0
$mdmAdminEventLogPresentCount = 0
$autopilotEventCountSampled = 0
$autopilotCriticalCount = 0
$autopilotErrorCount = 0
$autopilotWarningCount = 0
$mdmAdminEventCountSampled = 0
$mdmAdminCriticalCount = 0
$mdmAdminErrorCount = 0
$mdmAdminWarningCount = 0
$offlineBootStorePresentCount = 0
$offlineBootStoreEnumeratedCount = 0
$offlineBootEntryCount = 0
$existingMdmDiagnosticsDirectoryCount = 0
$intuneManagementExtensionLogDirectoryCount = 0
if ($offlineWindowsInventoryCaptured) {
    $offlineInventoryPath = Join-Path $evidenceRoot $offlineWindowsInventoryFile
    $offlineInventory = Get-Content -LiteralPath $offlineInventoryPath -Raw | ConvertFrom-Json
    if ($offlineInventory.SchemaVersion -ne 1 -or
        $offlineInventory.CollectionMode -cne 'read-only offline Windows inventory') {
        throw 'The offline Windows inventory schema or collection mode is invalid.'
    }
    foreach ($privacyProperty in @(
        'UserNamesIncluded',
        'RawEventPayloadsIncluded',
        'EventMessagesIncluded',
        'RawBcdOutputIncluded',
        'RecoveryMaterialIncluded'
    )) {
        Assert-ExplicitFalse -InputObject $offlineInventory -PropertyName $privacyProperty -Context (
            'The offline Windows inventory'
        )
    }
    $offlineInstallations = @($offlineInventory.WindowsInstallations)
    $offlineWindowsInstallationCount = $offlineInstallations.Count
    if ([int]$offlineInventory.WindowsInstallationCount -ne $offlineWindowsInstallationCount) {
        throw 'The offline Windows installation count is inconsistent.'
    }
    $offlineBootStores = @($offlineInventory.OfflineBootStores)
    if ([int]$offlineInventory.OfflineBootStoreCount -ne $offlineBootStores.Count) {
        throw 'The offline boot-store count is inconsistent.'
    }
    foreach ($bootStore in $offlineBootStores) {
        Assert-ExplicitFalse -InputObject $bootStore -PropertyName 'RawBcdOutputIncluded' -Context (
            'Each offline boot-store inventory'
        )
    }
    $offlineBootStorePresentCount = @($offlineBootStores | Where-Object Present -eq $true).Count
    $offlineBootStoreEnumeratedCount = @(
        $offlineBootStores | Where-Object EnumerationSucceeded -eq $true
    ).Count
    $offlineBootEntryCount = [int](
        $offlineBootStores | Measure-Object -Property EntryCount -Sum
    ).Sum
    foreach ($installation in $offlineInstallations) {
        foreach ($privacyProperty in @('UserNamesIncluded', 'RawEventPayloadsIncluded')) {
            Assert-ExplicitFalse -InputObject $installation -PropertyName $privacyProperty -Context (
                'Each offline Windows installation'
            )
        }
        foreach ($managementEventLog in @(
            $installation.ManagementIndicators.AutopilotEventLog,
            $installation.ManagementIndicators.MdmAdminEventLog
        )) {
            foreach ($privacyProperty in @('EventMessagesIncluded', 'RawPayloadsIncluded')) {
                Assert-ExplicitFalse -InputObject $managementEventLog -PropertyName $privacyProperty -Context (
                    'Each management event-log inventory'
                )
            }
        }
        $profiles = @($installation.Profiles)
        if ([int]$installation.ProfileCount -ne $profiles.Count) {
            throw 'An offline Windows profile count is inconsistent.'
        }
        foreach ($profileEntry in $profiles) {
            foreach ($privacyProperty in @('FileNamesEnumerated', 'FileContentsRead')) {
                Assert-ExplicitFalse -InputObject $profileEntry -PropertyName $privacyProperty -Context (
                    'Each redacted profile inventory entry'
                )
            }
        }
    }
    $offlineUserProfileCount = [int](
        $offlineInstallations |
            Measure-Object -Property ProfileCount -Sum
    ).Sum
    $autopilotEventLogPresentCount = @(
        $offlineInstallations |
            Where-Object { $_.ManagementIndicators.AutopilotEventLog.Present -eq $true }
    ).Count
    $mdmAdminEventLogPresentCount = @(
        $offlineInstallations |
            Where-Object { $_.ManagementIndicators.MdmAdminEventLog.Present -eq $true }
    ).Count
    $autopilotEventCountSampled = [int](
        $offlineInstallations.ManagementIndicators.AutopilotEventLog |
            Measure-Object -Property EventCountSampled -Sum
    ).Sum
    $autopilotCriticalCount = [int](
        $offlineInstallations.ManagementIndicators.AutopilotEventLog |
            Measure-Object -Property CriticalCount -Sum
    ).Sum
    $autopilotErrorCount = [int](
        $offlineInstallations.ManagementIndicators.AutopilotEventLog |
            Measure-Object -Property ErrorCount -Sum
    ).Sum
    $autopilotWarningCount = [int](
        $offlineInstallations.ManagementIndicators.AutopilotEventLog |
            Measure-Object -Property WarningCount -Sum
    ).Sum
    $mdmAdminEventCountSampled = [int](
        $offlineInstallations.ManagementIndicators.MdmAdminEventLog |
            Measure-Object -Property EventCountSampled -Sum
    ).Sum
    $mdmAdminCriticalCount = [int](
        $offlineInstallations.ManagementIndicators.MdmAdminEventLog |
            Measure-Object -Property CriticalCount -Sum
    ).Sum
    $mdmAdminErrorCount = [int](
        $offlineInstallations.ManagementIndicators.MdmAdminEventLog |
            Measure-Object -Property ErrorCount -Sum
    ).Sum
    $mdmAdminWarningCount = [int](
        $offlineInstallations.ManagementIndicators.MdmAdminEventLog |
            Measure-Object -Property WarningCount -Sum
    ).Sum
    $existingMdmDiagnosticsDirectoryCount = @(
        $offlineInstallations |
            Where-Object { $_.ManagementIndicators.ExistingMdmDiagnostics.Present -eq $true }
    ).Count
    $intuneManagementExtensionLogDirectoryCount = @(
        $offlineInstallations |
            Where-Object { $_.ManagementIndicators.IntuneManagementExtensionLogs.Present -eq $true }
    ).Count
}
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
    "- OfflineWindowsInventoryCaptured: $offlineWindowsInventoryCaptured",
    "- OfflineWindowsInstallationCount: $offlineWindowsInstallationCount",
    "- OfflineUserProfileCount: $offlineUserProfileCount",
    "- OfflineBootStorePresentCount: $offlineBootStorePresentCount",
    "- OfflineBootStoreEnumeratedCount: $offlineBootStoreEnumeratedCount",
    "- OfflineBootEntryCount: $offlineBootEntryCount",
    "- AutopilotEventLogPresentCount: $autopilotEventLogPresentCount",
    "- AutopilotEventCountSampled: $autopilotEventCountSampled",
    "- AutopilotCriticalCount: $autopilotCriticalCount",
    "- AutopilotErrorCount: $autopilotErrorCount",
    "- AutopilotWarningCount: $autopilotWarningCount",
    "- MdmAdminEventLogPresentCount: $mdmAdminEventLogPresentCount",
    "- MdmAdminEventCountSampled: $mdmAdminEventCountSampled",
    "- MdmAdminCriticalCount: $mdmAdminCriticalCount",
    "- MdmAdminErrorCount: $mdmAdminErrorCount",
    "- MdmAdminWarningCount: $mdmAdminWarningCount",
    "- ExistingMdmDiagnosticsDirectoryCount: $existingMdmDiagnosticsDirectoryCount",
    "- IntuneManagementExtensionLogDirectoryCount: $intuneManagementExtensionLogDirectoryCount",
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
    OfflineWindowsInventoryCaptured = $offlineWindowsInventoryCaptured
    OfflineWindowsInstallationCount = $offlineWindowsInstallationCount
    OfflineUserProfileCount = $offlineUserProfileCount
    OfflineBootStorePresentCount = $offlineBootStorePresentCount
    OfflineBootStoreEnumeratedCount = $offlineBootStoreEnumeratedCount
    OfflineBootEntryCount = $offlineBootEntryCount
    AutopilotEventLogPresentCount = $autopilotEventLogPresentCount
    AutopilotEventCountSampled = $autopilotEventCountSampled
    AutopilotErrorCount = $autopilotErrorCount
    AutopilotWarningCount = $autopilotWarningCount
    MdmAdminEventLogPresentCount = $mdmAdminEventLogPresentCount
    MdmAdminEventCountSampled = $mdmAdminEventCountSampled
    MdmAdminErrorCount = $mdmAdminErrorCount
    MdmAdminWarningCount = $mdmAdminWarningCount
    OperatorReviewRequired = $true
} | Format-List
