<#
.SYNOPSIS
Runs and exports the Phase 1 Codex Rescue read-only Windows assessment.
.DESCRIPTION
Imports the checked-in CodexRescue module, runs local diagnostics, validates the
result, writes a detailed local folder, and creates a separately sanitized ZIP.
No repair or cloud request runs. Existing destinations are never overwritten.
.PARAMETER DestinationPath
New assessment directory in an existing parent directory.
.PARAMETER IncludeOnlineNetworkTests
Runs consent-bound DNS and Microsoft sign-in HTTPS tests.
.PARAMETER OnlineTestConfirmationToken
Must exactly match RUN CODEX RESCUE ONLINE TESTS.
.PARAMETER IncludeRawManagementLogs
Collects privacy-sensitive local logs for local technician review only.
.PARAMETER RawLogConfirmationToken
Must exactly match INCLUDE RAW WINDOWS MANAGEMENT LOGS.
.EXAMPLE
.\scripts\Invoke-CodexRescueReadOnlyAssessment.ps1 -DestinationPath 'C:\Temp\CodexRescue\Assessment-001' -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationPath,

    [switch]$IncludeOnlineNetworkTests,
    [string]$OnlineTestConfirmationToken,
    [switch]$IncludeRawManagementLogs,
    [string]$RawLogConfirmationToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'The read-only assessment must run in full Windows.'
}

$modulePath = Join-Path $PSScriptRoot '..\PowerShell\Modules\CodexRescue\CodexRescue.psd1'
Import-Module $modulePath -Force -ErrorAction Stop
$healthParameters = @{}
if ($IncludeOnlineNetworkTests) {
    $healthParameters.IncludeOnlineNetworkTests = $true
    $healthParameters.OnlineTestConfirmationToken = $OnlineTestConfirmationToken
}
$assessment = Get-CodexRescueDeviceHealth @healthParameters
$validation = Invoke-CodexRescueValidation -Assessment $assessment -Strict
if ($PSCmdlet.ShouldProcess($DestinationPath, 'Export validated Codex Rescue read-only assessment')) {
    Export-CodexRescueLogs -DestinationPath $DestinationPath -Assessment $assessment `
        -IncludeRawManagementLogs:$IncludeRawManagementLogs `
        -RawLogConfirmationToken $RawLogConfirmationToken -Confirm:$false
}
