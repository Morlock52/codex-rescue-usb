<#
.SYNOPSIS
Audits or changes one explicitly selected full-Windows network adapter.

.DESCRIPTION
Lists physical adapters in audit mode. Enable and Disable require an exact
interface index, administrator rights, and an action-specific confirmation
token. The script never changes every adapter implicitly and makes no network
request of its own.

.EXAMPLE
.\scripts\Set-CodexRecoveryNetwork.ps1 -Action Audit

.EXAMPLE
.\scripts\Set-CodexRecoveryNetwork.ps1 -Action Disable -InterfaceIndex 6 -ConfirmationToken DISABLE-CODEX-RECOVERY-NETWORK-6 -Confirm:$false

.EXAMPLE
.\scripts\Set-CodexRecoveryNetwork.ps1 -Action Enable -InterfaceIndex 6 -ConfirmationToken ENABLE-CODEX-RECOVERY-NETWORK-6 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Audit', 'Enable', 'Disable')]
    [string]$Action = 'Audit',

    [ValidateRange(0, 4096)]
    [int]$InterfaceIndex = 0,

    [string]$ConfirmationToken
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') {
    throw 'The Codex recovery network gate requires full Windows.'
}
$adapters = @(
    Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object HardwareInterface -eq $true
)

if ($Action -eq 'Audit') {
    [pscustomobject]@{
        SchemaVersion = 1
        Action = 'Audit'
        PhysicalAdapterCount = $adapters.Count
        NetworkConsentGranted = $false
    } | Format-List
    $adapters |
        Select-Object Name, InterfaceDescription, ifIndex, Status, LinkSpeed |
        Sort-Object ifIndex |
        Format-Table -AutoSize
    return
}

if ($InterfaceIndex -eq 0) {
    throw 'Enable or Disable requires one explicit -InterfaceIndex from the audit output.'
}
$matches = @($adapters | Where-Object ifIndex -eq $InterfaceIndex)
if ($matches.Count -ne 1) {
    throw "Expected exactly one physical adapter with interface index $InterfaceIndex; found $($matches.Count)."
}
if (!(Test-Administrator)) {
    throw 'Run Enable or Disable from an elevated PowerShell session.'
}

$adapter = $matches[0]
$requiredToken = "$($Action.ToUpperInvariant())-CODEX-RECOVERY-NETWORK-$InterfaceIndex"
if ($ConfirmationToken -cne $requiredToken) {
    throw "Confirmation token mismatch. Required: $requiredToken"
}

if ($Action -eq 'Disable') {
    if ($adapter.Status -notin @('Disabled', 'Not Present') -and $PSCmdlet.ShouldProcess(
            "$($adapter.Name) (ifIndex $InterfaceIndex)",
            'Disable the selected recovery-workspace network adapter'
        )) {
        Disable-NetAdapter -Name $adapter.Name -IncludeHidden -Confirm:$false -ErrorAction Stop
    }
}
elseif ($Action -eq 'Enable') {
    if ($adapter.Status -in @('Disabled', 'Not Present') -and $PSCmdlet.ShouldProcess(
            "$($adapter.Name) (ifIndex $InterfaceIndex)",
            'Enable the selected recovery-workspace network adapter'
        )) {
        Enable-NetAdapter -Name $adapter.Name -IncludeHidden -Confirm:$false -ErrorAction Stop
    }
}

$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 500
    $updatedMatches = @(
        Get-NetAdapter -IncludeHidden -ErrorAction Stop |
            Where-Object HardwareInterface -eq $true |
            Where-Object Name -CEQ $adapter.Name
    )
    if ($updatedMatches.Count -ne 1) {
        throw "Selected adapter $($adapter.Name) became missing or ambiguous during the $Action transition."
    }
    $updated = $updatedMatches[0]
    $reachedTarget = if ($Action -eq 'Disable') {
        $updated.Status -in @('Disabled', 'Not Present')
    }
    else {
        $updated.Status -notin @('Disabled', 'Not Present')
    }
} until ($reachedTarget -or (Get-Date) -ge $deadline)

if (!$reachedTarget) {
    throw "Adapter $($adapter.Name) did not reach the requested $Action state before $deadline. Current status: $($updated.Status)."
}

[pscustomobject]@{
    SchemaVersion = 1
    Action = $Action
    InterfaceIndex = $updated.ifIndex
    InterfaceName = $updated.Name
    Status = $updated.Status
    NetworkEnabled = ($updated.Status -notin @('Disabled', 'Not Present'))
    NetworkConsentGranted = $true
} | Format-List
