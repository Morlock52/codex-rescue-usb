<#
.SYNOPSIS
  Audits or installs the QEMU Guest Agent from attached VirtIO media.
.DESCRIPTION
  Audit is the default and makes no change or network request. It locates
  exactly one 64-bit QEMU Guest Agent MSI on an explicitly selected media root
  or attached CD-ROM, verifies its Windows Authenticode signature and Red Hat
  signer subject, and reports the QEMU-GA service state.

  Apply is full-Windows-only and requires elevation, the exact confirmation
  phrase, a passing live installer audit, and ShouldProcess approval. It uses
  msiexec without restart, writes a private local installation log, and verifies
  that QEMU-GA is installed, running, and automatic. It never downloads media.
.PARAMETER Mode
  Audit is read-only. Apply installs the verified MSI.
.PARAMETER MediaRoot
  Optional exact root of the mounted VirtIO ISO. Without it, live Audit searches
  attached CD-ROM volumes only.
.PARAMETER ConfirmationToken
  Apply requires the exact phrase INSTALL QEMU GUEST AGENT.
.PARAMETER LogDirectory
  Private local directory for the MSI log created during Apply.
.PARAMETER ContractFixturePath
  Optional deterministic Audit fixture. Fixtures never authorize Apply or count
  as live installation readiness.
.PARAMETER AsJson
  Emits the bounded result as JSON.
.EXAMPLE
  .\Install-TechnicianWorkspaceGuestAgent.ps1 -Mode Audit -AsJson
.EXAMPLE
  .\Install-TechnicianWorkspaceGuestAgent.ps1 -Mode Apply `
    -MediaRoot E:\ `
    -ConfirmationToken 'INSTALL QEMU GUEST AGENT'
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('Audit', 'Apply')]
    [string] $Mode = 'Audit',

    [Parameter()]
    [string] $MediaRoot,

    [Parameter()]
    [string] $ConfirmationToken,

    [Parameter()]
    [string] $LogDirectory = 'C:\CodexRescueBuild\GuestAgent',

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ContractFixturePath,

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

function New-GuestAgentCheck {
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

function Find-QemuGuestAgentInstaller {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ExactMediaRoot
    )

    $searchRoots = @()
    if (-not [string]::IsNullOrWhiteSpace($ExactMediaRoot)) {
        $searchRoots = @((Resolve-Path -LiteralPath $ExactMediaRoot -ErrorAction Stop).Path)
    }
    else {
        $searchRoots = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=5' -ErrorAction Stop |
            ForEach-Object { [string]$_.DeviceID + '\' })
    }

    $candidates = @()
    foreach ($root in $searchRoots) {
        $preferredPath = Join-Path $root 'guest-agent\qemu-ga-x86_64.msi'
        if (Test-Path -LiteralPath $preferredPath -PathType Leaf) {
            $candidates += Get-Item -LiteralPath $preferredPath -ErrorAction Stop
            continue
        }
        $candidates += @(Get-ChildItem -LiteralPath $root -Filter 'qemu-ga-x86_64.msi' -File -Recurse -ErrorAction SilentlyContinue)
    }

    @($candidates | Sort-Object FullName -Unique)
}

function Get-GuestAgentServiceSnapshot {
    [CmdletBinding()]
    param()

    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='QEMU-GA'" -ErrorAction SilentlyContinue
    [pscustomobject][ordered]@{
        ServiceInstalled = ($null -ne $service)
        ServiceRunning = ($null -ne $service -and $service.State -eq 'Running')
        ServiceStartMode = if ($null -ne $service) { [string]$service.StartMode } else { 'Unavailable' }
    }
}

function Get-LiveGuestAgentSnapshot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ExactMediaRoot
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Live QEMU Guest Agent collection requires full Windows 11.'
    }

    $candidates = @(Find-QemuGuestAgentInstaller -ExactMediaRoot $ExactMediaRoot)
    $signatureStatus = 'Unavailable'
    $signerSubject = ''
    $installerFileName = ''
    if ($candidates.Count -eq 1) {
        $installerFileName = $candidates[0].Name
        $signature = Get-AuthenticodeSignature -LiteralPath $candidates[0].FullName
        $signatureStatus = [string]$signature.Status
        if ($null -ne $signature.SignerCertificate) {
            $signerSubject = [string]$signature.SignerCertificate.Subject
        }
    }

    $service = Get-GuestAgentServiceSnapshot
    [pscustomobject][ordered]@{
        IsWindows = $true
        IsWinPE = (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')
        IsAdministrator = (Test-Administrator)
        InstallerCandidateCount = $candidates.Count
        InstallerFileName = $installerFileName
        InstallerSignatureStatus = $signatureStatus
        InstallerSignerSubject = $signerSubject
        ServiceInstalled = $service.ServiceInstalled
        ServiceRunning = $service.ServiceRunning
        ServiceStartMode = $service.ServiceStartMode
    }
}

function Write-GuestAgentResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Result,

        [Parameter(Mandatory)]
        [bool] $Json
    )

    if ($Json) {
        $Result | ConvertTo-Json -Depth 6
    }
    else {
        $Result
    }
}

$allowedSnapshotProperties = @(
    'IsWindows',
    'IsWinPE',
    'IsAdministrator',
    'InstallerCandidateCount',
    'InstallerFileName',
    'InstallerSignatureStatus',
    'InstallerSignerSubject',
    'ServiceInstalled',
    'ServiceRunning',
    'ServiceStartMode'
)

$liveEvidence = -not $PSBoundParameters.ContainsKey('ContractFixturePath')
if ($liveEvidence) {
    $snapshot = Get-LiveGuestAgentSnapshot -ExactMediaRoot $MediaRoot
    $evidenceSource = 'LiveWindows'
}
else {
    if ($Mode -ne 'Audit') {
        throw 'Contract fixtures are audit-only and cannot authorize installation.'
    }
    $snapshot = Get-Content -LiteralPath $ContractFixturePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $propertyNames = @($snapshot.PSObject.Properties.Name)
    $missingProperties = @($allowedSnapshotProperties | Where-Object { $_ -notin $propertyNames })
    $unexpectedProperties = @($propertyNames | Where-Object { $_ -notin $allowedSnapshotProperties })
    if ($missingProperties.Count -gt 0 -or $unexpectedProperties.Count -gt 0) {
        throw "Contract fixture properties do not match the allowlist. Missing=$($missingProperties -join ','); Unexpected=$($unexpectedProperties -join ',')"
    }
    $evidenceSource = 'ContractFixture'
}

$redHatSignerPattern = '^(?:CN|O)="?Red Hat, Inc\."?(?:,|$)'
$checks = @(
    (New-GuestAgentCheck -Name 'FullWindows' -Passed ([bool]$snapshot.IsWindows -and -not [bool]$snapshot.IsWinPE) -Message 'Requires full Windows rather than WinPE.'),
    (New-GuestAgentCheck -Name 'ElevatedOperator' -Passed ([bool]$snapshot.IsAdministrator) -Message 'Installation requires an elevated operator session.'),
    (New-GuestAgentCheck -Name 'ExactInstallerCandidate' -Passed ([int]$snapshot.InstallerCandidateCount -eq 1 -and [string]$snapshot.InstallerFileName -ceq 'qemu-ga-x86_64.msi') -Message "Requires exactly one qemu-ga-x86_64.msi candidate; observed $($snapshot.InstallerCandidateCount)."),
    (New-GuestAgentCheck -Name 'TrustedInstallerSignature' -Passed ([string]$snapshot.InstallerSignatureStatus -ceq 'Valid' -and [string]$snapshot.InstallerSignerSubject -match $redHatSignerPattern) -Message 'Requires a Valid Windows Authenticode signature with the exact Red Hat, Inc. signer subject prefix.')
)

$installerContractPasses = @($checks | Where-Object { $_.Status -ne 'Passed' }).Count -eq 0
$guestAgentHealthy = [bool]$snapshot.ServiceInstalled -and
    [bool]$snapshot.ServiceRunning -and
    [string]$snapshot.ServiceStartMode -in @('Auto', 'Automatic')

$auditResult = [pscustomobject][ordered]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    Mode = 'Audit'
    EvidenceSource = $evidenceSource
    LiveEvidence = $liveEvidence
    InstallerContractPasses = $installerContractPasses
    GuestAgentHealthy = $guestAgentHealthy
    ReadyForInstall = ($liveEvidence -and $installerContractPasses -and -not $guestAgentHealthy)
    Checks = $checks
    ServiceInstalled = [bool]$snapshot.ServiceInstalled
    ServiceRunning = [bool]$snapshot.ServiceRunning
    ServiceStartMode = [string]$snapshot.ServiceStartMode
    ContainsIdentifiers = $false
    ContainsCredentials = $false
    NetworkRequestsMade = 0
    ChangesMade = 0
}

if ($Mode -eq 'Audit') {
    Write-GuestAgentResult -Result $auditResult -Json ([bool]$AsJson)
    return
}

if (-not $liveEvidence) {
    throw 'Apply requires live Windows evidence.'
}
if (-not $installerContractPasses) {
    throw 'Apply refused: the live installer contract did not pass.'
}
if ($guestAgentHealthy) {
    throw 'Apply refused: QEMU-GA is already installed, running, and automatic.'
}
if ($ConfirmationToken -cne 'INSTALL QEMU GUEST AGENT') {
    throw 'Apply refused: the exact confirmation phrase was not supplied.'
}

$installerCandidates = @(Find-QemuGuestAgentInstaller -ExactMediaRoot $MediaRoot)
if ($installerCandidates.Count -ne 1) {
    throw "Installer selection changed after audit; found $($installerCandidates.Count) candidates."
}
$installerPath = $installerCandidates[0].FullName
$signature = Get-AuthenticodeSignature -LiteralPath $installerPath
if ([string]$signature.Status -cne 'Valid' -or
    $null -eq $signature.SignerCertificate -or
    [string]$signature.SignerCertificate.Subject -notmatch $redHatSignerPattern) {
    throw 'Installer signature changed after audit. Nothing was installed.'
}

$changesMade = 0
$restartRequired = $false
$logPath = $null
if ($PSCmdlet.ShouldProcess($installerPath, 'Install the verified QEMU Guest Agent without restarting Windows')) {
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $LogDirectory | Out-Null
    }
    $logName = 'qemu-guest-agent-{0}.log' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
    $logPath = Join-Path $LogDirectory $logName
    if (Test-Path -LiteralPath $logPath) {
        throw "Refusing to overwrite existing MSI log: $logPath"
    }

    $msiexec = Get-Command msiexec.exe -ErrorAction Stop
    $arguments = @('/i', "`"$installerPath`"", '/qn', '/norestart', '/l*v', "`"$logPath`"")
    $process = Start-Process -FilePath $msiexec.Source -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "QEMU Guest Agent MSI failed with exit code $($process.ExitCode). Review the private MSI log."
    }
    $restartRequired = $process.ExitCode -eq 3010
    $changesMade++

    $serviceAfterInstall = Get-CimInstance -ClassName Win32_Service -Filter "Name='QEMU-GA'" -ErrorAction Stop
    if ($serviceAfterInstall.StartMode -notin @('Auto', 'Automatic')) {
        Set-Service -Name 'QEMU-GA' -StartupType Automatic -ErrorAction Stop
        $changesMade++
    }
    if ($serviceAfterInstall.State -ne 'Running') {
        Start-Service -Name 'QEMU-GA' -ErrorAction Stop
        $changesMade++
    }
}

$finalService = Get-GuestAgentServiceSnapshot
$finalHealthy = [bool]$finalService.ServiceInstalled -and
    [bool]$finalService.ServiceRunning -and
    [string]$finalService.ServiceStartMode -in @('Auto', 'Automatic')
if (-not $WhatIfPreference -and -not $finalHealthy) {
    throw 'QEMU-GA did not reach installed, running, and automatic state.'
}

$applyResult = [pscustomobject][ordered]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    Mode = 'Apply'
    EvidenceSource = 'LiveWindows'
    LiveEvidence = $true
    InstallerContractPasses = $installerContractPasses
    GuestAgentHealthy = $finalHealthy
    RestartRequired = $restartRequired
    ServiceInstalled = [bool]$finalService.ServiceInstalled
    ServiceRunning = [bool]$finalService.ServiceRunning
    ServiceStartMode = [string]$finalService.ServiceStartMode
    PrivateLogCreated = (-not [string]::IsNullOrWhiteSpace($logPath))
    ContainsIdentifiers = $false
    ContainsCredentials = $false
    NetworkRequestsMade = 0
    ChangesMade = $changesMade
}

Write-GuestAgentResult -Result $applyResult -Json ([bool]$AsJson)
