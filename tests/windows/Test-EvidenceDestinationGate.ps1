<#
.SYNOPSIS
Runs the evidence-destination gate against disposable mapped drives.

.DESCRIPTION
Verifies that the batch collector rejects a directory marker, rejects two
prepared destinations, and performs no write after an incorrect confirmation.
Only temporary mapped drives are changed, and they are removed in cleanup.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$firstDrive = 'Y'
$secondDrive = 'Z'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'CodexRescueDestinationGate-{0}' -f [guid]::NewGuid()
)
$firstRoot = Join-Path $temporaryRoot 'first'
$secondRoot = Join-Path $temporaryRoot 'second'
$mappedDrives = @()
$collectorSourcePath = Join-Path $PSScriptRoot '..\..\winpe\Collect-RescueEvidence.cmd'
$collectorPath = Join-Path $temporaryRoot 'Collect-RescueEvidence.cmd'

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

function Invoke-CollectorWithInput {
    param(
        [Parameter(Mandatory)]
        [string]$InputPath
    )

    $command = 'call "{0}" < "{1}"' -f $collectorPath, $InputPath
    return (& $env:ComSpec /d /c $command 2>&1 | Out-String)
}

try {
    foreach ($driveLetter in @($firstDrive, $secondDrive)) {
        if (Test-Path -LiteralPath ('{0}:\' -f $driveLetter)) {
            throw ('Fixture drive {0}: is already in use.' -f $driveLetter)
        }
    }

    New-Item -ItemType Directory -Path $firstRoot, $secondRoot | Out-Null
    Get-Content -LiteralPath $collectorSourcePath |
        Set-Content -LiteralPath $collectorPath -Encoding ASCII
    & subst.exe ('{0}:' -f $firstDrive) $firstRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not map the first fixture drive.' }
    $mappedDrives += $firstDrive
    & subst.exe ('{0}:' -f $secondDrive) $secondRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not map the second fixture drive.' }
    $mappedDrives += $secondDrive

    $firstMarker = '{0}:\CODEX_EVIDENCE.DEST' -f $firstDrive
    $secondMarker = '{0}:\CODEX_EVIDENCE.DEST' -f $secondDrive
    $incorrectInputPath = Join-Path $temporaryRoot 'incorrect-confirmation.txt'
    Set-Content -LiteralPath $incorrectInputPath -Value 'DO NOT COLLECT' -Encoding ASCII

    New-Item -ItemType Directory -Path $firstMarker | Out-Null
    $directoryMarkerOutput = Invoke-CollectorWithInput -InputPath $incorrectInputPath
    Assert-True ($directoryMarkerOutput -match 'must be an empty file, not a directory') (
        'The collector did not reject a directory marker.'
    )
    Assert-True (!(Test-Path -LiteralPath ('{0}:\CodexRescueEvidence' -f $firstDrive))) (
        'The directory-marker case created an evidence directory.'
    )
    Remove-Item -LiteralPath $firstMarker -Force

    New-Item -ItemType File -Path $firstMarker, $secondMarker | Out-Null
    $ambiguousOutput = Invoke-CollectorWithInput -InputPath $incorrectInputPath
    Assert-True ($ambiguousOutput -match 'More than one prepared destination') (
        'The collector did not reject two prepared destinations.'
    )
    Assert-True (!(Test-Path -LiteralPath ('{0}:\CodexRescueEvidence' -f $firstDrive))) (
        'The ambiguous-marker case wrote to the first fixture drive.'
    )
    Assert-True (!(Test-Path -LiteralPath ('{0}:\CodexRescueEvidence' -f $secondDrive))) (
        'The ambiguous-marker case wrote to the second fixture drive.'
    )
    Remove-Item -LiteralPath $secondMarker -Force

    $incorrectConfirmationOutput = Invoke-CollectorWithInput -InputPath $incorrectInputPath
    Assert-True ($incorrectConfirmationOutput -match 'confirmation did not match') (
        'The collector accepted an incorrect target confirmation.'
    )
    Assert-True (!(Test-Path -LiteralPath ('{0}:\CodexRescueEvidence' -f $firstDrive))) (
        'The incorrect-confirmation case created an evidence directory.'
    )

    [pscustomobject]@{
        Result = 'PASS'
        DirectoryMarkerRejected = $true
        MultipleDestinationsRejected = $true
        IncorrectConfirmationRejected = $true
        EvidenceDirectoryCreated = $false
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
        throw 'The evidence-destination fixture directory survived cleanup.'
    }
}
