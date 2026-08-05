function Assert-CodexRescueCloudResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Assessment
    )

    $errors = @()
    if ($Assessment.ReadOnly -ne $true -or $Assessment.WriteRequestsPerformed -ne 0) {
        $errors += 'Cloud result must remain read-only with zero write requests.'
    }
    if ($Assessment.RecoveryKeyMaterialRequested -ne $false -or $Assessment.RecoveryKeyMaterialCollected -ne $false) {
        $errors += 'RecoveryKeyMaterialCollected -ne $false or recovery material was requested.'
    }
    if ($Assessment.CredentialsCollected -ne $false) {
        $errors += 'CredentialsCollected -ne $false.'
    }
    if ($Assessment.IdentifiersIncluded -ne $false) {
        $errors += 'IdentifiersIncluded must be false.'
    }
    foreach ($check in @($Assessment.Checks)) {
        if ($check.Outcome -notin @('Healthy', 'Warning', 'Failed', 'NotTested', 'PermissionDenied', 'NotFound', 'Unavailable')) {
            $errors += "Invalid cloud check outcome: $($check.Outcome)"
        }
    }

    $json = $Assessment | ConvertTo-Json -Depth 20
    $patterns = [ordered]@{
        'GUID-shaped identifier' = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
        'email-shaped identifier' = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        'recovery-password-shaped value' = '(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)'
        'token-shaped value' = '(?i)authorization\s*:\s*bearer|access[_ -]?token|refresh[_ -]?token|eyJ[A-Za-z0-9_-]{12,}\.'
    }
    foreach ($name in $patterns.Keys) {
        if ([regex]::IsMatch($json, $patterns[$name])) {
            $errors += "Cloud result contains a $name."
        }
    }
    if ($errors.Count -gt 0) {
        throw "Codex Rescue cloud result validation failed: $($errors -join '; ')"
    }
    return $true
}
