<#
.SYNOPSIS
  Verifies the installed technician workspace before image generalization.
.DESCRIPTION
  Performs read-only checks for the full-Windows platform, offline network and
  startup policy, staged project payload, required allowlisted packages and
  PowerShell modules, the exact Codex CLI version, absence of persisted Codex
  or Graph authentication artifacts, and a privacy-safe install receipt.

  The script never enables networking, installs software, signs in, changes a
  scheduled task, or writes an evidence file.
  Contract fixtures never count as live generalization evidence.
.PARAMETER ManifestPath
  Path to the checked-in technician-workspace tool manifest.
.PARAMETER ProjectRoot
  Root of the staged Codex Rescue source payload.
.PARAMETER ReceiptPath
  Optional exact install receipt. Live collection otherwise selects the newest
  technician-toolchain receipt from C:\CodexRescueBuild\Toolchain.
.PARAMETER ContractFixturePath
  Optional JSON fixture for deterministic cross-platform contract tests. A
  passing fixture cannot set ReadyForGeneralization to true.
.PARAMETER AsJson
  Emits the bounded result as JSON.
.EXAMPLE
  .\Test-TechnicianWorkspaceToolchain.ps1 -AsJson
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\technician-workspace-tools.json'),

    [Parameter()]
    [string] $ProjectRoot = (Split-Path $PSScriptRoot -Parent),

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ReceiptPath,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ContractFixturePath,

    [Parameter()]
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-ToolchainCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Passed,

        [Parameter(Mandatory)]
        [string] $Message
    )

    [pscustomobject][ordered]@{
        Name = $Name
        Required = $true
        Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Message = $Message
    }
}

function Assert-ToolManifestContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Manifest
    )

    if ($Manifest.schemaVersion -ne 1) {
        throw "Unsupported technician tool manifest schema: $($Manifest.schemaVersion)"
    }
    if ($Manifest.policy.network -ne 'offline-default-explicit-maintenance-window' -or
        $Manifest.policy.persistCredentialsInImage -ne $false -or
        $Manifest.policy.allowCloudWriteActions -ne $false -or
        $Manifest.codexCli.persistAuthenticationInImage -ne $false) {
        throw 'The technician tool manifest does not satisfy the offline and no-credential contract.'
    }
}

function Get-ReceiptSnapshot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ExactReceiptPath
    )

    $candidate = $null
    if (-not [string]::IsNullOrWhiteSpace($ExactReceiptPath)) {
        $candidate = Get-Item -LiteralPath $ExactReceiptPath -ErrorAction Stop
    }
    else {
        $defaultDirectory = 'C:\CodexRescueBuild\Toolchain'
        if (Test-Path -LiteralPath $defaultDirectory -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath $defaultDirectory -Filter 'technician-toolchain-*.json' -File -ErrorAction Stop |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
        }
    }

    if ($null -eq $candidate) {
        return [pscustomobject][ordered]@{
            Present = $false
            ManifestAsOfDate = ''
            CodexIntegrityVerified = $false
            ContainsSensitiveMaterial = $false
        }
    }

    $rawReceipt = Get-Content -LiteralPath $candidate.FullName -Raw -Encoding UTF8
    $receipt = $rawReceipt | ConvertFrom-Json -ErrorAction Stop
    $sensitiveValuePattern = '"(?:accessToken|refreshToken|clientSecret|apiKey|recoveryKey|recoveryPassword)"\s*:\s*"[^"\s][^"]*"'

    [pscustomobject][ordered]@{
        Present = $true
        ManifestAsOfDate = [string]$receipt.ManifestAsOfDate
        CodexIntegrityVerified = [bool]$receipt.CodexCli.IntegrityVerified
        ContainsSensitiveMaterial = [regex]::IsMatch(
            $rawReceipt,
            $sensitiveValuePattern,
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
}

function Get-PersistedAuthenticationCounts {
    [CmdletBinding()]
    param()

    $profileDirectories = @()
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot -PathType Container) {
        $profileDirectories = @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)
    }

    $codexAuthCount = 0
    $cloudAuthCount = 0
    foreach ($profileDirectory in $profileDirectories) {
        foreach ($relativePath in @('.codex\auth.json', '.codex\credentials.json', '.codex\tokens.json')) {
            if (Test-Path -LiteralPath (Join-Path $profileDirectory.FullName $relativePath) -PathType Leaf) {
                $codexAuthCount++
            }
        }

        $graphProfileDirectory = Join-Path $profileDirectory.FullName '.mg'
        if (Test-Path -LiteralPath $graphProfileDirectory -PathType Container) {
            $cloudAuthCount += @(Get-ChildItem -LiteralPath $graphProfileDirectory -File -Recurse -Force -ErrorAction SilentlyContinue).Count
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        foreach ($authName in @('auth.json', 'credentials.json', 'tokens.json')) {
            if (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME $authName) -PathType Leaf) {
                $codexAuthCount++
            }
        }
    }

    $sensitiveEnvironmentVariableCount = 0
    foreach ($variableName in @('OPENAI_API_KEY', 'AZURE_OPENAI_API_KEY', 'AZURE_CLIENT_SECRET', 'MSGRAPH_CLIENT_SECRET')) {
        $isPresent = @('Process', 'User', 'Machine') | Where-Object {
            -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variableName, $_))
        }
        if (@($isPresent).Count -gt 0) {
            $sensitiveEnvironmentVariableCount++
        }
    }

    [pscustomobject][ordered]@{
        CodexAuthArtifactCount = $codexAuthCount
        CloudAuthArtifactCount = $cloudAuthCount
        SensitiveEnvironmentVariableCount = $sensitiveEnvironmentVariableCount
    }
}

function Get-LiveToolchainSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Manifest,

        [Parameter(Mandatory)]
        [string] $StagedProjectRoot,

        [Parameter()]
        [string] $ExactReceiptPath
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Live technician toolchain verification requires full Windows 11.'
    }

    $isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    $hardwareAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.HardwareInterface })
    $activeHardwareAdapters = @($hardwareAdapters | Where-Object { $_.Status -eq 'Up' })
    $offlineTask = Get-ScheduledTask -TaskName 'Codex Rescue Offline Startup' -ErrorAction SilentlyContinue
    $offlinePolicyPath = Join-Path $env:ProgramData 'CodexRescue\Disable-NetworkAtStartup.ps1'

    $requiredProjectPaths = @(
        'PowerShell\Modules\CodexRescue\CodexRescue.psd1',
        'PowerShell\Modules\CodexRescue.Graph\CodexRescue.Graph.psd1',
        'PowerShell\Dashboard\CodexRescueDashboard.xaml',
        'scripts\Open-CodexRecoveryWorkspace.ps1'
    )
    $projectPayloadPresent = @($requiredProjectPaths | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $StagedProjectRoot $_) -PathType Leaf)
    }).Count -eq 0

    $installedModules = @($Manifest.powerShellModules | ForEach-Object {
        $moduleName = [string]$_.name
        $moduleVersion = [string]$_.version
        $match = Get-Module -ListAvailable -Name $moduleName |
            Where-Object { $_.Version.ToString() -eq $moduleVersion } |
            Select-Object -First 1
        if ($null -ne $match) {
            [pscustomobject][ordered]@{ Name = $moduleName; Version = $moduleVersion }
        }
    })

    $installedWinGetPackages = @()
    $winGetModule = $Manifest.powerShellModules | Where-Object { $_.name -eq 'Microsoft.WinGet.Client' } | Select-Object -First 1
    $winGetModulePresent = $installedModules | Where-Object {
        $_.Name -eq 'Microsoft.WinGet.Client' -and $_.Version -eq [string]$winGetModule.version
    }
    if ($null -ne $winGetModulePresent) {
        Import-Module Microsoft.WinGet.Client -RequiredVersion ([version]$winGetModule.version) -Force -ErrorAction Stop
        foreach ($package in $Manifest.wingetPackages) {
            $matches = @(Get-WinGetPackage -Id ([string]$package.id) -MatchOption Equals -ErrorAction SilentlyContinue |
                Where-Object { $_.Id -ceq [string]$package.id })
            if ($matches.Count -eq 1) {
                $version = if ($matches[0].PSObject.Properties.Name -contains 'InstalledVersion') {
                    [string]$matches[0].InstalledVersion
                }
                else {
                    [string]$matches[0].Version
                }
                $installedWinGetPackages += [pscustomobject][ordered]@{
                    Id = [string]$package.id
                    Version = $version
                }
            }
        }
    }

    $codexCommand = Get-Command -Name @('codex.exe', 'codex.cmd', 'codex') -ErrorAction SilentlyContinue | Select-Object -First 1
    $codexVersion = ''
    if ($null -ne $codexCommand) {
        $reportedVersion = (& $codexCommand.Source --version 2>&1 | Out-String).Trim()
        if ($reportedVersion -match '(?<Version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)') {
            $codexVersion = $Matches.Version
        }
    }

    $authentication = Get-PersistedAuthenticationCounts
    $receipt = Get-ReceiptSnapshot -ExactReceiptPath $ExactReceiptPath

    [pscustomobject][ordered]@{
        IsWindows = $true
        IsWinPE = [bool]$isWinPE
        HardwareAdapterCount = $hardwareAdapters.Count
        ActiveHardwareAdapterCount = $activeHardwareAdapters.Count
        OfflineStartupTaskInstalled = ($null -ne $offlineTask)
        OfflineStartupPolicyPresent = (Test-Path -LiteralPath $offlinePolicyPath -PathType Leaf)
        ProjectPayloadPresent = $projectPayloadPresent
        InstalledWinGetPackages = $installedWinGetPackages
        InstalledPowerShellModules = $installedModules
        CodexCommandAvailable = ($null -ne $codexCommand)
        CodexVersion = $codexVersion
        CodexAuthArtifactCount = $authentication.CodexAuthArtifactCount
        CloudAuthArtifactCount = $authentication.CloudAuthArtifactCount
        SensitiveEnvironmentVariableCount = $authentication.SensitiveEnvironmentVariableCount
        ReceiptPresent = $receipt.Present
        ReceiptManifestAsOfDate = $receipt.ManifestAsOfDate
        ReceiptCodexIntegrityVerified = $receipt.CodexIntegrityVerified
        ReceiptContainsSensitiveMaterial = $receipt.ContainsSensitiveMaterial
    }
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
Assert-ToolManifestContract -Manifest $manifest

$allowedSnapshotProperties = @(
    'IsWindows',
    'IsWinPE',
    'HardwareAdapterCount',
    'ActiveHardwareAdapterCount',
    'OfflineStartupTaskInstalled',
    'OfflineStartupPolicyPresent',
    'ProjectPayloadPresent',
    'InstalledWinGetPackages',
    'InstalledPowerShellModules',
    'CodexCommandAvailable',
    'CodexVersion',
    'CodexAuthArtifactCount',
    'CloudAuthArtifactCount',
    'SensitiveEnvironmentVariableCount',
    'ReceiptPresent',
    'ReceiptManifestAsOfDate',
    'ReceiptCodexIntegrityVerified',
    'ReceiptContainsSensitiveMaterial'
)

$liveEvidence = -not $PSBoundParameters.ContainsKey('ContractFixturePath')
if ($liveEvidence) {
    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path
    $snapshot = Get-LiveToolchainSnapshot -Manifest $manifest -StagedProjectRoot $resolvedProjectRoot -ExactReceiptPath $ReceiptPath
    $evidenceSource = 'LiveWindows'
}
else {
    $snapshot = Get-Content -LiteralPath $ContractFixturePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $propertyNames = @($snapshot.PSObject.Properties.Name)
    $missingProperties = @($allowedSnapshotProperties | Where-Object { $_ -notin $propertyNames })
    $unexpectedProperties = @($propertyNames | Where-Object { $_ -notin $allowedSnapshotProperties })
    if ($missingProperties.Count -gt 0 -or $unexpectedProperties.Count -gt 0) {
        throw "Contract fixture properties do not match the allowlist. Missing=$($missingProperties -join ','); Unexpected=$($unexpectedProperties -join ',')"
    }
    $evidenceSource = 'ContractFixture'
}

$requiredWinGetIds = @($manifest.wingetPackages | Where-Object { $_.required } | ForEach-Object { [string]$_.id })
$installedWinGetIds = @($snapshot.InstalledWinGetPackages | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Version) } | ForEach-Object { [string]$_.Id })
$missingRequiredWinGetIds = @($requiredWinGetIds | Where-Object { $_ -notin $installedWinGetIds })

$requiredModuleKeys = @($manifest.powerShellModules | Where-Object { $_.required } | ForEach-Object { "$($_.name)@$($_.version)" })
$installedModuleKeys = @($snapshot.InstalledPowerShellModules | ForEach-Object { "$($_.Name)@$($_.Version)" })
$missingRequiredModuleKeys = @($requiredModuleKeys | Where-Object { $_ -notin $installedModuleKeys })

$checks = @(
    (New-ToolchainCheck -Name 'FullWindows' -Passed ([bool]$snapshot.IsWindows -and -not [bool]$snapshot.IsWinPE) -Message 'Requires full Windows rather than WinPE.'),
    (New-ToolchainCheck -Name 'NetworkDefaultOffline' -Passed ([int]$snapshot.HardwareAdapterCount -gt 0 -and [int]$snapshot.ActiveHardwareAdapterCount -eq 0) -Message "Requires at least one hardware adapter and zero active hardware adapters; observed $($snapshot.HardwareAdapterCount) total and $($snapshot.ActiveHardwareAdapterCount) active."),
    (New-ToolchainCheck -Name 'OfflineStartupPolicy' -Passed ([bool]$snapshot.OfflineStartupTaskInstalled -and [bool]$snapshot.OfflineStartupPolicyPresent) -Message 'Requires the named startup task and its policy script.'),
    (New-ToolchainCheck -Name 'ProjectPayload' -Passed ([bool]$snapshot.ProjectPayloadPresent) -Message 'Requires both diagnostic modules, the dashboard XAML, and the guarded workspace launcher.'),
    (New-ToolchainCheck -Name 'RequiredWinGetPackages' -Passed ($missingRequiredWinGetIds.Count -eq 0) -Message "Missing required package count: $($missingRequiredWinGetIds.Count)."),
    (New-ToolchainCheck -Name 'RequiredPowerShellModules' -Passed ($missingRequiredModuleKeys.Count -eq 0) -Message "Missing exact required module count: $($missingRequiredModuleKeys.Count)."),
    (New-ToolchainCheck -Name 'CodexCliVersion' -Passed ([bool]$snapshot.CodexCommandAvailable -and [string]$snapshot.CodexVersion -ceq [string]$manifest.codexCli.version) -Message "Requires Codex CLI $($manifest.codexCli.version); observed $($snapshot.CodexVersion)."),
    (New-ToolchainCheck -Name 'CodexUnauthenticated' -Passed ([int]$snapshot.CodexAuthArtifactCount -eq 0 -and [int]$snapshot.CloudAuthArtifactCount -eq 0 -and [int]$snapshot.SensitiveEnvironmentVariableCount -eq 0) -Message 'Requires zero persisted Codex/Graph authentication artifacts and zero sensitive API/client-secret environment variables.'),
    (New-ToolchainCheck -Name 'InstallReceipt' -Passed ([bool]$snapshot.ReceiptPresent -and [string]$snapshot.ReceiptManifestAsOfDate -ceq [string]$manifest.asOfDate -and [bool]$snapshot.ReceiptCodexIntegrityVerified) -Message 'Requires a matching receipt that records successful Codex package-integrity verification.'),
    (New-ToolchainCheck -Name 'ReceiptPrivacy' -Passed (-not [bool]$snapshot.ReceiptContainsSensitiveMaterial) -Message 'The receipt must not contain access tokens, refresh tokens, client secrets, API keys, or recovery material.')
)

$allRequiredChecksPass = @($checks | Where-Object { $_.Status -ne 'Passed' }).Count -eq 0
$result = [pscustomobject][ordered]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    EvidenceSource = $evidenceSource
    LiveEvidence = $liveEvidence
    AllRequiredChecksPass = $allRequiredChecksPass
    ReadyForGeneralization = ($liveEvidence -and $allRequiredChecksPass)
    Checks = $checks
    ContainsIdentifiers = $false
    ContainsCredentials = $false
    NetworkRequestsMade = 0
    ChangesMade = 0
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
}
else {
    $result
}
