function New-CodexRescueCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Healthy', 'Warning', 'Failed', 'NotTested')]
        [string]$Status,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Data,

        [string[]]$Errors = @()
    )

    [pscustomobject][ordered]@{
        SchemaVersion = 1
        CheckName = $Name
        Status = $Status
        Summary = $Summary
        CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        Data = $Data
        Errors = @($Errors)
        RecoveryMaterialCollected = $false
        CredentialsCollected = $false
        RawMessagesIncluded = $false
    }
}
