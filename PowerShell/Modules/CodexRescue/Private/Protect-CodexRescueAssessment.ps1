function Protect-CodexRescueAssessmentValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [string]$PropertyName = ''
    )

    $sensitiveNamePattern = '(?i)(serial(number)?|computername|currentuser|username|userprincipalname|deviceid|tenantid|enrollmentid|thumbprint|subject|issuer|ip(address)?|mac(address)?|gateway|dnsserver|hardwarehash|keyprotectorid|recovery(password|key)|access(token)?|refresh(token)?|clientsecret|password|privatekey|error(s)?|exception|mountpoint|filepath|fullpath|root)'
    if ($PropertyName -match $sensitiveNamePattern) {
        if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $null -eq $Value) {
            return $Value
        }
        return '[REDACTED]'
    }
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [datetime]) {
        return $Value
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $copy[[string]$key] = Protect-CodexRescueAssessmentValue -Value $Value[$key] -PropertyName ([string]$key)
        }
        return [pscustomobject]$copy
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value | ForEach-Object { Protect-CodexRescueAssessmentValue -Value $_ })
    }

    $objectCopy = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        $objectCopy[$property.Name] = Protect-CodexRescueAssessmentValue -Value $property.Value -PropertyName $property.Name
    }
    return [pscustomobject]$objectCopy
}

function Protect-CodexRescueAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Assessment
    )

    $protected = Protect-CodexRescueAssessmentValue -Value $Assessment
    $protected | Add-Member -NotePropertyName SanitizedForCodex -NotePropertyValue $true -Force
    $protected | Add-Member -NotePropertyName OperatorReviewRequired -NotePropertyValue $true -Force
    $protected | Add-Member -NotePropertyName RawLogsIncluded -NotePropertyValue $false -Force
    return $protected
}
