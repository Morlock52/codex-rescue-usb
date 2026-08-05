function Get-CodexRescueCertificateHealth {
    <#
    .SYNOPSIS
    Summarizes local device-management certificate health without exporting identities or keys.
    .EXAMPLE
    Get-CodexRescueCertificateHealth
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 365)]
        [int]$ExpiringWithinDays = 30
    )

    Assert-CodexRescueWindows
    try {
        $now = Get-Date
        $warningDate = $now.AddDays($ExpiringWithinDays)
        $certificates = @(
            Get-ChildItem -LiteralPath Cert:\LocalMachine\My -ErrorAction Stop |
                Where-Object {
                    $_.Subject -match '(?i)Microsoft Intune|MS-Organization|Workplace|Device' -or
                    $_.Issuer -match '(?i)Microsoft Intune|MS-Organization|Workplace|Device'
                }
        )
        $expired = @($certificates | Where-Object NotAfter -LE $now)
        $expiring = @($certificates | Where-Object { $_.NotAfter -gt $now -and $_.NotAfter -le $warningDate })
        $withoutPrivateKey = @($certificates | Where-Object { !$_.HasPrivateKey })

        $status = 'NotTested'
        $summary = 'No device-management certificates matched the local health inventory.'
        if ($certificates.Count -gt 0) {
            $status = 'Healthy'
            $summary = 'No expired or near-expiry device-management certificates were detected.'
            if ($expired.Count -gt 0) {
                $status = 'Failed'
                $summary = 'One or more device-management certificates are expired.'
            }
            elseif ($expiring.Count -gt 0 -or $withoutPrivateKey.Count -gt 0) {
                $status = 'Warning'
                $summary = 'A device-management certificate is near expiry or lacks an accessible private-key association.'
            }
        }

        New-CodexRescueCheck -Name 'Certificates' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            RelevantCertificateCount = $certificates.Count
            ExpiredCertificateCount = $expired.Count
            ExpiringCertificateCount = $expiring.Count
            MissingPrivateKeyAssociationCount = $withoutPrivateKey.Count
            ExpiringWithinDays = $ExpiringWithinDays
            CertificateSubjectsIncluded = $false
            CertificateThumbprintsIncluded = $false
            PrivateKeysExported = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Certificates' -Status 'NotTested' -Summary 'Certificate health could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
