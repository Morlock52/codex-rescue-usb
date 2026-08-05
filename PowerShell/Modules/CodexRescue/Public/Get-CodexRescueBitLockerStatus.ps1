function Get-CodexRescueBitLockerStatus {
    <#
    .SYNOPSIS
    Collects read-only BitLocker volume state without recovery material.
    .DESCRIPTION
    Returns volume, encryption, protection, lock, and protector-type metadata.
    It never requests, exports, or serializes a recovery password or key file.
    .EXAMPLE
    Get-CodexRescueBitLockerStatus
    #>
    [CmdletBinding()]
    param()

    Assert-CodexRescueWindows
    try {
        $command = Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue
        if (!$command) {
            return New-CodexRescueCheck -Name 'BitLocker' -Status 'NotTested' -Summary 'The BitLocker PowerShell command is unavailable.' -Data ([pscustomobject]@{
                VolumeCount = 0
                RecoveryMaterialCollected = $false
            })
        }

        $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
        $volumeResults = foreach ($volume in $volumes) {
            $protectorTypes = @(
                @($volume.KeyProtector) |
                    ForEach-Object { $_.KeyProtectorType.ToString() } |
                    Where-Object { $_ } |
                    Sort-Object -Unique
            )
            [pscustomobject][ordered]@{
                MountPoint = [string]$volume.MountPoint
                VolumeType = $volume.VolumeType.ToString()
                VolumeStatus = $volume.VolumeStatus.ToString()
                ProtectionStatus = $volume.ProtectionStatus.ToString()
                LockStatus = $volume.LockStatus.ToString()
                EncryptionPercentage = [int]$volume.EncryptionPercentage
                EncryptionMethod = $volume.EncryptionMethod.ToString()
                KeyProtectorTypes = @($protectorTypes)
                KeyProtectorIdentifiersIncluded = $false
            }
        }

        $lockedCount = @($volumeResults | Where-Object LockStatus -EQ 'Locked').Count
        $suspendedCount = @(
            $volumeResults | Where-Object {
                $_.VolumeStatus -ne 'FullyDecrypted' -and $_.ProtectionStatus -ne 'On'
            }
        ).Count
        $encryptedCount = @($volumeResults | Where-Object VolumeStatus -NE 'FullyDecrypted').Count

        $status = 'Healthy'
        $summary = 'BitLocker volume state was read successfully and no suspended protection was detected.'
        if ($lockedCount -gt 0) {
            $status = 'Warning'
            $summary = 'One or more BitLocker volumes are locked. No unlock attempt was made.'
        }
        if ($suspendedCount -gt 0) {
            $status = 'Failed'
            $summary = 'One or more encrypted BitLocker volumes do not have protection enabled.'
        }
        elseif ($encryptedCount -eq 0) {
            $status = 'Warning'
            $summary = 'No encrypted BitLocker volume was detected.'
        }

        New-CodexRescueCheck -Name 'BitLocker' -Status $status -Summary $summary -Data ([pscustomobject][ordered]@{
            VolumeCount = $volumeResults.Count
            EncryptedVolumeCount = $encryptedCount
            LockedVolumeCount = $lockedCount
            SuspendedProtectionCount = $suspendedCount
            Volumes = @($volumeResults)
            RecoveryMaterialCollected = $false
            RecoveryMaterialAvailabilityTested = $false
            CloudEscrowTested = $false
        })
    }
    catch {
        New-CodexRescueCheck -Name 'BitLocker' -Status 'NotTested' -Summary 'BitLocker status could not be completed.' -Data $null -Errors @($_.Exception.Message)
    }
}
