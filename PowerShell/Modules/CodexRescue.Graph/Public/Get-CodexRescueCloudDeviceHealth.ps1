function Get-CodexRescueCloudDeviceHealth {
    <#
    .SYNOPSIS
    Runs bounded read-only Entra, Intune, Autopilot, group, and escrow checks.
    .DESCRIPTION
    Uses one verified local Entra device ID only in memory. The returned result
    excludes device, directory, tenant, group, recovery-key, and user identifiers.
    No raw Graph response or exception is returned.
    .PARAMETER DeviceId
    Optional locally verified Entra device ID. When omitted, one unambiguous ID
    is read from the local CloudDomainJoin registry state.
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$DeviceId
    )

    $null = Assert-CodexRescueGraphSession
    $script:CodexRescueGraphRequestCount = 0
    $deviceIdText = if ($DeviceId) { ([guid]$DeviceId).ToString('D') } else { Get-CodexRescueLocalDeviceId }
    if (!$deviceIdText) {
        $checks = @(
            'EntraCloud', 'IntuneCloud', 'AutopilotCloud', 'GroupMembershipCloud', 'BitLockerEscrowAvailability'
        ) | ForEach-Object {
            New-CodexRescueCloudCheck -Name $_ -Outcome 'NotTested' `
                -Summary 'No unambiguous local Entra device ID was available; no cloud request was made.' `
                -Data ([pscustomobject]@{ QueryPerformed = $false })
        }
        $result = [pscustomobject][ordered]@{
            SchemaVersion = 1
            AssessmentType = 'CodexRescue.ReadOnlyCloudDeviceHealth'
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            ReadOnly = $true
            DelegatedAuthentication = $true
            ContextScope = 'Process'
            CloudRequestsPerformed = 0
            HTTPMethodsUsed = @('GET')
            WriteRequestsPerformed = 0
            IdentifiersIncluded = $false
            LocalDeviceIdUsedInMemory = $false
            RawResponsesIncluded = $false
            RecoveryKeyMaterialRequested = $false
            RecoveryKeyMaterialCollected = $false
            CredentialsCollected = $false
            OperatorReviewRequired = $true
            Checks = @($checks)
        }
        $null = Assert-CodexRescueCloudResult -Assessment $result
        return $result
    }

    function Get-ResponseValue {
        param([object]$Response, [string]$Name)
        if ($null -eq $Response) { return $null }
        if ($Response -is [Collections.IDictionary]) { return $Response[$Name] }
        $property = $Response.PSObject.Properties[$Name]
        if ($property) { return $property.Value }
        return $null
    }
    function Get-ResponseItems {
        param([object]$Response)
        $value = Get-ResponseValue -Response $Response -Name 'value'
        if ($null -eq $value) { return @() }
        return @($value)
    }
    function New-QueryFailureCheck {
        param([string]$Name, [string]$Outcome)
        $summary = switch ($Outcome) {
            'PermissionDenied' { 'Microsoft Graph denied the bounded read-only query.' }
            'NotFound' { 'No matching cloud record was found.' }
            default { 'The bounded read-only cloud query was unavailable.' }
        }
        New-CodexRescueCloudCheck -Name $Name -Outcome $Outcome -Summary $summary `
            -Data ([pscustomobject]@{ QueryPerformed = $true; RawErrorIncluded = $false })
    }

    $selectDevice = [Uri]::EscapeDataString('id,accountEnabled,approximateLastSignInDateTime,isCompliant,isManaged,operatingSystem,operatingSystemVersion,profileType,trustType')
    $entraUri = "/v1.0/devices(deviceId='$deviceIdText')?%24select=$selectDevice"
    $entraQuery = Invoke-CodexRescueGraphQuerySafely -RelativeUri $entraUri
    $directoryObjectId = $null
    if ($entraQuery.Outcome -ne 'Success') {
        $entraCheck = New-QueryFailureCheck -Name 'EntraCloud' -Outcome $entraQuery.Outcome
    }
    else {
        $entra = $entraQuery.Response
        $directoryObjectId = [string](Get-ResponseValue $entra 'id')
        $accountEnabled = [bool](Get-ResponseValue $entra 'accountEnabled')
        $entraOutcome = if ($accountEnabled) { 'Healthy' } else { 'Warning' }
        $entraCheck = New-CodexRescueCloudCheck -Name 'EntraCloud' -Outcome $entraOutcome `
            -Summary 'A matching Microsoft Entra device record was returned without identifiers.' `
            -Data ([pscustomobject][ordered]@{
                RecordFound = $true
                AccountEnabled = $accountEnabled
                IsCompliant = Get-ResponseValue $entra 'isCompliant'
                IsManaged = Get-ResponseValue $entra 'isManaged'
                OperatingSystem = Get-ResponseValue $entra 'operatingSystem'
                OperatingSystemVersion = Get-ResponseValue $entra 'operatingSystemVersion'
                ProfileType = Get-ResponseValue $entra 'profileType'
                TrustType = Get-ResponseValue $entra 'trustType'
                ApproximateLastSignInDateTime = Get-ResponseValue $entra 'approximateLastSignInDateTime'
                IdentifiersIncluded = $false
            })
    }

    $managedFilter = [Uri]::EscapeDataString("azureADDeviceId eq '$deviceIdText'")
    $managedSelect = [Uri]::EscapeDataString('complianceState,deviceEnrollmentType,deviceRegistrationState,lastSyncDateTime,managedDeviceOwnerType,managementAgent,managementState,operatingSystem,osVersion')
    $intuneQuery = Invoke-CodexRescueGraphQuerySafely -RelativeUri "/v1.0/deviceManagement/managedDevices?%24filter=$managedFilter&%24select=$managedSelect&%24top=2"
    if ($intuneQuery.Outcome -ne 'Success') {
        $intuneCheck = New-QueryFailureCheck -Name 'IntuneCloud' -Outcome $intuneQuery.Outcome
    }
    else {
        $managedDevices = @(Get-ResponseItems $intuneQuery.Response)
        if ($managedDevices.Count -eq 0) {
            $intuneCheck = New-CodexRescueCloudCheck -Name 'IntuneCloud' -Outcome 'NotFound' `
                -Summary 'No matching Intune managed-device record was found.' `
                -Data ([pscustomobject]@{ RecordCount = 0; IdentifiersIncluded = $false })
        }
        else {
            $managed = $managedDevices[0]
            $complianceState = [string](Get-ResponseValue $managed 'complianceState')
            $intuneOutcome = if ($complianceState -eq 'compliant') { 'Healthy' } else { 'Warning' }
            $intuneCheck = New-CodexRescueCloudCheck -Name 'IntuneCloud' -Outcome $intuneOutcome `
                -Summary 'A matching Intune managed-device record was returned without device or user identifiers.' `
                -Data ([pscustomobject][ordered]@{
                    RecordCount = $managedDevices.Count
                    ComplianceState = $complianceState
                    DeviceEnrollmentType = Get-ResponseValue $managed 'deviceEnrollmentType'
                    DeviceRegistrationState = Get-ResponseValue $managed 'deviceRegistrationState'
                    LastSyncDateTime = Get-ResponseValue $managed 'lastSyncDateTime'
                    ManagedDeviceOwnerType = Get-ResponseValue $managed 'managedDeviceOwnerType'
                    ManagementAgent = Get-ResponseValue $managed 'managementAgent'
                    ManagementState = Get-ResponseValue $managed 'managementState'
                    OperatingSystem = Get-ResponseValue $managed 'operatingSystem'
                    OperatingSystemVersion = Get-ResponseValue $managed 'osVersion'
                    IdentifiersIncluded = $false
                })
        }
    }

    $autopilotFilter = [Uri]::EscapeDataString("azureActiveDirectoryDeviceId eq '$deviceIdText'")
    $autopilotSelect = [Uri]::EscapeDataString('enrollmentState,lastContactedDateTime')
    $autopilotQuery = Invoke-CodexRescueGraphQuerySafely -RelativeUri "/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?%24filter=$autopilotFilter&%24select=$autopilotSelect&%24top=2"
    if ($autopilotQuery.Outcome -ne 'Success') {
        $autopilotCheck = New-QueryFailureCheck -Name 'AutopilotCloud' -Outcome $autopilotQuery.Outcome
    }
    else {
        $autopilotDevices = @(Get-ResponseItems $autopilotQuery.Response)
        if ($autopilotDevices.Count -eq 0) {
            $autopilotCheck = New-CodexRescueCloudCheck -Name 'AutopilotCloud' -Outcome 'NotFound' `
                -Summary 'No matching Windows Autopilot registration was found.' `
                -Data ([pscustomobject]@{ RecordCount = 0; IdentifiersIncluded = $false })
        }
        else {
            $autopilot = $autopilotDevices[0]
            $enrollmentState = [string](Get-ResponseValue $autopilot 'enrollmentState')
            $autopilotOutcome = if ($enrollmentState -eq 'enrolled') { 'Healthy' } else { 'Warning' }
            $autopilotCheck = New-CodexRescueCloudCheck -Name 'AutopilotCloud' -Outcome $autopilotOutcome `
                -Summary 'A matching Autopilot registration was returned without serial, user, tag, or object identifiers.' `
                -Data ([pscustomobject][ordered]@{
                    RecordCount = $autopilotDevices.Count
                    EnrollmentState = $enrollmentState
                    LastContactedDateTime = Get-ResponseValue $autopilot 'lastContactedDateTime'
                    IdentifiersIncluded = $false
                })
        }
    }

    $parsedDirectoryId = [guid]::Empty
    if (![guid]::TryParse($directoryObjectId, [ref]$parsedDirectoryId)) {
        $membershipCheck = New-CodexRescueCloudCheck -Name 'GroupMembershipCloud' -Outcome 'NotTested' `
            -Summary 'No matching Entra directory object was available for membership counting.' `
            -Data ([pscustomobject]@{ QueryPerformed = $false; GroupNamesIncluded = $false })
    }
    else {
        $memberSelect = [Uri]::EscapeDataString('id')
        $membershipQuery = Invoke-CodexRescueGraphQuerySafely -RelativeUri "/v1.0/devices/$($parsedDirectoryId.ToString('D'))/memberOf?%24select=$memberSelect&%24top=100"
        if ($membershipQuery.Outcome -ne 'Success') {
            $membershipCheck = New-QueryFailureCheck -Name 'GroupMembershipCloud' -Outcome $membershipQuery.Outcome
        }
        else {
            $memberItems = @(Get-ResponseItems $membershipQuery.Response)
            $membershipOutcome = if ($memberItems.Count -gt 0) { 'Healthy' } else { 'NotFound' }
            $membershipCheck = New-CodexRescueCloudCheck -Name 'GroupMembershipCloud' -Outcome $membershipOutcome `
                -Summary 'Direct directory membership was counted without returning group names or identifiers.' `
                -Data ([pscustomobject][ordered]@{
                    DirectMembershipCount = $memberItems.Count
                    ResultTruncated = [bool](Get-ResponseValue $membershipQuery.Response '@odata.nextLink')
                    GroupNamesIncluded = $false
                    GroupIdentifiersIncluded = $false
                })
        }
    }

    $bitlockerFilter = [Uri]::EscapeDataString("deviceId eq '$deviceIdText'")
    $bitlockerQuery = Invoke-CodexRescueGraphQuerySafely -RelativeUri "/v1.0/informationProtection/bitlocker/recoveryKeys?%24filter=$bitlockerFilter"
    if ($bitlockerQuery.Outcome -ne 'Success') {
        $bitlockerCheck = New-QueryFailureCheck -Name 'BitLockerEscrowAvailability' -Outcome $bitlockerQuery.Outcome
    }
    else {
        $keyRecords = @(Get-ResponseItems $bitlockerQuery.Response)
        $backupDates = @($keyRecords | ForEach-Object { Get-ResponseValue $_ 'createdDateTime' } | Where-Object { $_ } | Sort-Object)
        $volumeTypes = @($keyRecords | ForEach-Object { [string](Get-ResponseValue $_ 'volumeType') } | Where-Object { $_ } | Sort-Object -Unique)
        $bitlockerOutcome = if ($keyRecords.Count -gt 0) { 'Healthy' } else { 'NotFound' }
        $bitlockerCheck = New-CodexRescueCloudCheck -Name 'BitLockerEscrowAvailability' -Outcome $bitlockerOutcome `
            -Summary 'BitLocker escrow availability was counted without requesting a recovery key value or key identifier.' `
            -Data ([pscustomobject][ordered]@{
                BackupRecordCount = $keyRecords.Count
                BackupExists = ($keyRecords.Count -gt 0)
                MostRecentBackupDateTime = if ($backupDates.Count) { $backupDates[-1] } else { $null }
                VolumeTypes = @($volumeTypes)
                ResultTruncated = [bool](Get-ResponseValue $bitlockerQuery.Response '@odata.nextLink')
                ApiMayReturnRecoveryKeyIdentifiers = $true
                RecoveryKeyValuesIncluded = $false
                RecoveryKeyIdentifiersIncluded = $false
            })
    }

    $checks = @($entraCheck, $intuneCheck, $autopilotCheck, $membershipCheck, $bitlockerCheck)
    $result = [pscustomobject][ordered]@{
        SchemaVersion = 1
        AssessmentType = 'CodexRescue.ReadOnlyCloudDeviceHealth'
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        ReadOnly = $true
        DelegatedAuthentication = $true
        ContextScope = 'Process'
        RequiredScopeCount = @(Get-CodexRescueGraphRequiredScope).Count
        CloudRequestsPerformed = $script:CodexRescueGraphRequestCount
        HTTPMethodsUsed = @('GET')
        WriteRequestsPerformed = 0
        IdentifiersIncluded = $false
        LocalDeviceIdUsedInMemory = $true
        RawResponsesIncluded = $false
        RecoveryKeyMaterialRequested = $false
        RecoveryKeyMaterialCollected = $false
        CredentialsCollected = $false
        OperatorReviewRequired = $true
        Checks = @($checks)
    }
    $null = Assert-CodexRescueCloudResult -Assessment $result
    return $result
}
