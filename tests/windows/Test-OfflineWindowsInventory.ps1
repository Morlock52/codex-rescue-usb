<#
.SYNOPSIS
Runs the offline Windows inventory against disposable mapped-drive fixtures.

.DESCRIPTION
Creates two temporary directories, maps them to otherwise-unused drive letters,
and verifies the generated JSON through the public file contract. The real
Windows volume is only probed read-only and no fixture data survives cleanup.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceDrive = 'Y'
$destinationDrive = 'Z'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'CodexRescueInventoryTest-{0}' -f [guid]::NewGuid()
)
$sourceRoot = Join-Path $temporaryRoot 'source'
$destinationRoot = Join-Path $temporaryRoot 'destination'
$mappedDrives = @()

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (!$Condition) {
        throw $Message
    }
}

try {
    foreach ($driveLetter in @($sourceDrive, $destinationDrive)) {
        if (Test-Path -LiteralPath ('{0}:\' -f $driveLetter)) {
            throw ('Fixture drive {0}: is already in use.' -f $driveLetter)
        }
    }

    New-Item -ItemType Directory -Path $sourceRoot, $destinationRoot | Out-Null
    & subst.exe ('{0}:' -f $sourceDrive) $sourceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not map the source fixture drive.' }
    $mappedDrives += $sourceDrive
    & subst.exe ('{0}:' -f $destinationDrive) $destinationRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not map the destination fixture drive.' }
    $mappedDrives += $destinationDrive

    $fixturePaths = @(
        ('{0}:\Windows\System32\config' -f $sourceDrive),
        ('{0}:\Windows\System32\winevt\Logs' -f $sourceDrive),
        ('{0}:\Boot' -f $sourceDrive),
        ('{0}:\Users\SensitiveFixtureName\Documents' -f $sourceDrive),
        ('{0}:\Users\SensitiveFixtureName\Downloads' -f $sourceDrive),
        ('{0}:\CodexRescueEvidence' -f $destinationDrive)
    )
    New-Item -ItemType Directory -Path $fixturePaths -Force | Out-Null
    New-Item -ItemType File -Path @(
        ('{0}:\Windows\System32\ntoskrnl.exe' -f $sourceDrive),
        ('{0}:\Windows\System32\config\SYSTEM' -f $sourceDrive),
        ('{0}:\Windows\System32\config\SOFTWARE' -f $sourceDrive),
        ('{0}:\Windows\System32\winevt\Logs\Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Autopilot.evtx' -f $sourceDrive),
        ('{0}:\Windows\System32\winevt\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Admin.evtx' -f $sourceDrive),
        ('{0}:\CODEX_EVIDENCE.DEST' -f $destinationDrive)
    ) -Force | Out-Null
    & bcdedit.exe '/export' ('{0}:\Boot\BCD' -f $sourceDrive) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the disposable BCD fixture.' }

    $outputPath = '{0}:\CodexRescueEvidence\windows-installations.json' -f $destinationDrive
    $collectorArguments = @{
        OutputPath = $outputPath
        DestinationDriveLetter = $destinationDrive
    }
    & (Join-Path $PSScriptRoot '..\..\winpe\Collect-OfflineWindowsInventory.ps1') @collectorArguments
    $inventoryText = Get-Content -LiteralPath $outputPath -Raw
    $inventory = $inventoryText | ConvertFrom-Json
    $fixture = @($inventory.WindowsInstallations | Where-Object InstallationAlias -CEQ 'Windows-Y')
    $hostWindows = @($inventory.WindowsInstallations | Where-Object InstallationAlias -CEQ 'Windows-C')
    $fixtureBootStore = @($inventory.OfflineBootStores | Where-Object StoreAlias -CEQ 'BootStore-Y-Boot')

    Assert-True ($fixture.Count -eq 1) 'The disposable Windows fixture was not identified exactly once.'
    Assert-True ($hostWindows.Count -eq 1) 'The host Windows installation was not identified exactly once.'
    Assert-True ($fixtureBootStore.Count -eq 1) 'The disposable BCD store was not identified exactly once.'
    Assert-True ($fixtureBootStore[0].EnumerationSucceeded -eq $true) 'The disposable BCD store was not enumerated.'
    Assert-True ($fixtureBootStore[0].EntryCount -gt 0) 'The disposable BCD summary has no entries.'
    Assert-True ($fixtureBootStore[0].RawBcdOutputIncluded -eq $false) 'Raw BCD output was not explicitly withheld.'
    Assert-True ($fixture[0].ProfileCount -eq 1) 'The fixture profile count is incorrect.'
    Assert-True ($fixture[0].Profiles[0].ProfileAlias -ceq 'Profile-01') 'The profile alias is incorrect.'
    Assert-True ($fixture[0].Profiles[0].KnownFoldersPresent -contains 'Documents') 'Documents metadata is missing.'
    Assert-True ($fixture[0].Profiles[0].KnownFoldersPresent -contains 'Downloads') 'Downloads metadata is missing.'
    Assert-True ($inventoryText -notmatch 'SensitiveFixtureName') 'A source profile name leaked into the inventory.'
    Assert-True ($inventory.UserNamesIncluded -eq $false) 'The top-level username privacy flag is not false.'
    Assert-True ($inventory.RawEventPayloadsIncluded -eq $false) 'The raw-event privacy flag is not false.'
    Assert-True ($inventory.RecoveryMaterialIncluded -eq $false) 'The recovery-material privacy flag is not false.'
    Assert-True ($hostWindows[0].ManagementIndicators.AutopilotEventLog.EventMessagesIncluded -eq $false) 'Autopilot event messages were not explicitly withheld.'
    Assert-True ($hostWindows[0].ManagementIndicators.MdmAdminEventLog.EventMessagesIncluded -eq $false) 'MDM event messages were not explicitly withheld.'

    $overwriteRejected = $false
    try {
        & (Join-Path $PSScriptRoot '..\..\winpe\Collect-OfflineWindowsInventory.ps1') @collectorArguments
    }
    catch {
        $overwriteRejected = $_.Exception.Message -match 'already exists'
    }
    Assert-True $overwriteRejected 'The collector did not reject an existing inventory.'

    $evidenceDirectory = Split-Path -Parent $outputPath
    foreach ($name in @(
        'bcd.txt',
        'bitlocker-status.txt',
        'diskpart.txt',
        'drivers.txt',
        'event-log-index.txt',
        'network.txt',
        'README.txt'
    )) {
        Set-Content -LiteralPath (Join-Path $evidenceDirectory $name) -Value 'fixture' -Encoding ASCII
    }
    & (Join-Path $PSScriptRoot '..\..\winpe\New-EvidenceManifest.ps1') -OutputDirectory $evidenceDirectory | Out-Null
    $summaryPath = '{0}:\CodexRescueSummary.md' -f $destinationDrive
    & (Join-Path $PSScriptRoot '..\..\scripts\New-CodexEvidenceSummary.ps1') `
        -EvidenceDirectory $evidenceDirectory `
        -OutputPath $summaryPath | Out-Null
    $summaryText = Get-Content -LiteralPath $summaryPath -Raw
    Assert-True ($summaryText -match 'OfflineWindowsInventoryCaptured: True') 'The summary omitted the inventory state.'
    Assert-True ($summaryText -notmatch 'SensitiveFixtureName') 'A fixture profile name leaked into the summary.'

    $inventory.PSObject.Properties.Remove('UserNamesIncluded')
    $inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8
    & (Join-Path $PSScriptRoot '..\..\winpe\New-EvidenceManifest.ps1') -OutputDirectory $evidenceDirectory | Out-Null
    $missingPrivacyFlagRejected = $false
    try {
        & (Join-Path $PSScriptRoot '..\..\scripts\New-CodexEvidenceSummary.ps1') `
            -EvidenceDirectory $evidenceDirectory `
            -OutputPath ('{0}:\RejectedSummary.md' -f $destinationDrive) | Out-Null
    }
    catch {
        $missingPrivacyFlagRejected = $_.Exception.Message -match 'must declare UserNamesIncluded'
    }
    Assert-True $missingPrivacyFlagRejected 'The summary accepted a missing privacy declaration.'

    [pscustomobject]@{
        Result = 'PASS'
        FixtureInstallationFound = $true
        HostWindowsInstallationFound = $true
        FixtureBootStoreEnumerated = $true
        FixtureBootEntryCountPositive = $true
        HostAutopilotLogPresent = [bool]$hostWindows[0].ManagementIndicators.AutopilotEventLog.Present
        HostAutopilotSampleReadSucceeded = [bool]$hostWindows[0].ManagementIndicators.AutopilotEventLog.SampleReadSucceeded
        HostMdmAdminLogPresent = [bool]$hostWindows[0].ManagementIndicators.MdmAdminEventLog.Present
        HostMdmAdminSampleReadSucceeded = [bool]$hostWindows[0].ManagementIndicators.MdmAdminEventLog.SampleReadSucceeded
        ProfileNameWithheld = $true
        ExistingOutputRejected = $true
        MissingPrivacyFlagRejected = $true
    } | Format-List
}
finally {
    foreach ($driveLetter in $mappedDrives) {
        & subst.exe ('{0}:' -f $driveLetter) /d | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw ('Could not remove fixture drive {0}: during cleanup.' -f $driveLetter)
        }
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        throw 'The offline Windows inventory fixture directory survived cleanup.'
    }
}
