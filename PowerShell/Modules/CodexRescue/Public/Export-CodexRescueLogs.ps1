function Export-CodexRescueLogs {
    <#
    .SYNOPSIS
    Exports a new local assessment folder and a sanitized escalation ZIP.
    .DESCRIPTION
    Refuses existing destinations, validates the read-only assessment, writes a
    detailed local JSON/HTML report, writes separately sanitized Codex files,
    hashes every local output created before the manifest, and creates a
    sanitized sibling ZIP. Raw Intune
    and event logs are excluded unless the operator supplies the exact raw-log
    consent phrase; raw logs are never placed in the sanitized ZIP.
    .PARAMETER DestinationPath
    New destination directory. Its parent must already exist.
    .PARAMETER Assessment
    Optional assessment object. If omitted, a new local read-only assessment runs.
    .PARAMETER IncludeRawManagementLogs
    Collects local Intune text logs and selected Windows event channels for local review.
    .PARAMETER RawLogConfirmationToken
    Must exactly match INCLUDE RAW WINDOWS MANAGEMENT LOGS.
    .EXAMPLE
    Export-CodexRescueLogs -DestinationPath C:\Temp\CodexRescue\Assessment-001 -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [ValidateNotNull()]
        [object]$Assessment,

        [switch]$IncludeRawManagementLogs,
        [string]$RawLogConfirmationToken
    )

    Assert-CodexRescueWindows
    $requiredRawLogToken = 'INCLUDE RAW WINDOWS MANAGEMENT LOGS'
    if ($IncludeRawManagementLogs -and $RawLogConfirmationToken -cne $requiredRawLogToken) {
        throw 'Raw-log consent was not entered exactly. No files were exported.'
    }
    if (!$Assessment) {
        $Assessment = Get-CodexRescueDeviceHealth
    }
    $validation = Invoke-CodexRescueValidation -Assessment $Assessment
    if (!$validation.ValidationPassed) {
        throw "The assessment failed validation and was not exported: $($validation.Errors -join '; ')"
    }

    $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
    $parent = Split-Path -Parent $destinationFull
    if (!(Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Create the export parent directory first: $parent"
    }
    if (Test-Path -LiteralPath $destinationFull) {
        throw "The destination already exists and will not be overwritten: $destinationFull"
    }
    $zipPath = "$destinationFull-sanitized.zip"
    if (Test-Path -LiteralPath $zipPath) {
        throw "The sanitized escalation ZIP already exists and will not be overwritten: $zipPath"
    }

    if (!$PSCmdlet.ShouldProcess($destinationFull, 'Create read-only assessment export and sanitized escalation ZIP')) {
        return
    }

    $stage = Join-Path $parent ('.codexrescue-stage-{0}' -f [guid]::NewGuid().ToString('N'))
    $escalationStage = Join-Path $parent ('.codexrescue-escalation-{0}' -f [guid]::NewGuid().ToString('N'))
    $completed = $false
    try {
        New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
        $folders = @(
            'DeviceInfo', 'Autopilot', 'Intune', 'Entra', 'Certificates',
            'BitLocker', 'TPM', 'WindowsUpdate', 'EventLogs', 'Network',
            'Drivers', 'Registry', 'Reports', 'Screenshots', 'CodexAnalysis'
        )
        foreach ($folder in $folders) {
            New-Item -ItemType Directory -Path (Join-Path $stage $folder) -ErrorAction Stop | Out-Null
        }

        $detailedJsonPath = Join-Path $stage 'DeviceInfo\CodexRescueAssessment.local.json'
        $Assessment | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $detailedJsonPath -Encoding UTF8
        $detailedReportPath = Join-Path $stage 'Reports\CodexRescueReport.local.html'
        $null = New-CodexRescueReport -Assessment $Assessment -OutputPath $detailedReportPath -Confirm:$false

        $sanitized = Protect-CodexRescueAssessment -Assessment $Assessment
        $sanitizedJson = $sanitized | ConvertTo-Json -Depth 20
        $sanitizedSecretMatches = @(Test-CodexRescueSecretMaterial -Text $sanitizedJson)
        if ($sanitizedSecretMatches.Count -gt 0) {
            throw "The sanitized assessment contains a prohibited pattern: $($sanitizedSecretMatches -join ', ')"
        }
        $sanitizedJsonPath = Join-Path $stage 'CodexAnalysis\CodexRescueAssessment.sanitized.json'
        $sanitizedJson | Set-Content -LiteralPath $sanitizedJsonPath -Encoding UTF8
        $sanitizedReportPath = Join-Path $stage 'CodexAnalysis\CodexRescueReport.sanitized.html'
        $null = New-CodexRescueReport -Assessment $sanitized -OutputPath $sanitizedReportPath -Confirm:$false

        $rawLogResult = [ordered]@{
            Included = $false
            IntuneLogCount = 0
            ExportedEventChannelCount = 0
            FailedEventChannelCount = 0
            MdmDiagnosticsArchiveCreated = $false
        }
        if ($IncludeRawManagementLogs) {
            $rawLogResult.Included = $true
            $imeSource = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
            if (Test-Path -LiteralPath $imeSource -PathType Container) {
                $imeDestination = Join-Path $stage 'Intune\IntuneManagementExtension'
                New-Item -ItemType Directory -Path $imeDestination | Out-Null
                foreach ($log in @(Get-ChildItem -LiteralPath $imeSource -Filter '*.log' -File -ErrorAction SilentlyContinue)) {
                    Copy-Item -LiteralPath $log.FullName -Destination $imeDestination -ErrorAction Stop
                    $rawLogResult.IntuneLogCount++
                }
            }

            $eventChannels = @(
                'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin',
                'Microsoft-Windows-AAD/Operational',
                'Microsoft-Windows-User Device Registration/Admin',
                'Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin',
                'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot',
                'Microsoft-Windows-WindowsUpdateClient/Operational',
                'Microsoft-Windows-BitLocker/BitLocker Management',
                'Microsoft-Windows-TPM-WMI/Admin',
                'Microsoft-Windows-Kernel-Boot/Operational',
                'System', 'Application', 'Setup'
            )
            $channelIndex = 0
            foreach ($channel in $eventChannels) {
                $channelIndex++
                if (!(Get-WinEvent -ListLog $channel -ErrorAction SilentlyContinue)) {
                    continue
                }
                $eventPath = Join-Path $stage ('EventLogs\{0:D2}.evtx' -f $channelIndex)
                & wevtutil.exe epl $channel $eventPath /ow:false 2>$null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $eventPath -PathType Leaf)) {
                    $rawLogResult.ExportedEventChannelCount++
                }
                else {
                    $rawLogResult.FailedEventChannelCount++
                }
            }

            $mdmTool = Get-Command mdmdiagnosticstool.exe -ErrorAction SilentlyContinue
            if ($mdmTool) {
                $mdmPath = Join-Path $stage 'Intune\MdmDiagnostics.local-review-required.zip'
                & $mdmTool.Source -area 'DeviceEnrollment;DeviceProvisioning;Autopilot' -zip $mdmPath 2>$null
                $rawLogResult.MdmDiagnosticsArchiveCreated = (Test-Path -LiteralPath $mdmPath -PathType Leaf)
            }
        }
        [pscustomobject]$rawLogResult | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'Reports\raw-log-collection.json') -Encoding UTF8

        $fileRecords = @(
            Get-ChildItem -LiteralPath $stage -Recurse -File |
                Sort-Object FullName |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        RelativePath = $_.FullName.Substring($stage.Length + 1)
                        SizeBytes = $_.Length
                        Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                    }
                }
        )
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1
            CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            AssessmentReadOnly = $true
            RepairActionsPerformed = 0
            CloudRequestsPerformed = [int]$Assessment.CloudRequestsPerformed
            RawManagementLogsIncluded = [bool]$IncludeRawManagementLogs
            RawManagementLogsExcludedFromEscalationZip = $true
            EscalationZipSanitized = $true
            RecoveryMaterialCollected = $false
            CredentialsCollected = $false
            OperatorReviewRequired = $true
            Files = @($fileRecords)
        }
        $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8

        New-Item -ItemType Directory -Path $escalationStage -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath $sanitizedJsonPath -Destination (Join-Path $escalationStage 'CodexRescueAssessment.sanitized.json')
        Copy-Item -LiteralPath $sanitizedReportPath -Destination (Join-Path $escalationStage 'CodexRescueReport.sanitized.html')
        [pscustomobject][ordered]@{
            SchemaVersion = 1
            Sanitized = $true
            RawLogsIncluded = $false
            RecoveryMaterialIncluded = $false
            CredentialsIncluded = $false
            OperatorReviewRequired = $true
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $escalationStage 'README.json') -Encoding UTF8
        Compress-Archive -Path (Join-Path $escalationStage '*') -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop

        Move-Item -LiteralPath $stage -Destination $destinationFull -ErrorAction Stop
        $stage = $null
        $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
        $completed = $true
        [pscustomobject][ordered]@{
            SchemaVersion = 1
            DestinationPath = $destinationFull
            SanitizedZipPath = $zipPath
            SanitizedZipSha256 = $zipHash
            HealthScore = [int]$Assessment.HealthScore
            RawManagementLogsIncluded = [bool]$IncludeRawManagementLogs
            RawManagementLogsExcludedFromEscalationZip = $true
            RecoveryMaterialCollected = $false
            CredentialsCollected = $false
            OperatorReviewRequired = $true
        }
    }
    finally {
        if ($stage -and (Test-Path -LiteralPath $stage)) {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
        if (Test-Path -LiteralPath $escalationStage) {
            Remove-Item -LiteralPath $escalationStage -Recurse -Force
        }
        if (!$completed -and (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
            Remove-Item -LiteralPath $zipPath -Force
        }
    }
}
