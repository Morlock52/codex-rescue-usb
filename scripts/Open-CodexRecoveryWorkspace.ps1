<#
.SYNOPSIS
Audits and opens the full-Windows Codex recovery workspace.

.DESCRIPTION
Verifies the staged recovery source, the installed OpenAI Codex AppX package,
and its registered codex: protocol. It reports whether Windows exposes a
microphone endpoint, requires exact consent before starting the networked app,
and never imports recovery evidence or recovery material automatically.

.PARAMETER WorkspacePath
Full path to the staged Codex Rescue source. Defaults to Documents\CodexRescue.

.PARAMETER ConfirmationToken
Must exactly match START CODEX RECOVERY WORKSPACE. Omit it for an interactive
prompt.

.PARAMETER AuditOnly
Reports readiness without requesting consent or launching Codex.

.EXAMPLE
.\scripts\Open-CodexRecoveryWorkspace.ps1 -AuditOnly

.EXAMPLE
.\scripts\Open-CodexRecoveryWorkspace.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WorkspacePath,
    [string]$ConfirmationToken,
    [switch]$AuditOnly
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'The Codex recovery workspace requires full Windows. It does not run in WinPE.'
}
if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $WorkspacePath = Join-Path $documents 'CodexRescue'
}
$WorkspacePath = [IO.Path]::GetFullPath($WorkspacePath)
if (!(Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    throw "Stage the recovery source before launching Codex. Missing folder: $WorkspacePath"
}
if (!(Test-Path -LiteralPath (Join-Path $WorkspacePath 'README.md') -PathType Leaf)) {
    throw "The selected workspace does not contain the Codex Rescue README: $WorkspacePath"
}

$packageScope = 'CurrentUser'
$package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
if (!$package -and $AuditOnly) {
    $package = Get-AppxPackage -AllUsers -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $packageScope = 'AllUsersInventory'
}
if (!$package) {
    throw 'OpenAI.Codex is not installed for this Windows user. Install the official Windows Codex app before continuing.'
}
if (!$AuditOnly -and $packageScope -ne 'CurrentUser') {
    throw 'OpenAI.Codex is installed for another account, not the signed-in recovery operator. Codex was not started.'
}
$manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
$protocolRegistered = [bool](
    Select-String -LiteralPath $manifestPath -SimpleMatch '<uap:Protocol Name="codex"' -Quiet
)
if (!$protocolRegistered) {
    throw 'The installed OpenAI.Codex package does not expose the expected codex: protocol.'
}

$audioEndpoints = @()
if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
    $audioEndpoints = @(
        Get-PnpDevice -Class AudioEndpoint -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object Status -eq 'OK'
    )
}
$inputEndpoints = @(
    $audioEndpoints |
        Where-Object FriendlyName -Match 'Microphone|Mic|Input'
)

$requiredToken = 'START CODEX RECOVERY WORKSPACE'
$networkConsentGranted = $false
if (!$AuditOnly) {
    Write-Host ''
    Write-Host 'Codex starts only in full Windows and uses a signed-in network service.'
    Write-Host 'Never paste, speak, attach, or import a BitLocker key or unredacted recovery package.'
    Write-Host 'Review the selected project and use the least access needed before any repair.'
    if ([string]::IsNullOrWhiteSpace($ConfirmationToken)) {
        $ConfirmationToken = Read-Host "Type $requiredToken to continue"
    }
    if ($ConfirmationToken -cne $requiredToken) {
        throw 'Network consent was not entered exactly. Codex was not started.'
    }
    $networkConsentGranted = $true
}

$result = [ordered]@{
    SchemaVersion = 1
    WorkspacePath = $WorkspacePath
    PackageName = $package.Name
    PackageVersion = $package.Version.ToString()
    PackageScope = $packageScope
    ProtocolRegistered = $protocolRegistered
    NetworkConsentGranted = $networkConsentGranted
    RecoveryMaterialAllowed = $false
    AutomaticEvidenceImport = $false
    AudioEndpointCount = $audioEndpoints.Count
    AudioInputDetected = ($inputEndpoints.Count -gt 0)
    VoiceRuntimeValidated = $false
}
[pscustomobject]$result | Format-List

if ($AuditOnly) {
    Write-Host 'Audit-only mode: Codex was not started.'
    return
}

if (!$inputEndpoints.Count) {
    Write-Warning 'No Windows microphone endpoint is present. The Voice control may be visible, but a spoken session is not validated.'
}
if ($PSCmdlet.ShouldProcess('OpenAI Codex desktop app', "Open the codex: protocol for $WorkspacePath")) {
    Start-Process 'codex:'
    Write-Host "Codex started. Press Ctrl+O and select: $WorkspacePath"
}
