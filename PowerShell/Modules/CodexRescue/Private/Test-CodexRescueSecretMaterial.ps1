function Test-CodexRescueSecretMaterial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $patterns = [ordered]@{
        BitLockerRecoveryPassword = '(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)'
        BearerToken = '(?i)\bBearer\s+[A-Za-z0-9._~+\/-]{20,}'
        JsonAccessToken = '(?i)"(?:access_token|refresh_token|client_secret|password)"\s*:\s*"(?!\[REDACTED\])[^"\r\n]+"'
        PemPrivateKey = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
        BekFile = '(?i)\b[^\s"'']+\.bek\b'
    }

    $matches = @()
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($Text -match $entry.Value) {
            $matches += $entry.Key
        }
    }
    return @($matches)
}
