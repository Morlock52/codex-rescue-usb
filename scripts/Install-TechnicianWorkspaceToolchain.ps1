<#
.SYNOPSIS
  Plans or installs the allowlisted full-Windows technician toolchain.
.DESCRIPTION
  Reads config\technician-workspace-tools.json and returns a bounded plan by
  default. Apply mode is Windows-only and requires administrator rights, a
  passing live prerequisite audit, an exact confirmation phrase, explicit
  package-agreement approval, and ShouldProcess approval.

  Apply mode installs only exact allowlisted WinGet package IDs, exact
  PowerShell Gallery module versions, and the integrity-pinned Codex CLI npm
  package. It never signs in to Codex or Microsoft Graph and never stores a
  credential in the generalized image.
.PARAMETER ManifestPath
  Path to the checked-in technician-workspace tool manifest.
.PARAMETER Mode
  Plan is read-only and cross-platform. Apply performs the guarded Windows
  installations.
.PARAMETER ConfirmationToken
  Apply requires the exact phrase INSTALL CODEX RESCUE TOOLCHAIN.
.PARAMETER PackageAgreementsApproved
  Confirms that the operator has reviewed and approved the package and source
  agreements at action time. Required for Apply.
.PARAMETER ReceiptDirectory
  Directory that receives the non-secret build receipt after Apply.
.PARAMETER AsJson
  Emits the result as JSON.
.EXAMPLE
  .\Install-TechnicianWorkspaceToolchain.ps1 -Mode Plan -AsJson
.EXAMPLE
  .\Install-TechnicianWorkspaceToolchain.ps1 -Mode Apply `
    -ConfirmationToken 'INSTALL CODEX RESCUE TOOLCHAIN' `
    -PackageAgreementsApproved
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\technician-workspace-tools.json'),

    [Parameter()]
    [ValidateSet('Plan', 'Apply')]
    [string] $Mode = 'Plan',

    [Parameter()]
    [string] $ConfirmationToken,

    [Parameter()]
    [switch] $PackageAgreementsApproved,

    [Parameter()]
    [string] $ReceiptDirectory = 'C:\CodexRescueBuild\Toolchain',

    [Parameter()]
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        return $false
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ManifestContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Manifest
    )

    if ($Manifest.schemaVersion -ne 1) {
        throw "Unsupported technician tool manifest schema: $($Manifest.schemaVersion)"
    }
    if ($Manifest.policy.network -ne 'offline-default-explicit-maintenance-window') {
        throw 'The manifest does not require the approved offline-default network policy.'
    }
    if ($Manifest.policy.installOnlyFromAllowlist -ne $true -or
        $Manifest.policy.persistCredentialsInImage -ne $false -or
        $Manifest.policy.allowCloudWriteActions -ne $false -or
        $Manifest.policy.allowRecoveryKeyRetrieval -ne $false) {
        throw 'The manifest safety policy is not acceptable for provisioning.'
    }

    $wingetIds = @($Manifest.wingetPackages | ForEach-Object { [string]$_.id })
    if ($wingetIds.Count -eq 0 -or @($wingetIds | Select-Object -Unique).Count -ne $wingetIds.Count) {
        throw 'The WinGet allowlist must be non-empty and contain unique exact IDs.'
    }
    if (@($Manifest.wingetPackages | Where-Object { $_.versionPolicy -ne 'resolve-and-record' }).Count -ne 0) {
        throw 'Every WinGet package must use the resolve-and-record version policy.'
    }

    $moduleKeys = @($Manifest.powerShellModules | ForEach-Object { "$($_.name)@$($_.version)" })
    if ($moduleKeys.Count -eq 0 -or @($moduleKeys | Select-Object -Unique).Count -ne $moduleKeys.Count) {
        throw 'The PowerShell module allowlist must be non-empty and unique.'
    }
    if (@($Manifest.powerShellModules | Where-Object { -not $_.version -or $_.repository -ne 'PSGallery' }).Count -ne 0) {
        throw 'Every PowerShell module must have an exact version and the PSGallery repository.'
    }

    if ($Manifest.codexCli.provider -ne 'npm' -or
        $Manifest.codexCli.package -ne '@openai/codex' -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.codexCli.version) -or
        -not ([string]$Manifest.codexCli.integrity).StartsWith('sha512-') -or
        $Manifest.codexCli.persistAuthenticationInImage -ne $false) {
        throw 'The Codex CLI manifest entry is not pinned to the approved unauthenticated npm contract.'
    }
}

function Write-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Result,

        [Parameter(Mandatory)]
        [bool] $Json
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 8
    }
    else {
        $Result
    }
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
Assert-ManifestContract -Manifest $manifest

$planResult = [pscustomobject][ordered]@{
    SchemaVersion = 1
    Mode = 'Plan'
    ManifestSchemaVersion = [int]$manifest.schemaVersion
    ManifestAsOfDate = [string]$manifest.asOfDate
    ApplyAuthorized = $false
    RequiredConfirmationToken = 'INSTALL CODEX RESCUE TOOLCHAIN'
    PackageAgreementsApprovalRequired = $true
    WinGetPackageCount = @($manifest.wingetPackages).Count
    PowerShellModuleCount = @($manifest.powerShellModules).Count
    WinGetPackages = @($manifest.wingetPackages | ForEach-Object {
        [pscustomobject][ordered]@{
            Id = [string]$_.id
            Name = [string]$_.name
            Required = [bool]$_.required
            VersionPolicy = [string]$_.versionPolicy
        }
    })
    PowerShellModules = @($manifest.powerShellModules | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = [string]$_.name
            Version = [string]$_.version
            Repository = [string]$_.repository
            Required = [bool]$_.required
        }
    })
    CodexCli = [pscustomobject][ordered]@{
        Provider = [string]$manifest.codexCli.provider
        Package = [string]$manifest.codexCli.package
        Version = [string]$manifest.codexCli.version
        Integrity = [string]$manifest.codexCli.integrity
        Authentication = [string]$manifest.codexCli.authentication
    }
    PersistCredentialsInImage = $false
    CloudWritesAllowed = $false
    RecoveryMaterialRetrievalAllowed = $false
    ChangesMade = 0
    NetworkRequestsMade = 0
}

if ($Mode -eq 'Plan') {
    Write-Result -Result $planResult -Json ([bool]$AsJson)
    return
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Apply mode requires full Windows 11.'
}
if (-not (Test-Administrator)) {
    throw 'Apply mode requires an elevated Windows PowerShell session.'
}
if ($ConfirmationToken -cne 'INSTALL CODEX RESCUE TOOLCHAIN') {
    throw 'Apply refused: the exact confirmation token was not supplied.'
}
if (-not $PackageAgreementsApproved) {
    throw 'Apply refused: package and source agreements require operator approval at action time.'
}

$prerequisiteScript = Join-Path $PSScriptRoot 'Test-TechnicianWorkspacePrerequisite.ps1'
$prerequisite = & $prerequisiteScript
if (-not $prerequisite.LiveEvidence -or -not $prerequisite.ReadyForProvisioning) {
    throw 'Apply refused: the live Windows prerequisite audit is not ready for provisioning.'
}

$winget = Get-Command winget.exe -ErrorAction Stop
$changesMade = 0
$networkRequestsMade = 0
$wingetResults = @()
$moduleResults = @()
$codexResult = $null
$noApplicableUpgradeExitCode = -1978335189

foreach ($package in $manifest.wingetPackages) {
    $status = 'SkippedByWhatIf'
    $exitCode = $null
    if ($PSCmdlet.ShouldProcess([string]$package.id, "Install the exact allowlisted WinGet package $($package.name)")) {
        $networkRequestsMade++
        & $winget.Source install --id ([string]$package.id) --exact --silent --disable-interactivity --scope machine --accept-package-agreements --accept-source-agreements | Out-Host
        $exitCode = $LASTEXITCODE
        $status = if ($exitCode -eq 0) {
            $changesMade++
            'InstalledOrCurrent'
        }
        elseif ($exitCode -eq $noApplicableUpgradeExitCode) {
            'AlreadyCurrent'
        }
        else {
            throw "WinGet failed for exact package ID $($package.id) with exit code $exitCode."
        }
    }

    $wingetResults += [pscustomobject][ordered]@{
        Id = [string]$package.id
        Status = $status
        ExitCode = $exitCode
    }
}

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"

$npm = Get-Command npm.cmd -ErrorAction Stop
$codexPackageSpec = "$($manifest.codexCli.package)@$($manifest.codexCli.version)"
if ($PSCmdlet.ShouldProcess($codexPackageSpec, 'Verify integrity and install the exact allowlisted Codex CLI package')) {
    $networkRequestsMade++
    $npmIntegrityJson = (& $npm.Source view $codexPackageSpec 'dist.integrity' --json 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "npm could not resolve integrity for $codexPackageSpec."
    }
    $npmIntegrity = $npmIntegrityJson | ConvertFrom-Json
    if ([string]$npmIntegrity -cne [string]$manifest.codexCli.integrity) {
        throw "npm integrity mismatch for $codexPackageSpec."
    }

    $networkRequestsMade++
    & $npm.Source install --global $codexPackageSpec | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "npm failed to install $codexPackageSpec."
    }
    $changesMade++
    $codexCommand = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($null -eq $codexCommand) {
        $codexCommand = Get-Command codex -ErrorAction Stop
    }
    $codexVersion = (& $codexCommand.Source --version 2>&1 | Out-String).Trim()
    $codexResult = [pscustomobject][ordered]@{
        Package = [string]$manifest.codexCli.package
        RequestedVersion = [string]$manifest.codexCli.version
        IntegrityVerified = $true
        CommandAvailable = $true
        ReportedVersion = $codexVersion
        Authenticated = $false
    }
}
else {
    $codexResult = [pscustomobject][ordered]@{
        Package = [string]$manifest.codexCli.package
        RequestedVersion = [string]$manifest.codexCli.version
        IntegrityVerified = $false
        CommandAvailable = $false
        ReportedVersion = $null
        Authenticated = $false
    }
}

foreach ($module in $manifest.powerShellModules) {
    $moduleSpec = "$($module.name)@$($module.version)"
    $status = 'SkippedByWhatIf'
    if ($PSCmdlet.ShouldProcess($moduleSpec, 'Install the exact allowlisted PowerShell Gallery module')) {
        $networkRequestsMade++
        Install-Module -Name ([string]$module.name) -RequiredVersion ([string]$module.version) -Repository ([string]$module.repository) -Scope AllUsers -Force -AllowClobber -AcceptLicense -ErrorAction Stop
        $installedModule = Get-Module -ListAvailable -Name ([string]$module.name) |
            Where-Object { $_.Version.ToString() -eq [string]$module.version } |
            Select-Object -First 1
        if ($null -eq $installedModule) {
            throw "PowerShell module verification failed for $moduleSpec."
        }
        $changesMade++
        $status = 'InstalledAndVerified'
    }

    $moduleResults += [pscustomobject][ordered]@{
        Name = [string]$module.name
        Version = [string]$module.version
        Status = $status
    }
}

$applyResult = [pscustomobject][ordered]@{
    SchemaVersion = 1
    Mode = 'Apply'
    CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    ManifestAsOfDate = [string]$manifest.asOfDate
    ApplyAuthorized = $true
    PrerequisiteLiveEvidence = [bool]$prerequisite.LiveEvidence
    PrerequisiteReady = [bool]$prerequisite.ReadyForProvisioning
    WinGetPackages = $wingetResults
    PowerShellModules = $moduleResults
    CodexCli = $codexResult
    PersistCredentialsInImage = $false
    CloudWritesAllowed = $false
    RecoveryMaterialRetrievalAllowed = $false
    ChangesMade = $changesMade
    NetworkRequestsMade = $networkRequestsMade
}

if ($PSCmdlet.ShouldProcess($ReceiptDirectory, 'Write the non-secret technician toolchain build receipt')) {
    if (-not (Test-Path -LiteralPath $ReceiptDirectory)) {
        New-Item -ItemType Directory -Path $ReceiptDirectory | Out-Null
    }
    $receiptName = 'technician-toolchain-{0}.json' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
    $receiptPath = Join-Path $ReceiptDirectory $receiptName
    if (Test-Path -LiteralPath $receiptPath) {
        throw "Refusing to overwrite existing receipt: $receiptPath"
    }
    $applyResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}

Write-Result -Result $applyResult -Json ([bool]$AsJson)
