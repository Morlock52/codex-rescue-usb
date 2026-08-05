function Get-CodexRescueNetworkStatus {
    <#
    .SYNOPSIS
    Collects privacy-limited local network health and optional consent-bound online tests.
    .PARAMETER IncludeOnlineTests
    Performs DNS and HTTPS reachability tests without returning endpoint addresses.
    .PARAMETER OnlineTestConfirmationToken
    Must exactly match RUN CODEX RESCUE ONLINE TESTS when online tests are requested.
    .EXAMPLE
    Get-CodexRescueNetworkStatus
    .EXAMPLE
    Get-CodexRescueNetworkStatus -IncludeOnlineTests -OnlineTestConfirmationToken 'RUN CODEX RESCUE ONLINE TESTS'
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeOnlineTests,
        [string]$OnlineTestConfirmationToken
    )

    Assert-CodexRescueWindows
    $requiredToken = 'RUN CODEX RESCUE ONLINE TESTS'
    if ($IncludeOnlineTests -and $OnlineTestConfirmationToken -cne $requiredToken) {
        throw 'Online network consent was not entered exactly. No online test was performed.'
    }

    try {
        $adapters = @(
            Get-NetAdapter -IncludeHidden -ErrorAction Stop |
                Where-Object HardwareInterface -EQ $true
        )
        $upAdapters = @($adapters | Where-Object Status -EQ 'Up')
        $configurations = @()
        foreach ($adapter in $upAdapters) {
            $configuration = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
            if ($configuration) {
                $configurations += $configuration
            }
        }
        $gatewayCount = @($configurations | Where-Object IPv4DefaultGateway).Count
        $dnsConfiguredCount = @(
            $configurations | Where-Object { @($_.DNSServer.ServerAddresses).Count -gt 0 }
        ).Count
        $winHttpOutput = @(& netsh.exe winhttp show proxy 2>&1 | ForEach-Object { $_.ToString() })
        $proxyConfigured = ![bool]($winHttpOutput -match '(?i)Direct access \(no proxy server\)')
        $timeService = Get-Service -Name W32Time -ErrorAction SilentlyContinue

        $dnsResolutionSucceeded = $null
        $httpsReachable = $null
        if ($IncludeOnlineTests) {
            try {
                $null = Resolve-DnsName login.microsoftonline.com -ErrorAction Stop
                $dnsResolutionSucceeded = $true
            }
            catch {
                $dnsResolutionSucceeded = $false
            }
            try {
                $httpsReachable = [bool](Test-NetConnection login.microsoftonline.com -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)
            }
            catch {
                $httpsReachable = $false
            }
        }

        $status = if ($upAdapters.Count -gt 0 -and $gatewayCount -gt 0 -and $dnsConfiguredCount -gt 0) { 'Healthy' } else { 'Warning' }
        $summary = if ($status -eq 'Healthy') {
            'A hardware network adapter is up with local gateway and DNS configuration.'
        }
        else {
            'No complete local network path is currently available. The recovery workspace may be intentionally offline.'
        }
        if ($IncludeOnlineTests -and (!$dnsResolutionSucceeded -or !$httpsReachable)) {
            $status = 'Failed'
            $summary = 'The consent-bound Microsoft sign-in DNS or HTTPS reachability test failed.'
        }

        New-CodexRescueCheck -Name 'Network' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            HardwareAdapterCount = $adapters.Count
            UpHardwareAdapterCount = $upAdapters.Count
            ConfigurationWithGatewayCount = $gatewayCount
            ConfigurationWithDnsCount = $dnsConfiguredCount
            WinHttpProxyConfigured = $proxyConfigured
            TimeServiceStatus = if ($timeService) { $timeService.Status.ToString() } else { 'NotInstalled' }
            OnlineTestsPerformed = [bool]$IncludeOnlineTests
            DnsResolutionSucceeded = $dnsResolutionSucceeded
            MicrosoftSignInHttpsReachable = $httpsReachable
            AdapterAddressesIncluded = $false
            DnsServerAddressesIncluded = $false
            ProxyAddressIncluded = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'Network' -Status 'NotTested' -Summary 'Network diagnostics could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
