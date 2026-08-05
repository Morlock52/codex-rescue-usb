function Get-CodexRescueDeviceHealth {
    <#
    .SYNOPSIS
    Runs the complete read-only local Codex Rescue health assessment.
    .DESCRIPTION
    Collects device summary, offline Windows detection, and every local Phase 1
    diagnostic check. It makes no repair, cloud, or online-network request by
    default. The returned object is intended for local operator review.
    .PARAMETER IncludeOnlineNetworkTests
    Includes consent-bound DNS and HTTPS reachability tests.
    .PARAMETER OnlineTestConfirmationToken
    Must exactly match RUN CODEX RESCUE ONLINE TESTS when online tests are requested.
    .EXAMPLE
    Get-CodexRescueDeviceHealth
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeOnlineNetworkTests,
        [string]$OnlineTestConfirmationToken
    )

    Assert-CodexRescueWindows
    $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $firmwareTypeProperty = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' `
        -Name PEFirmwareType -ErrorAction SilentlyContinue
    $firmwareTypeValue = $null
    if (
        $firmwareTypeProperty -and
        $firmwareTypeProperty.PSObject.Properties.Name -contains 'PEFirmwareType'
    ) {
        $firmwareTypeValue = [int]$firmwareTypeProperty.PEFirmwareType
    }
    $firmwareType = switch ($firmwareTypeValue) {
        1 { 'BIOS' }
        2 { 'UEFI' }
        default { 'Unknown' }
    }

    $networkParameters = @{}
    if ($IncludeOnlineNetworkTests) {
        $networkParameters.IncludeOnlineTests = $true
        $networkParameters.OnlineTestConfirmationToken = $OnlineTestConfirmationToken
    }
    $checks = @(
        Get-CodexRescueAutopilotStatus
        Get-CodexRescueIntuneStatus
        Get-CodexRescueEntraStatus
        Get-CodexRescueCertificateHealth
        Get-CodexRescueBitLockerStatus
        Get-CodexRescueTpmStatus
        Get-CodexRescueWindowsUpdateStatus
        Get-CodexRescueNetworkStatus @networkParameters
        Get-CodexRescueDriverStatus
        Get-CodexRescueEventErrors
    )
    $statusScores = @{
        Healthy = 100
        Warning = 60
        Failed = 0
    }
    $tested = @($checks | Where-Object Status -NE 'NotTested')
    $healthScore = 0
    if ($tested.Count -gt 0) {
        $healthScore = [int][math]::Round((
            ($tested | ForEach-Object { $statusScores[$_.Status] } | Measure-Object -Average).Average
        ))
    }

    $offlineWindows = @(Get-CodexRescueOfflineWindows | Where-Object { !$_.IsCurrentSystem })
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        AssessmentType = 'CodexRescue.ReadOnlyDeviceHealth'
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        ReadOnly = $true
        RepairActionsPerformed = 0
        CloudRequestsPerformed = 0
        OnlineNetworkTestsPerformed = [bool]$IncludeOnlineNetworkTests
        RecoveryMaterialCollected = $false
        CredentialsCollected = $false
        SanitizationRequiredBeforeCodex = $true
        DeviceSummary = [pscustomobject][ordered]@{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            SerialNumber = $bios.SerialNumber
            BiosVersion = @($bios.BIOSVersion) -join '; '
            WindowsCaption = $operatingSystem.Caption
            WindowsVersion = $operatingSystem.Version
            WindowsBuild = $operatingSystem.BuildNumber
            FirmwareType = $firmwareType
            TotalPhysicalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
            CurrentUser = $env:USERNAME
        }
        OfflineWindowsInstallationCount = $offlineWindows.Count
        OfflineWindowsInstallations = @($offlineWindows)
        HealthScore = $healthScore
        TestedCheckCount = $tested.Count
        NotTestedCheckCount = @($checks | Where-Object Status -EQ 'NotTested').Count
        Checks = @($checks)
    }
}
