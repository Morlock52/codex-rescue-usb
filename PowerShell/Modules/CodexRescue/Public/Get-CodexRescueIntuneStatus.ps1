function Get-CodexRescueIntuneStatus {
    <#
    .SYNOPSIS
    Collects local, read-only Microsoft Intune enrollment indicators.
    .DESCRIPTION
    Reports enrollment-record counts, management-certificate health, Intune
    Management Extension service state, and log inventory metadata. It does not
    read log contents, disclose tenant identifiers, or contact Microsoft Graph.
    .EXAMPLE
    Get-CodexRescueIntuneStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $enrollmentRoot = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
        $enrollmentRecords = @()
        if (Test-Path -LiteralPath $enrollmentRoot) {
            $enrollmentRecords = @(
                Get-ChildItem -LiteralPath $enrollmentRoot -ErrorAction Stop |
                    Where-Object PSChildName -Match '^[0-9A-Fa-f-]{36}$'
            )
        }

        $now = Get-Date
        $managementCertificates = @(
            Get-ChildItem -LiteralPath Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Subject -match '(?i)Microsoft Intune|MS-Organization' -or
                    $_.Issuer -match '(?i)Microsoft Intune|MS-Organization'
                }
        )
        $validCertificateCount = @(
            $managementCertificates | Where-Object { $_.NotBefore -le $now -and $_.NotAfter -gt $now }
        ).Count
        $expiredCertificateCount = @(
            $managementCertificates | Where-Object { $_.NotAfter -le $now }
        ).Count

        $ime = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
        $logDirectory = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
        $logFiles = @()
        if (Test-Path -LiteralPath $logDirectory -PathType Container) {
            $logFiles = @(
                Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue
            )
        }
        $latestLogUtc = $null
        if ($logFiles.Count -gt 0) {
            $latestLogUtc = ($logFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc.ToString('o')
        }

        $status = 'NotTested'
        $summary = 'No local Intune enrollment indicators were found; cloud state was not tested.'
        if ($enrollmentRecords.Count -gt 0 -and $validCertificateCount -gt 0) {
            $status = 'Healthy'
            $summary = 'Local enrollment records and a currently valid management certificate are present; cloud state was not tested.'
            if ($ime -and $ime.Status -ne 'Running') {
                $status = 'Warning'
                $summary = 'Local enrollment state is present, but the Intune Management Extension service is not running.'
            }
        }
        elseif ($enrollmentRecords.Count -gt 0 -or $managementCertificates.Count -gt 0 -or $ime) {
            $status = if ($expiredCertificateCount -gt 0 -and $validCertificateCount -eq 0) { 'Failed' } else { 'Warning' }
            $summary = 'Local Intune indicators are incomplete or unhealthy; cloud state was not tested.'
        }

        New-CodexRescueCheck -Name 'Intune' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            EnrollmentRecordCount = $enrollmentRecords.Count
            ManagementCertificateCount = $managementCertificates.Count
            ValidManagementCertificateCount = $validCertificateCount
            ExpiredManagementCertificateCount = $expiredCertificateCount
            IntuneManagementExtensionInstalled = [bool]$ime
            IntuneManagementExtensionStatus = if ($ime) { $ime.Status.ToString() } else { 'NotInstalled' }
            LogDirectoryPresent = Test-Path -LiteralPath $logDirectory -PathType Container
            LogFileCount = $logFiles.Count
            LatestLogWriteUtc = $latestLogUtc
            TenantIdentifiersIncluded = $false
            LogContentsRead = $false
            CloudLookupPerformed = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Intune' -Status 'NotTested' -Summary 'Local Intune diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
