<#
.SYNOPSIS
Validates the CodexRescue.Graph read-only contract without a real tenant.
.DESCRIPTION
Imports the module, checks its local prerequisite report, and runs deterministic
in-memory Graph responses through the real GET broker and result sanitizer. No
network request, credential prompt, tenant, token, or cloud object is used.
.PARAMETER RepositoryRoot
Root of the checked-out or mounted Codex Rescue USB repository.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )
    if (!$Condition) { throw $Message }
}

$modulePath = Join-Path $RepositoryRoot 'PowerShell\Modules\CodexRescue.Graph\CodexRescue.Graph.psd1'
Assert-True (Test-Path -LiteralPath $modulePath -PathType Leaf) "Graph module manifest not found: $modulePath"
Import-Module $modulePath -Force -ErrorAction Stop
$module = Get-Module CodexRescue.Graph
$commands = @(Get-Command -Module CodexRescue.Graph -CommandType Function)
Assert-True ($commands.Count -eq 4) 'The Graph module did not export exactly four functions.'

$prerequisite = Test-CodexRescueGraphPrerequisite
Assert-True ($prerequisite.NetworkRequestPerformed -eq $false) 'The prerequisite test made a network request.'
Assert-True ($prerequisite.InstallationPerformed -eq $false) 'The prerequisite test changed installed software.'
Assert-True ($prerequisite.CredentialsCollected -eq $false) 'The prerequisite test collected credentials.'

$mockResult = & $module {
    function Get-MgContext {
        [pscustomobject]@{
            AuthType = 'Delegated'
            ContextScope = 'Process'
            Scopes = @(
                'Device.Read.All'
                'DeviceManagementManagedDevices.Read.All'
                'DeviceManagementServiceConfig.Read.All'
                'BitlockerKey.ReadBasic.All'
            )
        }
    }
    function Invoke-MgGraphRequest {
        [CmdletBinding()]
        param(
            [string]$Method,
            [string]$Uri,
            [object]$OutputType
        )
        if ($Method -ne 'GET') { throw 'Mock observed a non-GET request.' }
        if ($Uri -like '*windowsAutopilotDeviceIdentities*') {
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    enrollmentState = 'enrolled'
                    lastContactedDateTime = '2026-08-05T19:00:00Z'
                })
            }
        }
        if ($Uri -like '*managedDevices*') {
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    complianceState = 'compliant'
                    deviceEnrollmentType = 'windowsAutoEnrollment'
                    deviceRegistrationState = 'registered'
                    lastSyncDateTime = '2026-08-05T19:00:00Z'
                    managedDeviceOwnerType = 'company'
                    managementAgent = 'mdm'
                    managementState = 'managed'
                    operatingSystem = 'Windows'
                    osVersion = '10.0.26100'
                })
            }
        }
        if ($Uri -like '*/memberOf*') {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = '22222222-2222-4222-8222-222222222222' }
                    [pscustomobject]@{ id = '33333333-3333-4333-8333-333333333333' }
                )
            }
        }
        if ($Uri -like '*/bitlocker/recoveryKeys*') {
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    createdDateTime = '2026-08-05T18:00:00Z'
                    volumeType = 'operatingSystemVolume'
                })
            }
        }
        if ($Uri -like '*/devices(deviceId=*') {
            return [pscustomobject]@{
                id = '44444444-4444-4444-8444-444444444444'
                accountEnabled = $true
                approximateLastSignInDateTime = '2026-08-05T17:00:00Z'
                isCompliant = $true
                isManaged = $true
                operatingSystem = 'Windows'
                operatingSystemVersion = '10.0.26100'
                profileType = 'RegisteredDevice'
                trustType = 'AzureAd'
            }
        }
        throw "Mock received an unexpected URI: $Uri"
    }

    Get-CodexRescueCloudDeviceHealth -DeviceId '11111111-1111-4111-8111-111111111111'
}

Assert-True ($mockResult.Checks.Count -eq 5) 'The cloud assessment did not contain five bounded checks.'
Assert-True ($mockResult.CloudRequestsPerformed -eq 5) 'The cloud assessment did not report exactly five GET requests.'
Assert-True ($mockResult.WriteRequestsPerformed -eq 0) 'The cloud assessment reported a write request.'
Assert-True ($mockResult.IdentifiersIncluded -eq $false) 'The cloud assessment included identifiers.'
Assert-True ($mockResult.RecoveryKeyMaterialRequested -eq $false) 'The cloud assessment requested recovery-key material.'
Assert-True ($mockResult.RecoveryKeyMaterialCollected -eq $false) 'The cloud assessment collected recovery-key material.'
Assert-True ($mockResult.CredentialsCollected -eq $false) 'The cloud assessment collected credentials.'
Assert-True (($mockResult.HTTPMethodsUsed -join '|') -ceq 'GET') 'The cloud assessment reported a method other than GET.'

$expectedOutcomes = @('Healthy', 'Healthy', 'Healthy', 'Healthy', 'Healthy')
$actualOutcomes = @($mockResult.Checks | ForEach-Object Outcome)
Assert-True (($actualOutcomes -join '|') -ceq ($expectedOutcomes -join '|')) 'Unexpected happy-path cloud outcomes.'
$bitlocker = $mockResult.Checks | Where-Object CheckName -eq 'BitLockerEscrowAvailability'
Assert-True ($bitlocker.Data.BackupRecordCount -eq 1) 'The escrow-availability count was incorrect.'
Assert-True ($bitlocker.Data.RecoveryKeyValuesIncluded -eq $false) 'A recovery-key value leaked into the result.'
Assert-True ($bitlocker.Data.RecoveryKeyIdentifiersIncluded -eq $false) 'A recovery-key identifier leaked into the result.'

$json = $mockResult | ConvertTo-Json -Depth 20
Assert-True (!($json -match '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b')) 'A GUID-shaped identifier leaked into the cloud result.'
Assert-True (!($json -match '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b')) 'An email-shaped identifier leaked into the cloud result.'
Assert-True (!($json -match '(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)')) 'Recovery-password-shaped material leaked into the cloud result.'

$permissionResult = & $module {
    function Get-MgContext {
        [pscustomobject]@{
            AuthType = 'Delegated'; ContextScope = 'Process'
            Scopes = @('Device.Read.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceManagementServiceConfig.Read.All', 'BitlockerKey.ReadBasic.All')
        }
    }
    function Invoke-MgGraphRequest {
        [CmdletBinding()]
        param([string]$Method, [string]$Uri, [object]$OutputType)
        if ($Uri -like '*managedDevices*') {
            throw [UnauthorizedAccessException]::new('Forbidden')
        }
        if ($Uri -like '*/devices(deviceId=*') {
            return [pscustomobject]@{
                id = '66666666-6666-4666-8666-666666666666'; accountEnabled = $true
                isCompliant = $null; isManaged = $null; operatingSystem = 'Windows'
            }
        }
        return [pscustomobject]@{ value = @() }
    }
    Get-CodexRescueCloudDeviceHealth -DeviceId '11111111-1111-4111-8111-111111111111'
}
$permissionCheck = $permissionResult.Checks | Where-Object CheckName -eq 'IntuneCloud'
Assert-True ($permissionCheck.Outcome -eq 'PermissionDenied') 'A denied Intune query was not distinguished from not found or unavailable.'
Assert-True ($permissionCheck.Status -eq 'NotTested') 'A permission-denied check was incorrectly reported as device failure.'

$guardRejectedKeyRead = & $module {
    function Get-MgContext {
        [pscustomobject]@{
            AuthType = 'Delegated'; ContextScope = 'Process'
            Scopes = @('Device.Read.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceManagementServiceConfig.Read.All', 'BitlockerKey.ReadBasic.All')
        }
    }
    try {
        Invoke-CodexRescueGraphGet -RelativeUri '/v1.0/informationProtection/bitlocker/recoveryKeys/55555555-5555-4555-8555-555555555555?%24select=key'
        return $false
    }
    catch { return $true }
}
Assert-True $guardRejectedKeyRead 'The request broker did not reject a recovery-key value request.'

$guardRejectedUnsupportedBitLockerQuery = & $module {
    function Get-MgContext {
        [pscustomobject]@{
            AuthType = 'Delegated'; ContextScope = 'Process'
            Scopes = @('Device.Read.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceManagementServiceConfig.Read.All', 'BitlockerKey.ReadBasic.All')
        }
    }
    try {
        Invoke-CodexRescueGraphGet -RelativeUri '/v1.0/informationProtection/bitlocker/recoveryKeys?%24filter=deviceId%20eq%20%2711111111-1111-4111-8111-111111111111%27&%24top=1'
        return $false
    }
    catch { return $true }
}
Assert-True $guardRejectedUnsupportedBitLockerQuery 'The request broker accepted an unsupported BitLocker list query option.'

$guardRejectedExpandedScope = & $module {
    function Get-MgContext {
        [pscustomobject]@{
            AuthType = 'Delegated'; ContextScope = 'Process'
            Scopes = @('Device.Read.All', 'DeviceManagementManagedDevices.Read.All', 'DeviceManagementServiceConfig.Read.All', 'BitlockerKey.ReadBasic.All', 'Mail.Read')
        }
    }
    try {
        Assert-CodexRescueGraphSession | Out-Null
        return $false
    }
    catch { return $true }
}
Assert-True $guardRejectedExpandedScope 'The session guard accepted an unrelated delegated scope.'

[pscustomobject][ordered]@{
    Result = 'PASS'
    WindowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ExportedCommandCount = $commands.Count
    GraphAuthenticationModuleInstalled = $prerequisite.GraphAuthenticationModuleInstalled
    MockCloudRequestCount = $mockResult.CloudRequestsPerformed
    CloudCheckCount = $mockResult.Checks.Count
    WriteRequestCount = $mockResult.WriteRequestsPerformed
    RecoveryKeyMaterialRequested = $mockResult.RecoveryKeyMaterialRequested
    RecoveryKeyMaterialCollected = $mockResult.RecoveryKeyMaterialCollected
    IdentifiersIncluded = $mockResult.IdentifiersIncluded
    PermissionDeniedOutcome = $permissionCheck.Outcome
    RecoveryKeyRequestGuardPassed = $guardRejectedKeyRead
    BitLockerQueryContractGuardPassed = $guardRejectedUnsupportedBitLockerQuery
    ExpandedScopeGuardPassed = $guardRejectedExpandedScope
} | Format-List
