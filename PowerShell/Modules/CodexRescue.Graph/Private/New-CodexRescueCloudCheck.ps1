function New-CodexRescueCloudCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'Warning', 'Failed', 'NotTested', 'PermissionDenied', 'NotFound', 'Unavailable')]
        [string]$Outcome,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [AllowNull()]
        [object]$Data
    )

    $status = switch ($Outcome) {
        'Healthy' { 'Healthy' }
        'Warning' { 'Warning' }
        'Failed' { 'Failed' }
        default { 'NotTested' }
    }
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        CheckName = $Name
        Status = $status
        Outcome = $Outcome
        Summary = $Summary
        CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Data = $Data
        RawResponseIncluded = $false
        IdentifiersIncluded = $false
        RecoveryKeyMaterialRequested = $false
        RecoveryKeyMaterialCollected = $false
        CredentialsCollected = $false
    }
}
