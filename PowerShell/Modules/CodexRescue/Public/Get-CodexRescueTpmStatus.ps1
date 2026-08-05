function Get-CodexRescueTpmStatus {
    <#
    .SYNOPSIS
    Collects read-only TPM and Secure Boot state.
    .EXAMPLE
    Get-CodexRescueTpmStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $tpmCommand = Get-Command Get-Tpm -ErrorAction SilentlyContinue
        $tpm = if ($tpmCommand) { Get-Tpm -ErrorAction Stop } else { $null }
        $secureBootSupported = [bool](Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)
        $secureBootEnabled = $null
        $secureBootError = $null
        if ($secureBootSupported) {
            try {
                $secureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
            }
            catch {
                $secureBootError = $_.Exception.Message
            }
        }

        $status = 'NotTested'
        $summary = 'TPM state was unavailable.'
        if ($tpm) {
            $status = 'Healthy'
            $summary = 'TPM is present and ready; Secure Boot is enabled.'
            if (!$tpm.TpmPresent -or !$tpm.TpmReady) {
                $status = 'Failed'
                $summary = 'TPM is missing or not ready.'
            }
            elseif ($secureBootEnabled -ne $true) {
                $status = 'Warning'
                $summary = 'TPM is ready, but Secure Boot is disabled or could not be confirmed.'
            }
        }

        New-CodexRescueCheck -Name 'TPM' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            TpmCommandAvailable = [bool]$tpmCommand
            TpmPresent = if ($tpm) { [bool]$tpm.TpmPresent } else { $false }
            TpmReady = if ($tpm) { [bool]$tpm.TpmReady } else { $false }
            TpmEnabled = if ($tpm) { [bool]$tpm.TpmEnabled } else { $false }
            TpmActivated = if ($tpm) { [bool]$tpm.TpmActivated } else { $false }
            TpmOwned = if ($tpm) { [bool]$tpm.TpmOwned } else { $false }
            TpmLockedOut = if ($tpm) { [bool]$tpm.LockedOut } else { $false }
            SecureBootCommandAvailable = $secureBootSupported
            SecureBootEnabled = $secureBootEnabled
            SecureBootQueryError = $secureBootError
            TpmClearAttempted = $false
            SecureBootKeysChanged = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'TPM' -Status 'NotTested' -Summary 'TPM and Secure Boot diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
