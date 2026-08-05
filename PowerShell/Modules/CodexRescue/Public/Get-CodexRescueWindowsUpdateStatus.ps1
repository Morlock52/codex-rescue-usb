function Get-CodexRescueWindowsUpdateStatus {
    <#
    .SYNOPSIS
    Collects read-only Windows Update service and pending-reboot state.
    .DESCRIPTION
    This command does not scan online, reset components, stop services, or run
    DISM repair. It inventories service configuration and local reboot signals.
    .EXAMPLE
    Get-CodexRescueWindowsUpdateStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $serviceNames = @('wuauserv', 'bits', 'cryptsvc', 'UsoSvc', 'WaaSMedicSvc', 'DoSvc')
        $services = foreach ($name in $serviceNames) {
            $service = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction SilentlyContinue
            [pscustomobject][ordered]@{
                Name = $name
                Installed = [bool]$service
                State = if ($service) { $service.State } else { 'NotInstalled' }
                StartMode = if ($service) { $service.StartMode } else { 'Unavailable' }
            }
        }

        $rebootSignals = [ordered]@{
            ComponentBasedServicing = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            WindowsUpdate = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            PendingFileRename = $false
        }
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        $rebootSignals.PendingFileRename = [bool]($sessionManager -and $sessionManager.PendingFileRenameOperations)
        $pendingReboot = [bool]($rebootSignals.Values -contains $true)
        $disabled = @($services | Where-Object { $_.Installed -and $_.StartMode -eq 'Disabled' })

        $status = 'Healthy'
        $summary = 'Windows Update dependencies are not disabled and no standard pending-reboot signal is present.'
        if ($disabled.Count -gt 0) {
            $status = 'Failed'
            $summary = 'One or more Windows Update dependencies are disabled.'
        }
        elseif ($pendingReboot) {
            $status = 'Warning'
            $summary = 'Windows reports one or more pending-reboot signals.'
        }

        New-CodexRescueCheck -Name 'WindowsUpdate' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            Services = @($services)
            DisabledServiceCount = $disabled.Count
            PendingReboot = $pendingReboot
            PendingRebootSignals = [pscustomobject]$rebootSignals
            OnlineScanPerformed = $false
            ComponentRepairPerformed = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'WindowsUpdate' -Status 'NotTested' -Summary 'Windows Update diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
