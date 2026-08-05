<#
.SYNOPSIS
Unlocks one authorized BitLocker data volume with masked recovery-password input.

.DESCRIPTION
Requires an exact target drive and confirmation token, prompts locally for a
48-digit BitLocker recovery password as a SecureString, validates the password
through the MicrosoftVolumeEncryption WMI provider, and unlocks only the
selected locked volume. The password is never accepted as a command-line
parameter, written to output, copied to the clipboard, or included in evidence.

.PARAMETER TargetDrive
One authorized data-volume letter. C and the WinPE X RAM drive are blocked.

.PARAMETER ConfirmationToken
Must exactly match UNLOCK <drive>: for the selected target.

.EXAMPLE
X:\Rescue\Unlock-BitLockerWithRecoveryPassword.ps1 `
  -TargetDrive E `
  -ConfirmationToken 'UNLOCK E:' `
  -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[D-WY-Zd-wy-z]$')]
    [string]$TargetDrive,

    [Parameter(Mandatory)]
    [string]$ConfirmationToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$namespace = 'Root\CIMV2\Security\MicrosoftVolumeEncryption'
$target = $TargetDrive.ToUpperInvariant()
$targetMount = "$target`:"
$requiredConfirmation = "UNLOCK $target`:"

if ($ConfirmationToken -cne $requiredConfirmation) {
    throw "Confirmation token mismatch. Required: $requiredConfirmation"
}

$volumes = @(
    Get-WmiObject -Namespace $namespace -Class Win32_EncryptableVolume `
        -Filter "DriveLetter='$targetMount'" -ErrorAction Stop
)
if ($volumes.Count -ne 1) {
    throw "Expected exactly one BitLocker volume at $targetMount. Nothing was unlocked."
}
$volume = $volumes[0]
$before = $volume.GetLockStatus()
if ([uint32]$before.ReturnValue -ne 0) {
    throw ('Unable to read the selected BitLocker lock state. WMI code: 0x{0:X8}' -f [uint32]$before.ReturnValue)
}
if ([uint32]$before.LockStatus -ne 1) {
    throw "The selected volume is not locked. Nothing was changed."
}

if (!$PSCmdlet.ShouldProcess($targetMount, 'Unlock the selected BitLocker volume with a locally entered recovery password')) {
    return
}

Write-Host "Target volume: $targetMount"
Write-Host 'Type the 48-digit recovery password locally. Do not paste it, save it, or give it to Codex.'
Write-Host 'Input is masked. Only the selected volume receives the password.'

$securePassword = $null
$plainTextPassword = $null
$passwordBstr = [IntPtr]::Zero
$unlockReturn = $null
try {
    $securePassword = Read-Host 'Recovery password' -AsSecureString
    if ($securePassword.Length -eq 0) {
        throw 'No recovery password was entered. Nothing was unlocked.'
    }

    $passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainTextPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)

    $format = Invoke-WmiMethod -Namespace $namespace -Class Win32_EncryptableVolume `
        -Name IsNumericalPasswordValid -ArgumentList $plainTextPassword -ErrorAction Stop
    if ([uint32]$format.ReturnValue -ne 0 -or !$format.IsNumericalPasswordValid) {
        throw 'The recovery password format is invalid. Nothing was unlocked.'
    }

    $unlock = $volume.UnlockWithNumericalPassword($plainTextPassword)
    $unlockReturn = [uint32]$unlock.ReturnValue
}
finally {
    $plainTextPassword = $null
    if ($passwordBstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
        $passwordBstr = [IntPtr]::Zero
    }
    if ($null -ne $securePassword) {
        $securePassword.Dispose()
        $securePassword = $null
    }
}

if ($unlockReturn -ne 0) {
    throw ('BitLocker rejected the recovery password or selected volume. WMI code: 0x{0:X8}' -f $unlockReturn)
}

$volume = Get-WmiObject -Namespace $namespace -Class Win32_EncryptableVolume `
    -Filter "DriveLetter='$targetMount'" -ErrorAction Stop
$after = $volume.GetLockStatus()
if ([uint32]$after.ReturnValue -ne 0 -or [uint32]$after.LockStatus -ne 0) {
    throw 'The unlock call returned success, but the selected volume is still locked.'
}
if (!(Test-Path -LiteralPath "$targetMount\")) {
    throw 'The unlock call returned success, but the selected volume root is not accessible.'
}

[pscustomobject]@{
    TargetVolume = $targetMount
    LockStateBefore = 'Locked'
    LockStateAfter = 'Unlocked'
    RecoveryPasswordRetained = $false
    RecoveryPasswordLogged = $false
    AutomaticCodexImport = $false
}
