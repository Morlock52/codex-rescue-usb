<#
.SYNOPSIS
  Audits whether a clean Windows VM meets the technician-workspace provisioning baseline.
.DESCRIPTION
  Performs eleven read-only checks for full Windows 11, 64-bit architecture,
  Windows PowerShell 5.1, memory, free system-drive space, UEFI, Secure Boot,
  TPM 2.0, an offline hardware-network state, and QEMU Guest Agent recovery.

  The script does not install software, enable networking, change services, or
  write an evidence file. Contract fixtures never count as live readiness evidence.
.PARAMETER ContractFixturePath
  Optional JSON contract fixture for deterministic cross-platform tests. A
  passing fixture can prove the evaluator contract only. It cannot set
  ReadyForProvisioning to true.
.PARAMETER MinimumMemoryGB
  Required physical memory in GiB. The project build baseline is 12 GiB.
.PARAMETER MinimumSystemDriveFreeGB
  Required free space on the Windows system drive in GiB. Default is 64 GiB.
.PARAMETER AsJson
  Emits the bounded result as JSON rather than as a PowerShell object.
.EXAMPLE
  .\Test-TechnicianWorkspacePrerequisite.ps1
.EXAMPLE
  .\Test-TechnicianWorkspacePrerequisite.ps1 -AsJson
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ContractFixturePath,

    [Parameter()]
    [ValidateRange(8, 128)]
    [int] $MinimumMemoryGB = 12,

    [Parameter()]
    [ValidateRange(32, 2048)]
    [int] $MinimumSystemDriveFreeGB = 64,

    [Parameter()]
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PrerequisiteCheck {
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

function Get-LivePrerequisiteSnapshot {
    [CmdletBinding()]
    param()

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Live prerequisite collection requires full Windows 11.'
    }

    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $systemDrive = $operatingSystem.SystemDrive
    $escapedSystemDrive = $systemDrive.Replace("'", "''")
    $logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$escapedSystemDrive'" -ErrorAction Stop

    $firmwareValue = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction SilentlyContinue
    $firmwareType = switch ($firmwareValue) {
        2 { 'UEFI' }
        1 { 'BIOS' }
        default { 'Unknown' }
    }

    $secureBootEnabled = $false
    try {
        $secureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
    }
    catch {
        $secureBootEnabled = $false
    }

    $tpm = Get-Tpm -ErrorAction SilentlyContinue
    $tpmCim = Get-CimInstance -Namespace 'root\CIMV2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    $tpmVersion = if ($null -ne $tpmCim -and $tpmCim.SpecVersion) {
        ([string]$tpmCim.SpecVersion -split ',')[0].Trim()
    }
    else {
        'Unavailable'
    }

    $hardwareAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.HardwareInterface })
    $activeHardwareAdapters = @($hardwareAdapters | Where-Object { $_.Status -eq 'Up' })

    $guestAgent = Get-CimInstance -ClassName Win32_Service -Filter "Name='QEMU-GA'" -ErrorAction SilentlyContinue
    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $buildNumber = [int]$operatingSystem.BuildNumber

    [pscustomobject][ordered]@{
        IsWindows = $true
        IsWindows11 = ($buildNumber -ge 22000)
        IsWinPE = (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')
        Is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
        WindowsPowerShell51Available = (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)
        TotalMemoryGB = [math]::Round(([double]$computerSystem.TotalPhysicalMemory / 1GB), 2)
        SystemDriveFreeGB = [math]::Round(([double]$logicalDisk.FreeSpace / 1GB), 2)
        FirmwareType = $firmwareType
        SecureBootEnabled = $secureBootEnabled
        TpmPresent = ($null -ne $tpm -and [bool]$tpm.TpmPresent)
        TpmReady = ($null -ne $tpm -and [bool]$tpm.TpmReady)
        TpmVersion = $tpmVersion
        HardwareAdapterCount = $hardwareAdapters.Count
        ActiveHardwareAdapterCount = $activeHardwareAdapters.Count
        GuestAgentInstalled = ($null -ne $guestAgent)
        GuestAgentRunning = ($null -ne $guestAgent -and $guestAgent.State -eq 'Running')
        GuestAgentStartMode = if ($null -ne $guestAgent) { [string]$guestAgent.StartMode } else { 'Unavailable' }
    }
}

$allowedSnapshotProperties = @(
    'IsWindows',
    'IsWindows11',
    'IsWinPE',
    'Is64BitOperatingSystem',
    'WindowsPowerShell51Available',
    'TotalMemoryGB',
    'SystemDriveFreeGB',
    'FirmwareType',
    'SecureBootEnabled',
    'TpmPresent',
    'TpmReady',
    'TpmVersion',
    'HardwareAdapterCount',
    'ActiveHardwareAdapterCount',
    'GuestAgentInstalled',
    'GuestAgentRunning',
    'GuestAgentStartMode'
)

$liveEvidence = -not $PSBoundParameters.ContainsKey('ContractFixturePath')
if ($liveEvidence) {
    $snapshot = Get-LivePrerequisiteSnapshot
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

$checks = @(
    (New-PrerequisiteCheck -Name 'FullWindows' -Passed ([bool]$snapshot.IsWindows -and -not [bool]$snapshot.IsWinPE) -Message 'Requires full Windows rather than WinPE.'),
    (New-PrerequisiteCheck -Name 'Windows11' -Passed ([bool]$snapshot.IsWindows11) -Message 'Requires Windows 11 build 22000 or later.'),
    (New-PrerequisiteCheck -Name 'Architecture64Bit' -Passed ([bool]$snapshot.Is64BitOperatingSystem) -Message 'Requires a 64-bit operating system.'),
    (New-PrerequisiteCheck -Name 'WindowsPowerShell51' -Passed ([bool]$snapshot.WindowsPowerShell51Available) -Message 'Requires Windows PowerShell 5.1 availability.'),
    (New-PrerequisiteCheck -Name 'Memory' -Passed ([double]$snapshot.TotalMemoryGB -ge $MinimumMemoryGB) -Message "Requires at least $MinimumMemoryGB GiB; observed $($snapshot.TotalMemoryGB) GiB."),
    (New-PrerequisiteCheck -Name 'SystemDriveFreeSpace' -Passed ([double]$snapshot.SystemDriveFreeGB -ge $MinimumSystemDriveFreeGB) -Message "Requires at least $MinimumSystemDriveFreeGB GiB free; observed $($snapshot.SystemDriveFreeGB) GiB."),
    (New-PrerequisiteCheck -Name 'UefiFirmware' -Passed ([string]$snapshot.FirmwareType -eq 'UEFI') -Message "Requires UEFI firmware; observed $($snapshot.FirmwareType)."),
    (New-PrerequisiteCheck -Name 'SecureBoot' -Passed ([bool]$snapshot.SecureBootEnabled) -Message 'Requires Secure Boot enabled.'),
    (New-PrerequisiteCheck -Name 'Tpm20' -Passed ([bool]$snapshot.TpmPresent -and [bool]$snapshot.TpmReady -and [string]$snapshot.TpmVersion -like '2.*') -Message 'Requires a present, ready TPM 2.0.'),
    (New-PrerequisiteCheck -Name 'NetworkDefaultOffline' -Passed ([int]$snapshot.HardwareAdapterCount -gt 0 -and [int]$snapshot.ActiveHardwareAdapterCount -eq 0) -Message "Requires at least one hardware adapter and zero active hardware adapters; observed $($snapshot.HardwareAdapterCount) total and $($snapshot.ActiveHardwareAdapterCount) active."),
    (New-PrerequisiteCheck -Name 'GuestAgent' -Passed ([bool]$snapshot.GuestAgentInstalled -and [bool]$snapshot.GuestAgentRunning -and [string]$snapshot.GuestAgentStartMode -in @('Auto', 'Automatic')) -Message 'Requires QEMU Guest Agent installed, running, and automatic.')
)

$allRequiredChecksPass = @($checks | Where-Object { $_.Status -ne 'Passed' }).Count -eq 0
$result = [pscustomobject][ordered]@{
    SchemaVersion = 1
    CheckedAtUtc = [DateTime]::UtcNow.ToString('o')
    EvidenceSource = $evidenceSource
    LiveEvidence = $liveEvidence
    AllRequiredChecksPass = $allRequiredChecksPass
    ReadyForProvisioning = ($liveEvidence -and $allRequiredChecksPass)
    MinimumMemoryGB = $MinimumMemoryGB
    MinimumSystemDriveFreeGB = $MinimumSystemDriveFreeGB
    Checks = $checks
    ContainsIdentifiers = $false
    ContainsCredentials = $false
    NetworkRequestsMade = 0
    ChangesMade = 0
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
}
else {
    $result
}
