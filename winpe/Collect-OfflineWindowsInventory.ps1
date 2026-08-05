<#
.SYNOPSIS
Creates a redacted, read-only inventory of offline Windows installations.

.DESCRIPTION
Writes only to the already prepared Codex Rescue evidence directory. The
inventory is intentionally separate from raw event-log or registry export.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[D-WY-Zd-wy-z]$')]
    [string]$DestinationDriveLetter
)

$ErrorActionPreference = 'Stop'
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Get-Item -LiteralPath (Split-Path -Parent $OutputPath) -ErrorAction Stop
if (!$outputDirectory.PSIsContainer -or $outputDirectory.Name -ne 'CodexRescueEvidence') {
    throw 'The inventory output is not inside a CodexRescueEvidence directory.'
}
if (($outputDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The evidence directory must not be a reparse point.'
}
if ([IO.Path]::GetFileName($OutputPath) -cne 'windows-installations.json') {
    throw 'The inventory output filename must be windows-installations.json.'
}
$destinationRoot = "$($DestinationDriveLetter.ToUpperInvariant()):\"
if ([IO.Path]::GetPathRoot($OutputPath) -ine $destinationRoot) {
    throw 'The inventory output is not on the confirmed destination drive.'
}
$expectedOutputDirectory = [IO.Path]::GetFullPath(
    (Join-Path $destinationRoot 'CodexRescueEvidence')
)
if ($outputDirectory.FullName -ine $expectedOutputDirectory) {
    throw 'The inventory output must be in the root CodexRescueEvidence directory.'
}
if (!(Test-Path -LiteralPath (Join-Path $destinationRoot 'CODEX_EVIDENCE.DEST') -PathType Leaf)) {
    throw 'The confirmed evidence destination marker is missing.'
}
if (Test-Path -LiteralPath $OutputPath) {
    throw 'The offline Windows inventory already exists. Nothing was overwritten.'
}

function Test-PathSafely {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,

        [ValidateSet('Any', 'Container', 'Leaf')]
        [string]$PathType = 'Any'
    )

    try {
        return [bool](
            Test-Path -LiteralPath $LiteralPath -PathType $PathType -ErrorAction SilentlyContinue
        )
    }
    catch {
        return $false
    }
}

function Get-FileInventoryRecord {
    param(
        [Parameter(Mandatory)]
        [string]$InstallationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $path = [IO.Path]::Combine($InstallationRoot, $RelativePath)
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (!$item -or $item.PSIsContainer) {
        return [ordered]@{
            RelativePath = $RelativePath
            Present = $false
            Length = $null
            LastWriteTimeUtcAsRecorded = $null
        }
    }
    return [ordered]@{
        RelativePath = $RelativePath
        Present = $true
        Length = [long]$item.Length
        LastWriteTimeUtcAsRecorded = $item.LastWriteTimeUtc.ToString('o')
    }
}

function Get-DirectoryInventoryRecord {
    param(
        [Parameter(Mandatory)]
        [string]$InstallationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $path = [IO.Path]::Combine($InstallationRoot, $RelativePath)
    $directory = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (!$directory -or !$directory.PSIsContainer) {
        return [ordered]@{
            RelativePath = $RelativePath
            Present = $false
            DirectFileCount = 0
        }
    }
    $directFiles = @(
        Get-ChildItem -LiteralPath $path -File -Force -ErrorAction SilentlyContinue
    )
    return [ordered]@{
        RelativePath = $RelativePath
        Present = $true
        DirectFileCount = $directFiles.Count
    }
}

function Get-EventLogInventoryRecord {
    param(
        [Parameter(Mandatory)]
        [string]$InstallationRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $fileMetadata = Get-FileInventoryRecord -InstallationRoot $InstallationRoot -RelativePath $RelativePath
    $result = [ordered]@{
        RelativePath = $fileMetadata.RelativePath
        Present = $fileMetadata.Present
        Length = $fileMetadata.Length
        LastWriteTimeUtcAsRecorded = $fileMetadata.LastWriteTimeUtcAsRecorded
        SampleLimit = 500
        SampleReadSucceeded = $false
        EventCountSampled = 0
        CriticalCount = 0
        ErrorCount = 0
        WarningCount = 0
        EventIdCounts = @()
        OldestSampleTimeUtcAsRecorded = $null
        NewestSampleTimeUtcAsRecorded = $null
        EventMessagesIncluded = $false
        RawPayloadsIncluded = $false
    }
    if (!$fileMetadata.Present) {
        return $result
    }

    $path = [IO.Path]::Combine($InstallationRoot, $RelativePath)
    try {
        $events = @(
            Get-WinEvent -Path $path -MaxEvents $result.SampleLimit -ErrorAction Stop
        )
        $result.SampleReadSucceeded = $true
        $result.EventCountSampled = $events.Count
        $result.CriticalCount = @($events | Where-Object Level -eq 1).Count
        $result.ErrorCount = @($events | Where-Object Level -eq 2).Count
        $result.WarningCount = @($events | Where-Object Level -eq 3).Count
        $result.EventIdCounts = @(
            $events |
                Group-Object Id |
                Sort-Object { [int]$_.Name } |
                ForEach-Object {
                    [ordered]@{
                        EventId = [int]$_.Name
                        Count = [int]$_.Count
                    }
                }
        )
        $recordedTimes = @(
            $events |
                Where-Object { $null -ne $_.TimeCreated } |
                Select-Object -ExpandProperty TimeCreated
        )
        if ($recordedTimes.Count) {
            $result.OldestSampleTimeUtcAsRecorded = (
                $recordedTimes | Measure-Object -Minimum
            ).Minimum.ToUniversalTime().ToString('o')
            $result.NewestSampleTimeUtcAsRecorded = (
                $recordedTimes | Measure-Object -Maximum
            ).Maximum.ToUniversalTime().ToString('o')
        }
    }
    catch {
        $result.SampleReadSucceeded = $false
    }
    return $result
}

function Get-BcdStoreInventoryRecord {
    param(
        [Parameter(Mandatory)]
        [string]$DriveRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$Alias
    )

    $fileMetadata = Get-FileInventoryRecord -InstallationRoot $DriveRoot -RelativePath $RelativePath
    $result = [ordered]@{
        StoreAlias = $Alias
        RelativePath = $fileMetadata.RelativePath
        Present = $fileMetadata.Present
        Length = $fileMetadata.Length
        LastWriteTimeUtcAsRecorded = $fileMetadata.LastWriteTimeUtcAsRecorded
        EnumerationSucceeded = $false
        EntryCount = 0
        BootManagerPresent = $false
        WindowsBootLoaderCount = 0
        RecoverySequenceReferenceCount = 0
        RawBcdOutputIncluded = $false
    }
    if (!$fileMetadata.Present) {
        return $result
    }

    $path = [IO.Path]::Combine($DriveRoot, $RelativePath)
    try {
        $rawOutput = @(& bcdedit.exe '/store' $path '/enum' 'all' 2>$null)
        if ($LASTEXITCODE -ne 0) {
            return $result
        }
        $text = $rawOutput -join "`n"
        $result.EnumerationSucceeded = $true
        $result.EntryCount = ([regex]::Matches($text, '(?im)^\s*identifier\s+')).Count
        $result.BootManagerPresent = $text -match '(?im)^\s*identifier\s+\{bootmgr\}\s*$'
        $result.WindowsBootLoaderCount = ([regex]::Matches(
            $text,
            '(?im)^\s*path\s+\\Windows\\system32\\winload\.(?:efi|exe)\s*$'
        )).Count
        $result.RecoverySequenceReferenceCount = ([regex]::Matches(
            $text,
            '(?im)^\s*recoverysequence\s+'
        )).Count
    }
    catch {
        $result.EnumerationSucceeded = $false
    }
    finally {
        $rawOutput = $null
        $text = $null
    }
    return $result
}

function Get-RedactedProfileInventory {
    param(
        [Parameter(Mandatory)]
        [string]$InstallationRoot
    )

    $usersRoot = [IO.Path]::Combine($InstallationRoot, 'Users')
    $excludedProfileNames = @(
        'All Users',
        'Default',
        'Default User',
        'Public',
        'defaultuser0'
    )
    $profiles = @(
        Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object Name -NotIn $excludedProfileNames |
            Where-Object {
                ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
            } |
            Sort-Object Name
    )
    $knownFolderNames = @(
        'Desktop',
        'Documents',
        'Downloads',
        'Music',
        'OneDrive',
        'Pictures',
        'Videos'
    )
    $index = 0
    return @(
        foreach ($profileEntry in $profiles) {
            $index++
            $presentFolders = @(
                foreach ($folderName in $knownFolderNames) {
                    if (Test-PathSafely -LiteralPath (
                        Join-Path $profileEntry.FullName $folderName
                    ) -PathType Container) {
                        $folderName
                    }
                }
            )
            [ordered]@{
                ProfileAlias = 'Profile-{0:d2}' -f $index
                RedactedRoot = '{0}\Users\<redacted>' -f $InstallationRoot.TrimEnd('\')
                KnownFoldersPresent = $presentFolders
                FileNamesEnumerated = $false
                FileContentsRead = $false
            }
        }
    )
}

$candidateDriveLetters = @(
    'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'Y', 'Z'
)
$destinationLetter = $DestinationDriveLetter.ToUpperInvariant()
$scannedDriveLetters = @(
    $candidateDriveLetters | Where-Object { $_ -ne $destinationLetter -and $_ -ne 'X' }
)
$autopilotEventLogPath = 'Windows\System32\winevt\Logs\Microsoft-Windows-ModernDeployment-Diagnostics-Provider%4Autopilot.evtx'
$mdmAdminEventLogPath = 'Windows\System32\winevt\Logs\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider%4Admin.evtx'
$logPaths = @(
    'Windows\Panther\setuperr.log',
    'Windows\Panther\setupact.log',
    'Windows\Panther\Setup.etl',
    'Windows\INF\setupapi.dev.log',
    'Windows\Logs\DISM\dism.log',
    'Windows\Logs\CBS\CBS.log',
    'Windows\servicing\Sessions\Sessions.xml',
    'Windows\System32\LogFiles\Srt\SrtTrail.txt',
    'Windows\System32\winevt\Logs\Application.evtx',
    'Windows\System32\winevt\Logs\Setup.evtx',
    'Windows\System32\winevt\Logs\System.evtx',
    $autopilotEventLogPath,
    $mdmAdminEventLogPath,
    '$Windows.~BT\Sources\Panther\setuperr.log',
    '$Windows.~BT\Sources\Panther\setupact.log',
    '$Windows.~BT\Sources\Rollback\setuperr.log',
    '$Windows.~BT\Sources\Rollback\setupact.log'
)
$offlineBootStores = @(
    foreach ($driveLetter in $scannedDriveLetters) {
        $driveRoot = "$driveLetter`:\"
        foreach ($bootStore in @(
            @{ RelativePath = 'EFI\Microsoft\Boot\BCD'; Kind = 'EFI' },
            @{ RelativePath = 'Boot\BCD'; Kind = 'Boot' }
        )) {
            $record = Get-BcdStoreInventoryRecord `
                -DriveRoot $driveRoot `
                -RelativePath $bootStore.RelativePath `
                -Alias ('BootStore-{0}-{1}' -f $driveLetter, $bootStore.Kind)
            if ($record.Present) {
                $record
            }
        }
    }
)
$installations = @()
foreach ($driveLetter in $scannedDriveLetters) {
    $installationRoot = "$driveLetter`:\"
    $kernelPath = '{0}:\Windows\System32\ntoskrnl.exe' -f $driveLetter
    $systemHivePath = '{0}:\Windows\System32\config\SYSTEM' -f $driveLetter
    $softwareHivePath = '{0}:\Windows\System32\config\SOFTWARE' -f $driveLetter
    if (!(Test-PathSafely -LiteralPath $kernelPath -PathType Leaf) -or
        !(Test-PathSafely -LiteralPath $systemHivePath -PathType Leaf) -or
        !(Test-PathSafely -LiteralPath $softwareHivePath -PathType Leaf)) {
        continue
    }

    $kernelVersion = $null
    try {
        $kernelVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($kernelPath)
    }
    catch {
        $kernelVersion = $null
    }
    $profiles = @(Get-RedactedProfileInventory -InstallationRoot $installationRoot)
    $installations += [ordered]@{
        InstallationAlias = "Windows-$driveLetter"
        Root = $installationRoot
        WindowsDirectory = "$driveLetter`:\Windows"
        KernelProductVersion = if ($kernelVersion) { $kernelVersion.ProductVersion } else { $null }
        KernelFileVersion = if ($kernelVersion) { $kernelVersion.FileVersion } else { $null }
        SystemHivePresent = $true
        SoftwareHivePresent = $true
        RegistryHivesLoaded = $false
        RecoveryEnvironmentConfigPresent = Test-PathSafely -LiteralPath (
            Join-Path $installationRoot 'Windows\System32\Recovery\ReAgent.xml'
        ) -PathType Leaf
        LogArtifacts = @(
            foreach ($relativePath in $logPaths) {
                Get-FileInventoryRecord -InstallationRoot $installationRoot -RelativePath $relativePath
            }
        )
        ManagementIndicators = [ordered]@{
            AutopilotEventLog = Get-EventLogInventoryRecord -InstallationRoot $installationRoot -RelativePath (
                $autopilotEventLogPath
            )
            MdmAdminEventLog = Get-EventLogInventoryRecord -InstallationRoot $installationRoot -RelativePath (
                $mdmAdminEventLogPath
            )
            ExistingMdmDiagnostics = Get-DirectoryInventoryRecord -InstallationRoot $installationRoot -RelativePath (
                'Users\Public\Documents\MDMDiagnostics'
            )
            IntuneManagementExtensionLogs = Get-DirectoryInventoryRecord -InstallationRoot $installationRoot -RelativePath (
                'ProgramData\Microsoft\IntuneManagementExtension\Logs'
            )
        }
        ProfileCount = $profiles.Count
        Profiles = $profiles
        UserNamesIncluded = $false
        RawEventPayloadsIncluded = $false
    }
}

$result = [ordered]@{
    SchemaVersion = 1
    CollectionMode = 'read-only offline Windows inventory'
    ClockSource = 'WinPE system clock'
    ClockExternallyValidated = $false
    DestinationDriveExcluded = $destinationLetter
    WinPeRamDriveExcluded = 'X'
    CandidateDriveLettersScanned = $scannedDriveLetters
    WindowsInstallationCount = $installations.Count
    WindowsInstallations = $installations
    OfflineBootStoreCount = $offlineBootStores.Count
    OfflineBootStores = $offlineBootStores
    RecoveryMaterialIncluded = $false
    RawEventPayloadsIncluded = $false
    EventMessagesIncluded = $false
    RawBcdOutputIncluded = $false
    UserNamesIncluded = $false
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
