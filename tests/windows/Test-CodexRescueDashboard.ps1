<#
.SYNOPSIS
Validates the native Codex Rescue dashboard contract in Windows PowerShell 5.1.
.DESCRIPTION
Runs a fresh default read-only assessment, exports the normal local and
sanitized artifacts, loads the saved assessment through the dashboard's
headless validation path, and verifies the WPF XAML can be parsed. It does not
open the interactive window, request network access, or execute a repair.
.PARAMETER RepositoryRoot
Root of the checked-out or mounted Codex Rescue USB repository.
.PARAMETER OutputRoot
Parent directory for uniquely named validation artifacts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot,

    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot = 'C:\CodexRescueDashboardAudit'
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
    if (!$Condition) { throw $Message }
}

$modulePath = Join-Path $RepositoryRoot 'PowerShell\Modules\CodexRescue\CodexRescue.psd1'
$dashboardPath = Join-Path $RepositoryRoot 'scripts\Open-CodexRescueDashboard.ps1'
$xamlPath = Join-Path $RepositoryRoot 'PowerShell\Dashboard\CodexRescueDashboard.xaml'
Assert-True (Test-Path -LiteralPath $modulePath -PathType Leaf) "Module manifest not found: $modulePath"
Assert-True (Test-Path -LiteralPath $dashboardPath -PathType Leaf) "Dashboard script not found: $dashboardPath"
Assert-True (Test-Path -LiteralPath $xamlPath -PathType Leaf) "Dashboard XAML not found: $xamlPath"
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot -ErrorAction Stop | Out-Null
}

Import-Module $modulePath -Force -ErrorAction Stop
$assessment = Get-CodexRescueDeviceHealth
$validation = Invoke-CodexRescueValidation -Assessment $assessment -Strict
Assert-True $validation.ValidationPassed 'The source assessment failed strict validation.'

$artifactName = 'Dashboard-{0:yyyyMMddTHHmmssZ}-{1}' -f (Get-Date).ToUniversalTime(), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$destinationPath = Join-Path $OutputRoot $artifactName
$export = Export-CodexRescueLogs -DestinationPath $destinationPath -Assessment $assessment -Confirm:$false
$assessmentPath = Join-Path $destinationPath 'DeviceInfo\CodexRescueAssessment.local.json'
$reportPath = Join-Path $destinationPath 'Reports\CodexRescueReport.local.html'

$model = & $dashboardPath -AssessmentPath $assessmentPath `
    -DetailedReportPath $reportPath `
    -SanitizedZipPath $export.SanitizedZipPath `
    -NoWindow
Assert-True ($model.ViewModelType -eq 'CodexRescue.ReadOnlyDashboard') 'Unexpected dashboard view-model type.'
Assert-True ($model.ReadOnly -eq $true) 'The dashboard did not preserve ReadOnly=true.'
Assert-True ($model.RepairControlsAvailable -eq $false) 'The dashboard exposed a repair control.'
Assert-True ($model.AutomaticCodexUpload -eq $false) 'The dashboard enabled automatic Codex upload.'
Assert-True ($model.CloudStateBadge -eq 'CLOUD DISABLED') 'The dashboard did not show the cloud-disabled boundary.'
Assert-True ($model.CheckCards.Count -eq 10) 'The dashboard did not render exactly ten health cards.'
Assert-True ($model.TimelineEntries.Count -eq 3) 'The dashboard audit timeline contract changed unexpectedly.'
Assert-True ($model.DetailedReportAvailable -eq $true) 'The detailed local report control was not enabled for a valid report.'
Assert-True ($model.SanitizedZipAvailable -eq $true) 'The sanitized ZIP control was not enabled for a valid ZIP.'

$expectedChecks = @('Autopilot', 'Intune', 'Entra', 'Certificates', 'BitLocker', 'TPM', 'WindowsUpdate', 'Network', 'Drivers', 'EventErrors')
$actualChecks = @($model.CheckCards | ForEach-Object CheckName)
Assert-True (($actualChecks -join '|') -ceq ($expectedChecks -join '|')) 'Dashboard check order or membership is incorrect.'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xaml = [IO.File]::ReadAllText($xamlPath)
$xml = New-Object Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.LoadXml($xaml)
$reader = New-Object Xml.XmlNodeReader($xml)
try {
    $window = [Windows.Markup.XamlReader]::Load($reader)
}
finally {
    $reader.Dispose()
}
Assert-True ($null -ne $window) 'The WPF dashboard window could not be loaded from XAML.'
Assert-True ($null -ne $window.FindName('OpenDetailedReportButton')) 'The detailed-report control was not found in WPF.'
Assert-True ($null -ne $window.FindName('ShowSanitizedZipButton')) 'The sanitized-ZIP control was not found in WPF.'
$window.Close()

[pscustomobject][ordered]@{
    Result = 'PASS'
    WindowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    CheckCardCount = $model.CheckCards.Count
    TimelineEntryCount = $model.TimelineEntries.Count
    RepairControlsAvailable = $model.RepairControlsAvailable
    AutomaticCodexUpload = $model.AutomaticCodexUpload
    CloudStateBadge = $model.CloudStateBadge
    DetailedReportAvailable = $model.DetailedReportAvailable
    SanitizedZipAvailable = $model.SanitizedZipAvailable
    ArtifactDirectory = $destinationPath
    SanitizedZipSha256 = $export.SanitizedZipSha256
} | Format-List
