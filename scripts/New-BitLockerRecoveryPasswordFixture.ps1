<#
.SYNOPSIS
Creates one disposable BitLocker recovery-password test volume.

.DESCRIPTION
Destructively initializes one explicitly selected new 1 GiB RAW virtual disk,
opens Microsoft's manage-bde tool in a separate local console so the operator
can transcribe the generated recovery password without returning it to this
PowerShell process, waits for encryption, and locks the volume. The audit file
contains only non-secret fixture state.

Run this command only from the local interactive console of the disposable
Windows build VM. Do not run this command through Codex, a guest agent, a
transcript, redirected input/output, or a recorded screen.

.PARAMETER DataDiskNumber
Disk number of the new 1 GiB RAW virtual data disk.

.PARAMETER ConfirmationToken
Must exactly match CREATE DISPOSABLE RECOVERY PASSWORD FIXTURE <disk>.

.EXAMPLE
.\scripts\New-BitLockerRecoveryPasswordFixture.ps1 `
  -DataDiskNumber 1 `
  -ConfirmationToken 'CREATE DISPOSABLE RECOVERY PASSWORD FIXTURE 1' `
  -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, 128)]
    [int]$DataDiskNumber,

    [Parameter(Mandatory)]
    [string]$ConfirmationToken,

    [string]$OutputDirectory = 'C:\CodexRescueVmAudit\RecoveryPasswordFixture'
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') {
    throw 'The disposable recovery-password fixture requires full Windows.'
}
if (!(Test-Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    throw 'Use the local interactive console. Do not run this command through Codex, a guest agent, or redirected input/output.'
}

$requiredToken = "CREATE DISPOSABLE RECOVERY PASSWORD FIXTURE $DataDiskNumber"
if ($ConfirmationToken -cne $requiredToken) {
    throw "Confirmation token mismatch. Required: $requiredToken"
}

$dataDisk = Get-Disk -Number $DataDiskNumber -ErrorAction Stop
if ($dataDisk.IsBoot -or $dataDisk.IsSystem) {
    throw "Refusing boot or system disk $($dataDisk.Number)."
}
if ($dataDisk.PartitionStyle -ne 'RAW') {
    throw "Disk $DataDiskNumber is not RAW. No existing disk may be reused."
}
$gib = 1GB
if ($dataDisk.Size -lt (0.9 * $gib) -or $dataDisk.Size -gt (1.1 * $gib)) {
    throw "Disk $DataDiskNumber is not the expected disposable 1 GiB disk."
}

$targetDescription = "RAW 1 GiB data disk $DataDiskNumber"
if (!$PSCmdlet.ShouldProcess(
        $targetDescription,
        'Initialize, format, encrypt, and lock a disposable recovery-password fixture'
    )) {
    return
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$bitLockerPolicyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'
if (!(Test-Path $bitLockerPolicyPath)) {
    New-Item -Path $bitLockerPolicyPath | Out-Null
}
New-ItemProperty -Path $bitLockerPolicyPath -Name 'PreventDeviceEncryption' `
    -PropertyType DWord -Value 1 -Force | Out-Null

$dataPartition = Initialize-Disk -Number $DataDiskNumber -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -AssignDriveLetter
$dataVolume = $dataPartition |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'CODEX-BL-PASS' -Confirm:$false
$dataMount = "$($dataVolume.DriveLetter):"
$dataRoot = "$dataMount\"

'Codex Rescue disposable recovery-password fixture. No customer data.' |
    Set-Content -Encoding ASCII -LiteralPath (Join-Path $dataRoot 'RECOVERY-PASSWORD-TEST.txt')

$dataBitLocker = Get-BitLockerVolume -MountPoint $dataMount
if ($dataBitLocker.VolumeStatus -ne 'FullyDecrypted') {
    throw 'Windows began automatic device encryption. The disposable volume must be fully decrypted before the explicit protector is created.'
}

$commandPath = Join-Path ([IO.Path]::GetTempPath()) (
    'CodexRescue-RecoveryPassword-{0}.cmd' -f [guid]::NewGuid()
)
$commandContent = @"
@echo off
echo DISPOSABLE FIXTURE ONLY - DO NOT RECORD OR PASTE THIS PASSWORD INTO CODEX.
echo Write the generated 48-digit recovery password down for the local WinPE test.
echo.
"%SystemRoot%\System32\manage-bde.exe" -on $dataMount -RecoveryPassword -EncryptionMethod xts_aes128 -UsedSpaceOnly -SkipHardwareTest
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Fixture encryption failed. Do not continue to WinPE.
if "%RESULT%"=="0" echo Password display complete. Keep it local and press any key to close this window.
pause >nul
exit /b %RESULT%
"@
$commandContent | Set-Content -LiteralPath $commandPath -Encoding ASCII

try {
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList @(
        '/d', '/c', ('"{0}"' -f $commandPath)
    ) -Wait -PassThru
}
finally {
    Remove-Item -LiteralPath $commandPath -Force -ErrorAction SilentlyContinue
}
if ($process.ExitCode -ne 0) {
    throw "BitLocker fixture creation failed with exit code $($process.ExitCode)."
}

$deadline = (Get-Date).AddMinutes(3)
do {
    Start-Sleep -Seconds 2
    $bitLocker = Get-BitLockerVolume -MountPoint $dataMount
} until ($bitLocker.VolumeStatus -eq 'FullyEncrypted' -or (Get-Date) -ge $deadline)
if ($bitLocker.VolumeStatus -ne 'FullyEncrypted') {
    throw "BitLocker encryption did not complete before $deadline."
}

$recoveryPasswordProtectors = @(
    $bitLocker.KeyProtector |
        Where-Object KeyProtectorType -eq 'RecoveryPassword'
)
if ($recoveryPasswordProtectors.Count -ne 1) {
    throw 'Expected exactly one recovery-password protector on the disposable volume.'
}
$fixtureFileSha256 = (
    Get-FileHash -LiteralPath (Join-Path $dataRoot 'RECOVERY-PASSWORD-TEST.txt') `
        -Algorithm SHA256
).Hash

& manage-bde.exe -lock $dataMount -ForceDismount | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "BitLocker lock failed with exit code $LASTEXITCODE."
}
$bitLocker = Get-BitLockerVolume -MountPoint $dataMount
if ($bitLocker.LockStatus -ne 'Locked') {
    throw 'The disposable recovery-password volume did not reach the locked state.'
}

$result = [ordered]@{
    SchemaVersion = 1
    CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    DataDiskNumber = $DataDiskNumber
    DataDiskSize = $dataDisk.Size
    DataVolumeLabel = $dataVolume.FileSystemLabel
    RecoveryPasswordProtectorCount = $recoveryPasswordProtectors.Count
    EncryptionState = $bitLocker.VolumeStatus.ToString()
    LockState = $bitLocker.LockStatus.ToString()
    FixtureFileSha256 = $fixtureFileSha256
    ContainsRecoveryMaterial = $false
}
$result | ConvertTo-Json -Depth 4 |
    Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'fixture-result.json')
$result
