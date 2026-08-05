function Get-CodexRescueOfflineWindows {
    [CmdletBinding()]
    param()

    $results = @()
    if (!(Get-Command Get-Volume -ErrorAction SilentlyContinue)) {
        return $results
    }

    $currentRoot = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd('\\') } else { $null }
    foreach ($volume in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter)) {
        $root = '{0}:' -f $volume.DriveLetter
        $windowsDirectory = Join-Path $root 'Windows'
        $systemHive = Join-Path $windowsDirectory 'System32\Config\SYSTEM'
        $kernel = Join-Path $windowsDirectory 'System32\ntoskrnl.exe'
        if (!(Test-Path -LiteralPath $systemHive -PathType Leaf) -or !(Test-Path -LiteralPath $kernel -PathType Leaf)) {
            continue
        }

        $results += [pscustomobject][ordered]@{
            Root = $root
            IsCurrentSystem = ($root -ieq $currentRoot)
            WindowsDirectoryPresent = $true
            SystemHivePresent = $true
            KernelPresent = $true
            FileSystem = $volume.FileSystem
            DriveType = $volume.DriveType.ToString()
        }
    }
    return @($results)
}
