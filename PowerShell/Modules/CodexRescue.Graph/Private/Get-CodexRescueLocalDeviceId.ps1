function Get-CodexRescueLocalDeviceId {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        return $null
    }
    $joinRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
    if (!(Test-Path -LiteralPath $joinRoot -PathType Container)) {
        return $null
    }

    $deviceIds = @()
    foreach ($joinKey in @(Get-ChildItem -LiteralPath $joinRoot -ErrorAction SilentlyContinue)) {
        $join = Get-ItemProperty -LiteralPath $joinKey.PSPath -Name DeviceId -ErrorAction SilentlyContinue
        if ($null -eq $join) { continue }
        $parsed = [guid]::Empty
        if ([guid]::TryParse([string]$join.DeviceId, [ref]$parsed)) {
            $deviceIds += $parsed.ToString('D')
        }
    }
    $unique = @($deviceIds | Sort-Object -Unique)
    if ($unique.Count -gt 1) {
        throw 'Multiple local Entra device IDs were found. Supply the intended ID explicitly after local verification.'
    }
    if ($unique.Count -eq 0) {
        return $null
    }
    return $unique[0]
}
