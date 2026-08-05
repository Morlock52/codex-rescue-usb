<#
.SYNOPSIS
Opens the read-only Codex Rescue Windows technician health dashboard.
.DESCRIPTION
Loads a saved structured assessment or runs the default local read-only
assessment, applies strict module validation, builds a bounded display model,
and opens a native WPF dashboard. The dashboard does not scrape console text,
make cloud requests, enable networking, run repairs, or send data to Codex.
.PARAMETER AssessmentPath
Optional path to an existing CodexRescueAssessment local or sanitized JSON file.
When omitted, a fresh default local assessment is run.
.PARAMETER DetailedReportPath
Optional path to an existing detailed local HTML report. The dashboard only
opens it; it does not create or modify it.
.PARAMETER SanitizedZipPath
Optional path to an existing sanitized escalation ZIP. The dashboard only
reveals it in Explorer; it does not create, upload, or modify it.
.PARAMETER NoWindow
Returns the validated dashboard view model without loading WPF. Intended for
native Windows validation and automated contract tests.
.EXAMPLE
.\scripts\Open-CodexRescueDashboard.ps1
.EXAMPLE
.\scripts\Open-CodexRescueDashboard.ps1 `
  -AssessmentPath 'C:\Temp\Assessment-001\DeviceInfo\CodexRescueAssessment.local.json' `
  -DetailedReportPath 'C:\Temp\Assessment-001\Reports\CodexRescueReport.local.html' `
  -SanitizedZipPath 'C:\Temp\Assessment-001-sanitized.zip'
#>
[CmdletBinding()]
param(
    [string]$AssessmentPath,
    [string]$DetailedReportPath,
    [string]$SanitizedZipPath,
    [switch]$NoWindow
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-CodexRescueDisplayText {
    param(
        [AllowNull()]
        [object]$Value,

        [ValidateRange(1, 2000)]
        [int]$MaximumLength = 400
    )

    if ($null -eq $Value) {
        return 'Not available'
    }
    $text = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
    $text = [regex]::Replace($text, '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]', '')
    if ($text.Length -gt $MaximumLength) {
        return $text.Substring(0, $MaximumLength - 3) + '...'
    }
    return $text
}

function Resolve-ExistingArtifactPath {
    param(
        [string]$Path,
        [string]$ExpectedExtension,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (!(Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
        throw "$Description must be an existing file: $Path"
    }
    if ([IO.Path]::GetExtension($resolved.Path) -ine $ExpectedExtension) {
        throw "$Description must use the $ExpectedExtension extension."
    }
    return $resolved.Path
}

function Get-CodexRescueStatusStyle {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'Warning', 'Failed', 'NotTested')]
        [string]$Status
    )

    switch ($Status) {
        'Healthy' {
            return [pscustomobject]@{
                Label = 'HEALTHY'; Background = '#EBFFEE'; Border = '#14AE5C'
                Badge = '#CFF7D3'; Foreground = '#02542D'
            }
        }
        'Warning' {
            return [pscustomobject]@{
                Label = 'WARNING'; Background = '#FFFBEB'; Border = '#E8B931'
                Badge = '#FFF1C2'; Foreground = '#522504'
            }
        }
        'Failed' {
            return [pscustomobject]@{
                Label = 'FAILED'; Background = '#FEE9E7'; Border = '#EC221F'
                Badge = '#FDD3D0'; Foreground = '#900B09'
            }
        }
        'NotTested' {
            return [pscustomobject]@{
                Label = 'NOT TESTED'; Background = '#F5F5F5'; Border = '#B3B3B3'
                Badge = '#E3E3E3'; Foreground = '#303030'
            }
        }
    }
}

function Get-CodexRescueCheckTitle {
    param([Parameter(Mandatory)][string]$CheckName)

    $titles = @{
        Autopilot = 'Windows Autopilot'
        Intune = 'Microsoft Intune'
        Entra = 'Microsoft Entra registration'
        Certificates = 'Certificates'
        BitLocker = 'BitLocker'
        TPM = 'TPM and Secure Boot'
        WindowsUpdate = 'Windows Update'
        Network = 'Network readiness'
        Drivers = 'Drivers'
        EventErrors = 'Windows event health'
    }
    if ($titles.ContainsKey($CheckName)) {
        return $titles[$CheckName]
    }
    return ConvertTo-CodexRescueDisplayText -Value $CheckName -MaximumLength 80
}

function New-CodexRescueDashboardModel {
    param(
        [Parameter(Mandatory)]
        [object]$Assessment,
        [Parameter(Mandatory)]
        [object]$Validation,
        [AllowNull()]
        [string]$ResolvedDetailedReportPath,
        [AllowNull()]
        [string]$ResolvedSanitizedZipPath
    )

    $cards = foreach ($check in @($Assessment.Checks)) {
        $style = Get-CodexRescueStatusStyle -Status $check.Status
        $checkedAt = ConvertTo-CodexRescueDisplayText -Value $check.CheckedAtUtc -MaximumLength 80
        [pscustomobject][ordered]@{
            Title = Get-CodexRescueCheckTitle -CheckName $check.CheckName
            CheckName = ConvertTo-CodexRescueDisplayText -Value $check.CheckName -MaximumLength 80
            Status = $check.Status
            StatusLabel = $style.Label
            Summary = ConvertTo-CodexRescueDisplayText -Value $check.Summary
            EvidenceMetadata = "Local read-only check | $checkedAt | raw messages excluded"
            StatusBackground = $style.Background
            StatusBorder = $style.Border
            BadgeBackground = $style.Badge
            StatusForeground = $style.Foreground
        }
    }

    $deviceSummary = $Assessment.DeviceSummary
    $deviceLines = @(
        "$(ConvertTo-CodexRescueDisplayText $deviceSummary.Manufacturer) $(ConvertTo-CodexRescueDisplayText $deviceSummary.Model)"
        "$(ConvertTo-CodexRescueDisplayText $deviceSummary.WindowsCaption) | build $(ConvertTo-CodexRescueDisplayText $deviceSummary.WindowsBuild)"
        "$(ConvertTo-CodexRescueDisplayText $deviceSummary.FirmwareType) firmware | $(ConvertTo-CodexRescueDisplayText $deviceSummary.TotalPhysicalMemoryGB) GB RAM"
    )
    $offlineCount = [int]$Assessment.OfflineWindowsInstallationCount
    $installedWindowsSummary = if ($offlineCount -eq 0) {
        'Current Windows installation only. No separate offline installation was detected.'
    }
    else {
        "$offlineCount separate offline Windows installation(s) detected. Review the structured local assessment for bounded details."
    }

    $testedCount = [int]$Assessment.TestedCheckCount
    $notTestedCount = [int]$Assessment.NotTestedCheckCount
    $artifactStates = @()
    if ($ResolvedDetailedReportPath) { $artifactStates += 'detailed local report available' }
    else { $artifactStates += 'detailed local report not supplied' }
    if ($ResolvedSanitizedZipPath) { $artifactStates += 'sanitized ZIP available' }
    else { $artifactStates += 'sanitized ZIP not supplied' }

    $timeline = @(
        [pscustomobject][ordered]@{
            Title = 'Assessment generated locally'
            Metadata = ConvertTo-CodexRescueDisplayText -Value $Assessment.GeneratedAtUtc -MaximumLength 80
        }
        [pscustomobject][ordered]@{
            Title = "Strict validation passed for $($Validation.CheckCount) required checks"
            Metadata = ConvertTo-CodexRescueDisplayText -Value $Validation.ValidatedAtUtc -MaximumLength 80
        }
        [pscustomobject][ordered]@{
            Title = 'Safety boundary verified: zero repairs and zero cloud requests'
            Metadata = 'local dashboard session'
        }
    )

    [pscustomobject][ordered]@{
        SchemaVersion = 1
        ViewModelType = 'CodexRescue.ReadOnlyDashboard'
        ReadOnly = $true
        RepairControlsAvailable = $false
        AutomaticCodexUpload = $false
        NetworkStateBadge = if ($Assessment.OnlineNetworkTestsPerformed) { 'ONLINE TESTS USED' } else { 'OFFLINE CHECKS' }
        CloudStateBadge = 'CLOUD DISABLED'
        HealthScoreText = "$($Assessment.HealthScore)/100"
        HealthSummary = "$testedCount tested | $notTestedCount not tested | findings are diagnostic, not repair actions"
        DeviceSummaryText = $deviceLines -join "`n"
        InstalledWindowsSummaryText = $installedWindowsSummary
        CheckCards = @($cards)
        TimelineEntries = @($timeline)
        DetailedReportAvailable = [bool]$ResolvedDetailedReportPath
        SanitizedZipAvailable = [bool]$ResolvedSanitizedZipPath
        DetailedReportPath = $ResolvedDetailedReportPath
        SanitizedZipPath = $ResolvedSanitizedZipPath
        EvidenceSummaryText = 'Detailed evidence remains local. The sanitized ZIP is a separate, bounded handoff and still requires operator review.'
        ArtifactAvailabilityText = $artifactStates -join ' | '
        AssessmentFooterText = "Validated schema v$($Assessment.SchemaVersion) | generated $(ConvertTo-CodexRescueDisplayText $Assessment.GeneratedAtUtc 80)"
    }
}

$modulePath = Join-Path $PSScriptRoot '..\PowerShell\Modules\CodexRescue\CodexRescue.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($AssessmentPath)) {
    if ($env:OS -ne 'Windows_NT') {
        throw 'A fresh dashboard assessment must run in full Windows. Supply -AssessmentPath only for Windows validation.'
    }
    $assessment = Get-CodexRescueDeviceHealth
}
else {
    $resolvedAssessmentPath = Resolve-Path -LiteralPath $AssessmentPath -ErrorAction Stop
    if (!(Test-Path -LiteralPath $resolvedAssessmentPath.Path -PathType Leaf)) {
        throw "AssessmentPath must be an existing JSON file: $AssessmentPath"
    }
    if ([IO.Path]::GetExtension($resolvedAssessmentPath.Path) -ine '.json') {
        throw 'AssessmentPath must use the .json extension.'
    }
    $assessmentFile = Get-Item -LiteralPath $resolvedAssessmentPath.Path -ErrorAction Stop
    if ($assessmentFile.Length -gt 16MB) {
        throw 'AssessmentPath exceeds the 16 MB local dashboard limit.'
    }
    $assessment = Get-Content -LiteralPath $resolvedAssessmentPath.Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

$validation = Invoke-CodexRescueValidation -Assessment $assessment -Strict
$resolvedDetailedReportPath = Resolve-ExistingArtifactPath -Path $DetailedReportPath -ExpectedExtension '.html' -Description 'DetailedReportPath'
$resolvedSanitizedZipPath = Resolve-ExistingArtifactPath -Path $SanitizedZipPath -ExpectedExtension '.zip' -Description 'SanitizedZipPath'
$viewModel = New-CodexRescueDashboardModel -Assessment $assessment -Validation $validation `
    -ResolvedDetailedReportPath $resolvedDetailedReportPath `
    -ResolvedSanitizedZipPath $resolvedSanitizedZipPath

if ($NoWindow) {
    return $viewModel
}
if ($env:OS -ne 'Windows_NT') {
    throw 'The native WPF dashboard must run in full Windows.'
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'The native WPF dashboard requires an STA PowerShell process. Use the checked-in .cmd launcher.'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xamlPath = Join-Path $PSScriptRoot '..\PowerShell\Dashboard\CodexRescueDashboard.xaml'
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
$window.DataContext = $viewModel
$window.Add_ContentRendered({
    $null = $window.Activate()
})

$openDetailedReportButton = $window.FindName('OpenDetailedReportButton')
$showSanitizedZipButton = $window.FindName('ShowSanitizedZipButton')
if ($viewModel.DetailedReportAvailable) {
    $openDetailedReportButton.Add_Click({
        Start-Process -FilePath $viewModel.DetailedReportPath -ErrorAction Stop
    })
}
if ($viewModel.SanitizedZipAvailable) {
    $showSanitizedZipButton.Add_Click({
        Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($viewModel.SanitizedZipPath)`"" -ErrorAction Stop
    })
}

$null = $window.ShowDialog()
