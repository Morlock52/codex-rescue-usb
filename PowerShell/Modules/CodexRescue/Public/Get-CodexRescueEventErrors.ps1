function Get-CodexRescueEventErrors {
    <#
    .SYNOPSIS
    Aggregates recent critical, error, and warning events without raw messages.
    .PARAMETER Since
    Earliest event time to include. Defaults to seven days ago.
    .PARAMETER MaximumEventsPerChannel
    Maximum number of records sampled from each channel.
    .EXAMPLE
    Get-CodexRescueEventErrors -Since (Get-Date).AddDays(-2)
    #>
    [CmdletBinding()]
    param(
        [datetime]$Since = (Get-Date).AddDays(-7),
        [ValidateRange(1, 2000)]
        [int]$MaximumEventsPerChannel = 500
    )

    Assert-CodexRescueWindows
    try {
        $channels = @(
            'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin',
            'Microsoft-Windows-AAD/Operational',
            'Microsoft-Windows-User Device Registration/Admin',
            'Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin',
            'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot',
            'Microsoft-Windows-WindowsUpdateClient/Operational',
            'Microsoft-Windows-BitLocker/BitLocker Management',
            'Microsoft-Windows-TPM-WMI/Admin',
            'Microsoft-Windows-Kernel-Boot/Operational',
            'System',
            'Application',
            'Setup'
        )
        $channelResults = @()
        foreach ($channel in $channels) {
            $metadata = Get-WinEvent -ListLog $channel -ErrorAction SilentlyContinue
            if (!$metadata) {
                $channelResults += [pscustomobject][ordered]@{
                    Channel = $channel
                    Present = $false
                    Enabled = $false
                    SampleSucceeded = $false
                    CriticalCount = 0
                    ErrorCount = 0
                    WarningCount = 0
                    SampledCount = 0
                    TopEventIds = @()
                }
                continue
            }

            $events = @()
            $sampleSucceeded = $true
            try {
                $events = @(
                    Get-WinEvent -FilterHashtable @{
                        LogName = $channel
                        StartTime = $Since
                        Level = @(1, 2, 3)
                    } -MaxEvents $MaximumEventsPerChannel -ErrorAction Stop
                )
            }
            catch [System.Exception] {
                if ($_.Exception.Message -match '(?i)No events were found') {
                    $events = @()
                }
                else {
                    $sampleSucceeded = $false
                }
            }
            $topEventIds = @(
                $events |
                    Group-Object Id |
                    Sort-Object Count -Descending |
                    Select-Object -First 10 |
                    ForEach-Object {
                        [pscustomobject][ordered]@{
                            EventId = [int]$_.Name
                            Count = $_.Count
                        }
                    }
            )
            $channelResults += [pscustomobject][ordered]@{
                Channel = $channel
                Present = $true
                Enabled = [bool]$metadata.IsEnabled
                SampleSucceeded = $sampleSucceeded
                CriticalCount = @($events | Where-Object Level -EQ 1).Count
                ErrorCount = @($events | Where-Object Level -EQ 2).Count
                WarningCount = @($events | Where-Object Level -EQ 3).Count
                SampledCount = $events.Count
                TopEventIds = @($topEventIds)
            }
        }

        $criticalCount = [int](($channelResults | Measure-Object CriticalCount -Sum).Sum)
        $errorCount = [int](($channelResults | Measure-Object ErrorCount -Sum).Sum)
        $warningCount = [int](($channelResults | Measure-Object WarningCount -Sum).Sum)
        $failedSamples = @($channelResults | Where-Object { $_.Present -and !$_.SampleSucceeded }).Count
        $status = 'Healthy'
        $summary = 'No sampled critical, error, or warning events were found in the selected channels.'
        if ($criticalCount -gt 0) {
            $status = 'Failed'
            $summary = 'Recent critical events were found in the selected Windows channels.'
        }
        elseif ($errorCount -gt 0 -or $warningCount -gt 0 -or $failedSamples -gt 0) {
            $status = 'Warning'
            $summary = 'Recent errors or warnings were found, or one event channel could not be sampled.'
        }

        New-CodexRescueCheck -Name 'EventErrors' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            SinceUtc = $Since.ToUniversalTime().ToString('o')
            MaximumEventsPerChannel = $MaximumEventsPerChannel
            ChannelCount = $channels.Count
            CriticalCount = $criticalCount
            ErrorCount = $errorCount
            WarningCount = $warningCount
            FailedSampleCount = $failedSamples
            Channels = @($channelResults)
            RawMessagesIncluded = $false
            RawPayloadsIncluded = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'EventErrors' -Status 'NotTested' -Summary 'Event-log diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
