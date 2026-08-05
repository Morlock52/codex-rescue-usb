function Get-CodexRescueAutopilotStatus {
    <#
    .SYNOPSIS
    Collects local, read-only Windows Autopilot indicators.
    .DESCRIPTION
    Checks the local Autopilot diagnostics registry location, the Autopilot
    event channel, and the Microsoft MDM diagnostics executable. It does not
    generate or upload a hardware hash and it makes no Microsoft Graph request.
    .EXAMPLE
    Get-CodexRescueAutopilotStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $registryPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot'
        $registryPresent = Test-Path -LiteralPath $registryPath
        $registryValueNames = @()
        if ($registryPresent) {
            $registryValueNames = @(
                (Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop).PSObject.Properties |
                    Where-Object Name -NotMatch '^PS' |
                    Select-Object -ExpandProperty Name
            )
        }

        $channelName = 'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot'
        $eventChannel = Get-WinEvent -ListLog $channelName -ErrorAction SilentlyContinue
        $diagnosticsTool = Get-Command mdmdiagnosticstool.exe -ErrorAction SilentlyContinue
        $status = 'NotTested'
        $summary = 'No local Autopilot indicators were found. Cloud registration was not tested.'
        if ($registryPresent -and $eventChannel) {
            $status = 'Healthy'
            $summary = 'Local Autopilot diagnostics state and event channel are present; cloud registration was not tested.'
        }
        elseif ($registryPresent -or $eventChannel) {
            $status = 'Warning'
            $summary = 'Only part of the local Autopilot diagnostics surface is present; cloud registration was not tested.'
        }

        New-CodexRescueCheck -Name 'Autopilot' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            LocalDiagnosticsRegistryPresent = $registryPresent
            LocalDiagnosticsValueCount = $registryValueNames.Count
            AutopilotEventChannelPresent = [bool]$eventChannel
            AutopilotEventChannelEnabled = if ($eventChannel) { [bool]$eventChannel.IsEnabled } else { $false }
            MdmDiagnosticsToolPresent = [bool]$diagnosticsTool
            HardwareHashCollected = $false
            CloudLookupPerformed = $false
            RawEventPayloadsIncluded = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Autopilot' -Status 'NotTested' -Summary 'Local Autopilot diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
