<#
.SYNOPSIS
Audits, installs, or removes the Codex recovery offline-at-startup policy.

.DESCRIPTION
Installs a SYSTEM scheduled task that disables one exact physical network
adapter at Windows startup. The generated task script is stored in a locked
ProgramData directory. Install and Remove require administrator rights, one
explicit interface index, and an action-specific confirmation token.

.EXAMPLE
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 -Action Audit

.EXAMPLE
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 -Action Install -InterfaceIndex 6 -ConfirmationToken INSTALL-CODEX-RECOVERY-OFFLINE-BOOT-6

.EXAMPLE
.\scripts\Set-CodexRecoveryOfflineStartup.ps1 -Action Remove -InterfaceIndex 6 -ConfirmationToken REMOVE-CODEX-RECOVERY-OFFLINE-BOOT-6
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Audit', 'Install', 'Remove')]
    [string]$Action = 'Audit',

    [ValidateRange(0, 4096)]
    [int]$InterfaceIndex = 0,

    [string]$ConfirmationToken
)

$ErrorActionPreference = 'Stop'
$taskName = 'Codex Rescue Offline Startup'
$policyDirectory = Join-Path $env:ProgramData 'CodexRescue'
$policyPath = Join-Path $policyDirectory 'Disable-NetworkAtStartup.ps1'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') {
    throw 'The Codex recovery offline-startup policy requires full Windows.'
}

$adapters = @(
    Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object HardwareInterface -eq $true
)
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($Action -eq 'Audit') {
    $taskInfo = if ($existingTask) {
        Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
    }
    [pscustomobject]@{
        SchemaVersion = 1
        Action = 'Audit'
        OfflineAtStartupInstalled = [bool]$existingTask
        PolicyScriptPresent = Test-Path -LiteralPath $policyPath -PathType Leaf
        TaskState = if ($existingTask) { [string]$existingTask.State } else { 'Absent' }
        LastTaskResult = if ($taskInfo) { $taskInfo.LastTaskResult } else { $null }
        NetworkConsentGranted = $false
    } | Format-List
    $adapters |
        Select-Object Name, InterfaceDescription, ifIndex, Status, LinkSpeed |
        Sort-Object ifIndex |
        Format-Table -AutoSize
    return
}

if ($InterfaceIndex -eq 0) {
    throw 'Install or Remove requires one explicit -InterfaceIndex from the network audit.'
}
if (!(Test-Administrator)) {
    throw 'Run Install or Remove from an elevated PowerShell session.'
}
$requiredToken = "$($Action.ToUpperInvariant())-CODEX-RECOVERY-OFFLINE-BOOT-$InterfaceIndex"
if ($ConfirmationToken -cne $requiredToken) {
    throw "Confirmation token mismatch. Required: $requiredToken"
}

if ($Action -eq 'Install') {
    $matches = @($adapters | Where-Object ifIndex -eq $InterfaceIndex)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one physical adapter with interface index $InterfaceIndex; found $($matches.Count)."
    }

    $policyContent = @"
`$ErrorActionPreference = 'Stop'
`$matches = @(
    Get-NetAdapter -IncludeHidden -ErrorAction Stop |
        Where-Object HardwareInterface -eq `$true |
        Where-Object ifIndex -eq $InterfaceIndex
)
if (`$matches.Count -ne 1) {
    throw 'The configured Codex recovery network adapter is missing or ambiguous.'
}
if (`$matches[0].Status -notin @('Disabled', 'Not Present')) {
    Disable-NetAdapter -Name `$matches[0].Name -IncludeHidden -Confirm:`$false -ErrorAction Stop
}
"@

    if ($PSCmdlet.ShouldProcess(
            "$taskName for physical adapter ifIndex $InterfaceIndex",
            'Install the offline-at-startup policy'
        )) {
        New-Item -ItemType Directory -Path $policyDirectory -Force | Out-Null
        & icacls.exe $policyDirectory /inheritance:r `
            /grant:r '*S-1-5-18:(OI)(CI)(F)' `
            '*S-1-5-32-544:(OI)(CI)(F)' `
            '*S-1-5-32-545:(OI)(CI)(RX)' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to secure $policyDirectory with icacls.exe."
        }
        $policyContent | Set-Content -LiteralPath $policyPath -Encoding UTF8 -Force

        $actionArguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$policyPath`""
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArguments
        $taskTrigger = New-ScheduledTaskTrigger -AtStartup
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Register-ScheduledTask `
            -TaskName $taskName `
            -Description "Codex Rescue offline-default policy for physical adapter ifIndex $InterfaceIndex." `
            -Action $taskAction `
            -Trigger $taskTrigger `
            -Principal $taskPrincipal `
            -Settings $taskSettings `
            -Force | Out-Null
    }
}
else {
    if (!$existingTask) {
        throw "Scheduled task is not installed: $taskName"
    }
    if ($existingTask.Description -cne "Codex Rescue offline-default policy for physical adapter ifIndex $InterfaceIndex.") {
        throw 'The installed task is not bound to the selected interface index. Nothing was removed.'
    }
    if ($PSCmdlet.ShouldProcess($taskName, 'Remove the offline-at-startup policy')) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        if (Test-Path -LiteralPath $policyPath -PathType Leaf) {
            Remove-Item -LiteralPath $policyPath -Force
        }
    }
}

$updatedTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
[pscustomobject]@{
    SchemaVersion = 1
    Action = $Action
    InterfaceIndex = $InterfaceIndex
    OfflineAtStartupInstalled = [bool]$updatedTask
    PolicyScriptPresent = Test-Path -LiteralPath $policyPath -PathType Leaf
    NetworkConsentGranted = $false
} | Format-List
