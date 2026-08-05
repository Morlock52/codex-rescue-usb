function Get-CodexRescueEntraStatus {
    <#
    .SYNOPSIS
    Collects a privacy-limited, read-only Microsoft Entra registration status.
    .DESCRIPTION
    Runs dsregcmd /status and returns join/authentication booleans without the
    raw command output, tenant ID, device ID, user principal name, or tokens.
    .EXAMPLE
    Get-CodexRescueEntraStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $command = Get-Command dsregcmd.exe -ErrorAction Stop
        $output = @(& $command.Source /status 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        $values = @{}
        foreach ($line in $output) {
            if ($line -match '^\s*([^:]+?)\s*:\s*(.*?)\s*$') {
                $values[$matches[1].Trim()] = $matches[2].Trim()
            }
        }

        $azureAdJoined = $values['AzureAdJoined'] -eq 'YES'
        $deviceAuthStatus = [string]$values['DeviceAuthStatus']
        $status = 'Warning'
        $summary = 'The device does not report a healthy Microsoft Entra device join.'
        if ($azureAdJoined -and $deviceAuthStatus -eq 'SUCCESS') {
            $status = 'Healthy'
            $summary = 'The device reports Microsoft Entra join and successful device authentication.'
        }
        elseif ($azureAdJoined -and $deviceAuthStatus -and $deviceAuthStatus -ne 'SUCCESS') {
            $status = 'Failed'
            $summary = 'The device reports Microsoft Entra join but device authentication is not successful.'
        }

        New-CodexRescueCheck -Name 'Entra' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            AzureAdJoined = $azureAdJoined
            DomainJoined = $values['DomainJoined'] -eq 'YES'
            EnterpriseJoined = $values['EnterpriseJoined'] -eq 'YES'
            WorkplaceJoined = $values['WorkplaceJoined'] -eq 'YES'
            DeviceAuthStatus = if ($deviceAuthStatus) { $deviceAuthStatus } else { 'Unavailable' }
            AzureAdPrt = $values['AzureAdPrt'] -eq 'YES'
            WamDefaultSet = $values['WamDefaultSet'] -eq 'YES'
            NgcSet = $values['NgcSet'] -eq 'YES'
            DeviceIdPresent = ![string]::IsNullOrWhiteSpace([string]$values['DeviceId'])
            TenantIdPresent = ![string]::IsNullOrWhiteSpace([string]$values['TenantId'])
            CommandExitCode = $exitCode
            RawOutputIncluded = $false
            UserIdentityIncluded = $false
            TokensIncluded = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Entra' -Status 'NotTested' -Summary 'Microsoft Entra registration diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
