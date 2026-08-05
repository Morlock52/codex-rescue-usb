function Invoke-CodexRescueGraphGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativeUri
    )

    $null = Assert-CodexRescueGraphSession
    $decoded = [Uri]::UnescapeDataString($RelativeUri)
    $lower = $decoded.ToLowerInvariant()
    if (!$lower.StartsWith('/v1.0/')) {
        throw 'Request path is outside the allowlisted Microsoft Graph v1.0 boundary.'
    }
    if ($lower -match '/beta/' -or $lower -match 'select\s*=\s*key' -or $lower -match 'recoverykeys/') {
        throw 'Request path attempts to cross the recovery-key or stable-API boundary.'
    }

    $allowedPathPatterns = @(
        "^/v1\.0/devices\(deviceId='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'\)(?:\?.*)?$",
        '^/v1\.0/devices/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/memberOf(?:\?.*)?$',
        '^/v1\.0/deviceManagement/managedDevices(?:\?.*)?$',
        '^/v1\.0/deviceManagement/windowsAutopilotDeviceIdentities(?:\?.*)?$',
        '^/v1\.0/informationProtection/bitlocker/recoveryKeys(?:\?.*)?$'
    )
    if (!($allowedPathPatterns | Where-Object { $decoded -match $_ })) {
        throw 'Request path is outside the Codex Rescue read-only endpoint allowlist.'
    }

    $query = if ($decoded.Contains('?')) { $decoded.Split('?', 2)[1] } else { '' }
    if ($query -match '(?i)(password|secret|token|serialNumber|userPrincipalName|displayName|groupTag|purchaseOrder|productKey)') {
        throw 'Request query asks for a prohibited identifier, credential, or secret field.'
    }
    foreach ($part in @($query -split '&' | Where-Object { $_ })) {
        $name = $part.Split('=', 2)[0]
        if ($name -notin @('$filter', '$select', '$top')) {
            throw "Request query option is not allowlisted: $name"
        }
        if ($lower.StartsWith('/v1.0/informationprotection/bitlocker/recoverykeys?') -and $name -ne '$filter') {
            throw 'The BitLocker recovery-key list endpoint permits only the deviceId filter.'
        }
    }

    $script:CodexRescueGraphRequestCount++
    Invoke-MgGraphRequest -Method GET -Uri ("https://graph.microsoft.com$RelativeUri") -OutputType PSObject -ErrorAction Stop
}
