function Invoke-CodexRescueValidation {
    <#
    .SYNOPSIS
    Validates a Codex Rescue assessment contract and scans for prohibited secret material.
    .PARAMETER Assessment
    Assessment object to validate.
    .PARAMETER Strict
    Throws when validation fails; otherwise returns a result object.
    .EXAMPLE
    Get-CodexRescueDeviceHealth | Invoke-CodexRescueValidation -Strict
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$Assessment,

        [switch]$Strict
    )

    process {
        $errors = @()
        $requiredProperties = @(
            'SchemaVersion', 'AssessmentType', 'GeneratedAtUtc', 'ReadOnly',
            'RepairActionsPerformed', 'CloudRequestsPerformed',
            'OnlineNetworkTestsPerformed', 'RecoveryMaterialCollected',
            'CredentialsCollected', 'SanitizationRequiredBeforeCodex',
            'HealthScore', 'Checks'
        )
        foreach ($property in $requiredProperties) {
            if ($Assessment.PSObject.Properties.Name -notcontains $property) {
                $errors += "Missing required assessment property: $property"
            }
        }
        if ($Assessment.PSObject.Properties.Name -contains 'SchemaVersion' -and $Assessment.SchemaVersion -ne 1) {
            $errors += 'SchemaVersion must be 1.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'ReadOnly' -and $Assessment.ReadOnly -ne $true) {
            $errors += 'The Phase 1 assessment must declare ReadOnly=true.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'RepairActionsPerformed' -and $Assessment.RepairActionsPerformed -ne 0) {
            $errors += 'A read-only assessment cannot report repair actions.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'CloudRequestsPerformed' -and $Assessment.CloudRequestsPerformed -ne 0) {
            $errors += 'A Phase 1 assessment cannot report cloud requests.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'SanitizationRequiredBeforeCodex' -and $Assessment.SanitizationRequiredBeforeCodex -ne $true) {
            $errors += 'A Phase 1 assessment must require sanitization before Codex use.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'RecoveryMaterialCollected' -and $Assessment.RecoveryMaterialCollected -ne $false) {
            $errors += 'Recovery material must not be collected.'
        }
        if ($Assessment.PSObject.Properties.Name -contains 'CredentialsCollected' -and $Assessment.CredentialsCollected -ne $false) {
            $errors += 'Credentials must not be collected.'
        }

        $expectedChecks = @('Autopilot', 'Intune', 'Entra', 'Certificates', 'BitLocker', 'TPM', 'WindowsUpdate', 'Network', 'Drivers', 'EventErrors')
        $actualChecks = @($Assessment.Checks | ForEach-Object { $_.CheckName })
        if ($actualChecks.Count -ne $expectedChecks.Count) {
            $errors += "Expected exactly $($expectedChecks.Count) diagnostic checks; found $($actualChecks.Count)."
        }
        $duplicateChecks = @($actualChecks | Group-Object | Where-Object Count -GT 1 | Select-Object -ExpandProperty Name)
        foreach ($duplicateCheck in $duplicateChecks) {
            $errors += "Duplicate diagnostic check: $duplicateCheck"
        }
        foreach ($checkName in $expectedChecks) {
            if ($actualChecks -notcontains $checkName) {
                $errors += "Missing required diagnostic check: $checkName"
            }
        }
        foreach ($check in @($Assessment.Checks)) {
            if ($check.Status -notin @('Healthy', 'Warning', 'Failed', 'NotTested')) {
                $errors += "Invalid status '$($check.Status)' for check '$($check.CheckName)'."
            }
            if ($check.RecoveryMaterialCollected -ne $false -or $check.CredentialsCollected -ne $false) {
                $errors += "Check '$($check.CheckName)' does not preserve the secret-material boundary."
            }
        }

        $json = $Assessment | ConvertTo-Json -Depth 20
        $secretMatches = @(Test-CodexRescueSecretMaterial -Text $json)
        foreach ($secretMatch in $secretMatches) {
            $errors += "Prohibited secret-material pattern detected: $secretMatch"
        }
        $result = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ValidationPassed = ($errors.Count -eq 0)
            ValidatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            CheckCount = @($Assessment.Checks).Count
            SecretPatternCount = $secretMatches.Count
            Errors = @($errors)
        }
        if ($Strict -and !$result.ValidationPassed) {
            throw "Codex Rescue assessment validation failed: $($errors -join '; ')"
        }
        return $result
    }
}
