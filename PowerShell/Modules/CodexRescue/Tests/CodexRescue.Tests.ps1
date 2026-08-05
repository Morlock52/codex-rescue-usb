BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\CodexRescue.psd1'
    Import-Module $modulePath -Force

    function New-TestCodexRescueAssessment {
        param([string]$Summary = 'Synthetic read-only test result')

        $checks = foreach ($name in @(
            'Autopilot', 'Intune', 'Entra', 'Certificates', 'BitLocker',
            'TPM', 'WindowsUpdate', 'Network', 'Drivers', 'EventErrors'
        )) {
            [pscustomobject]@{
                SchemaVersion = 1
                CheckName = $name
                Status = 'Healthy'
                Summary = $Summary
                CheckedAtUtc = '2026-08-05T00:00:00.0000000Z'
                Data = [pscustomobject]@{ Synthetic = $true }
                Errors = @()
                RecoveryMaterialCollected = $false
                CredentialsCollected = $false
                RawMessagesIncluded = $false
            }
        }
        [pscustomobject]@{
            SchemaVersion = 1
            AssessmentType = 'CodexRescue.ReadOnlyDeviceHealth'
            GeneratedAtUtc = '2026-08-05T00:00:00.0000000Z'
            ReadOnly = $true
            RepairActionsPerformed = 0
            CloudRequestsPerformed = 0
            OnlineNetworkTestsPerformed = $false
            RecoveryMaterialCollected = $false
            CredentialsCollected = $false
            SanitizationRequiredBeforeCodex = $true
            DeviceSummary = [pscustomobject]@{
                ComputerName = '<script>alert(1)</script>'
                SerialNumber = 'SYNTHETIC-SERIAL'
            }
            OfflineWindowsInstallationCount = 0
            OfflineWindowsInstallations = @()
            HealthScore = 100
            TestedCheckCount = 10
            NotTestedCheckCount = 0
            Checks = @($checks)
        }
    }
}

Describe 'CodexRescue module contract' {
    It 'exports every Phase 1 command and no repair command' {
        $expected = @(
            'Export-CodexRescueLogs',
            'Get-CodexRescueAutopilotStatus',
            'Get-CodexRescueBitLockerStatus',
            'Get-CodexRescueCertificateHealth',
            'Get-CodexRescueDeviceHealth',
            'Get-CodexRescueDriverStatus',
            'Get-CodexRescueEntraStatus',
            'Get-CodexRescueEventErrors',
            'Get-CodexRescueIntuneStatus',
            'Get-CodexRescueNetworkStatus',
            'Get-CodexRescueTpmStatus',
            'Get-CodexRescueWindowsUpdateStatus',
            'Invoke-CodexRescueValidation',
            'New-CodexRescueReport'
        )
        $actual = @((Get-Module CodexRescue).ExportedFunctions.Keys | Sort-Object)
        Compare-Object ($expected | Sort-Object) $actual | Should -BeNullOrEmpty
        Get-Command Invoke-CodexRescueSafeRepair -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'accepts the complete read-only assessment contract' {
        $result = Invoke-CodexRescueValidation -Assessment (New-TestCodexRescueAssessment)
        $result.ValidationPassed | Should -BeTrue
        $result.CheckCount | Should -Be 10
        $result.SecretPatternCount | Should -Be 0
    }

    It 'rejects BitLocker recovery-password-shaped material' {
        $assessment = New-TestCodexRescueAssessment -Summary '123456-123456-123456-123456-123456-123456-123456-123456'
        $result = Invoke-CodexRescueValidation -Assessment $assessment
        $result.ValidationPassed | Should -BeFalse
        $result.SecretPatternCount | Should -Be 1
        { Invoke-CodexRescueValidation -Assessment $assessment -Strict } | Should -Throw
    }

    It 'rejects cloud activity and a duplicate diagnostic check' {
        $assessment = New-TestCodexRescueAssessment
        $assessment.CloudRequestsPerformed = 1
        $assessment.Checks = @($assessment.Checks) + @($assessment.Checks[0])
        $result = Invoke-CodexRescueValidation -Assessment $assessment
        $result.ValidationPassed | Should -BeFalse
        $result.Errors | Should -Contain 'A Phase 1 assessment cannot report cloud requests.'
        ($result.Errors -join "`n") | Should -Match 'Duplicate diagnostic check: Autopilot'
        ($result.Errors -join "`n") | Should -Match 'Expected exactly 10 diagnostic checks; found 11.'
    }

    It 'redacts diagnostic errors and volume paths from the sanitized object' {
        $assessment = New-TestCodexRescueAssessment
        $assessment.Checks[0].Errors = @('C:\Users\SensitiveName\diagnostic.txt')
        $assessment.Checks[0].Data = [pscustomobject]@{
            MountPoint = 'Q:'
            Root = 'Q:\Windows'
            SafeCount = 2
        }
        $module = Get-Module CodexRescue
        $protected = & $module {
            param($InputAssessment)
            Protect-CodexRescueAssessment -Assessment $InputAssessment
        } $assessment
        $protected.Checks[0].Errors | Should -Be '[REDACTED]'
        $protected.Checks[0].Data.MountPoint | Should -Be '[REDACTED]'
        $protected.Checks[0].Data.Root | Should -Be '[REDACTED]'
        $protected.Checks[0].Data.SafeCount | Should -Be 2
    }

    It 'HTML-encodes values and refuses to overwrite reports' {
        $reportPath = Join-Path $TestDrive 'report.html'
        $null = New-CodexRescueReport -Assessment (New-TestCodexRescueAssessment) -OutputPath $reportPath -Confirm:$false
        $html = Get-Content -LiteralPath $reportPath -Raw
        $html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $html | Should -Not -Match '<script>alert\(1\)</script>'
        { New-CodexRescueReport -Assessment (New-TestCodexRescueAssessment) -OutputPath $reportPath -Confirm:$false } | Should -Throw
    }
}
