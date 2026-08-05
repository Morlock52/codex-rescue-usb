function Get-CodexRescueGraphRequiredScope {
    [CmdletBinding()]
    param()

    @(
        'Device.Read.All'
        'DeviceManagementManagedDevices.Read.All'
        'DeviceManagementServiceConfig.Read.All'
        'BitlockerKey.ReadBasic.All'
    )
}
