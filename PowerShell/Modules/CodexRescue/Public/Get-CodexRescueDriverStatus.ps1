function Get-CodexRescueDriverStatus {
    <#
    .SYNOPSIS
    Summarizes present Windows devices and signed-driver health without device identifiers.
    .EXAMPLE
    Get-CodexRescueDriverStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $pnpCommand = Get-Command Get-PnpDevice -ErrorAction SilentlyContinue
        if (!$pnpCommand) {
            return New-CodexRescueCheck -Name 'Drivers' -Status 'NotTested' -Summary 'Get-PnpDevice is unavailable.' -Data ([pscustomobject]@{
                DeviceCount = 0
                DeviceIdentifiersIncluded = $false
            })
        }

        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
        $problemDevices = @($devices | Where-Object { $_.Status -notin @('OK', 'Unknown') })
        $criticalClasses = @('DiskDrive', 'Net', 'SCSIAdapter', 'HDC', 'System', 'USB')
        $criticalProblems = @($problemDevices | Where-Object Class -In $criticalClasses)
        $problemByClass = @(
            $problemDevices |
                Group-Object Class, Status |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        ClassAndStatus = $_.Name
                        Count = $_.Count
                    }
                }
        )
        $signedDrivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
        $unsignedCount = @($signedDrivers | Where-Object { $_.IsSigned -eq $false }).Count

        $status = 'Healthy'
        $summary = 'No present-device errors or unsigned PnP drivers were detected.'
        if ($criticalProblems.Count -gt 0) {
            $status = 'Failed'
            $summary = 'One or more storage, network, system, or USB devices report a problem.'
        }
        elseif ($problemDevices.Count -gt 0 -or $unsignedCount -gt 0) {
            $status = 'Warning'
            $summary = 'One or more present devices report a problem or an unsigned PnP driver is installed.'
        }

        New-CodexRescueCheck -Name 'Drivers' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            PresentDeviceCount = $devices.Count
            ProblemDeviceCount = $problemDevices.Count
            CriticalProblemDeviceCount = $criticalProblems.Count
            SignedDriverInventoryCount = $signedDrivers.Count
            UnsignedDriverCount = $unsignedCount
            ProblemCountsByClassAndStatus = @($problemByClass)
            PnpUtilPresent = [bool](Get-Command pnputil.exe -ErrorAction SilentlyContinue)
            DeviceIdentifiersIncluded = $false
            DriverInstallationAttempted = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Drivers' -Status 'NotTested' -Summary 'Driver diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
