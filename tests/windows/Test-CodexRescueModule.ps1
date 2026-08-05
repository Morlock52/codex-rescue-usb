<#
.SYNOPSIS
Runs the Phase 1 CodexRescue module contract in Windows PowerShell 5.1.
.DESCRIPTION
Imports the checked-in module, performs the default local read-only assessment,
validates it, and exports a detailed local folder plus a sanitized escalation
ZIP. The test does not request online checks, cloud access, or raw management
logs. It leaves the uniquely named export in place as VM validation evidence.
.PARAMETER RepositoryRoot
Root of the checked-out or mounted Codex Rescue USB repository.
.PARAMETER OutputRoot
Existing or new parent directory for uniquely named validation artifacts.
.EXAMPLE
.\tests\windows\Test-CodexRescueModule.ps1 -RepositoryRoot D:\
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot,

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = 'C:\CodexRescueVmAudit'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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

$modulePath = Join-Path $RepositoryRoot 'PowerShell\Modules\CodexRescue\CodexRescue.psd1'
Assert-True (Test-Path -LiteralPath $modulePath -PathType Leaf) "Module manifest not found: $modulePath"
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
}

Import-Module $modulePath -Force -ErrorAction Stop
$commands = @(Get-Command -Module CodexRescue -CommandType Function)
Assert-True ($commands.Count -eq 14) 'The module did not export exactly 14 Phase 1 functions.'
Assert-True (!($commands.Name -contains 'Invoke-CodexRescueSafeRepair')) 'A repair command leaked into Phase 1.'

$assessment = Get-CodexRescueDeviceHealth
$validation = Invoke-CodexRescueValidation -Assessment $assessment -Strict
Assert-True $validation.ValidationPassed 'The default assessment failed validation.'
Assert-True ($validation.CheckCount -eq 10) 'The assessment did not contain exactly 10 required checks.'
Assert-True ($assessment.ReadOnly -eq $true) 'The assessment did not declare ReadOnly=true.'
Assert-True ($assessment.RepairActionsPerformed -eq 0) 'The assessment reported a repair action.'
Assert-True ($assessment.CloudRequestsPerformed -eq 0) 'The default assessment made a cloud request.'
Assert-True ($assessment.OnlineNetworkTestsPerformed -eq $false) 'The default assessment made an online network test.'
Assert-True ($assessment.RecoveryMaterialCollected -eq $false) 'The assessment collected recovery material.'
Assert-True ($assessment.CredentialsCollected -eq $false) 'The assessment collected credentials.'

$artifactName = 'Phase1-{0:yyyyMMddTHHmmssZ}-{1}' -f (Get-Date).ToUniversalTime(), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$destinationPath = Join-Path $OutputRoot $artifactName
$export = Export-CodexRescueLogs -DestinationPath $destinationPath -Assessment $assessment -Confirm:$false
Assert-True (Test-Path -LiteralPath $export.DestinationPath -PathType Container) 'The detailed export directory was not created.'
Assert-True (Test-Path -LiteralPath $export.SanitizedZipPath -PathType Leaf) 'The sanitized ZIP was not created.'
Assert-True ($export.RawManagementLogsIncluded -eq $false) 'Raw management logs were unexpectedly included.'
Assert-True ($export.RawManagementLogsExcludedFromEscalationZip -eq $true) 'The export did not declare raw logs excluded.'
Assert-True ($export.RecoveryMaterialCollected -eq $false) 'The export collected recovery material.'
Assert-True ($export.CredentialsCollected -eq $false) 'The export collected credentials.'
Assert-True ($export.OperatorReviewRequired -eq $true) 'The export did not require operator review.'

$intuneRawFiles = @(Get-ChildItem -LiteralPath (Join-Path $destinationPath 'Intune') -Recurse -File -ErrorAction Stop)
$eventRawFiles = @(Get-ChildItem -LiteralPath (Join-Path $destinationPath 'EventLogs') -Recurse -File -ErrorAction Stop)
Assert-True ($intuneRawFiles.Count -eq 0) 'Raw Intune logs were written without consent.'
Assert-True ($eventRawFiles.Count -eq 0) 'Raw Windows event logs were written without consent.'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($export.SanitizedZipPath)
try {
    $entryNames = @($archive.Entries | ForEach-Object FullName | Sort-Object)
    $expectedEntries = @(
        'CodexRescueAssessment.sanitized.json',
        'CodexRescueReport.sanitized.html',
        'README.json'
    ) | Sort-Object
    Assert-True ($entryNames.Count -eq 3) 'The sanitized ZIP did not contain exactly three files.'
    Assert-True (($entryNames -join '|') -ceq ($expectedEntries -join '|')) 'The sanitized ZIP file set was incorrect.'

    $zipText = foreach ($entry in $archive.Entries) {
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    $zipText = $zipText -join "`n"
}
finally {
    $archive.Dispose()
}

$secretPatterns = @(
    '(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)',
    '(?i)authorization\s*:\s*bearer\s+',
    '(?i)refresh[_ -]?token\s*[:=]',
    '(?i)access[_ -]?token\s*[:=]',
    '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '(?i)\.bek(?:\b|\")'
)
foreach ($pattern in $secretPatterns) {
    Assert-True (!([regex]::IsMatch($zipText, $pattern))) "A prohibited pattern was found in the sanitized ZIP: $pattern"
}

$manifestPath = Join-Path $destinationPath 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
Assert-True ($manifest.AssessmentReadOnly -eq $true) 'The manifest did not declare a read-only assessment.'
Assert-True ($manifest.RawManagementLogsIncluded -eq $false) 'The manifest reported raw management logs.'
Assert-True ($manifest.RawManagementLogsExcludedFromEscalationZip -eq $true) 'The manifest did not declare raw-log exclusion.'
Assert-True ($manifest.EscalationZipSanitized -eq $true) 'The manifest did not declare a sanitized ZIP.'

[pscustomobject][ordered]@{
    Result = 'PASS'
    WindowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ExportedCommandCount = $commands.Count
    CheckCount = $validation.CheckCount
    HealthScore = $assessment.HealthScore
    RepairActionsPerformed = $assessment.RepairActionsPerformed
    CloudRequestsPerformed = $assessment.CloudRequestsPerformed
    OnlineNetworkTestsPerformed = $assessment.OnlineNetworkTestsPerformed
    RawManagementLogFileCount = $intuneRawFiles.Count + $eventRawFiles.Count
    SanitizedZipEntryCount = $entryNames.Count
    SecretPatternCount = 0
    DestinationPath = $export.DestinationPath
    SanitizedZipPath = $export.SanitizedZipPath
    SanitizedZipSha256 = $export.SanitizedZipSha256
} | Format-List
