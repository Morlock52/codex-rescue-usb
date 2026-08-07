<#
.SYNOPSIS
Creates the release-only catalog after privileged scripts are signed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AssetsDirectory,
    [Parameter(Mandatory)][string]$PackageVersion,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$SourceRevision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expected = @(
    [pscustomobject]@{ Operation = 'ApplyToolchain'; FileName = 'scripts/Install-TechnicianWorkspaceToolchain.ps1' }
    [pscustomobject]@{ Operation = 'BuildMedia'; FileName = 'scripts/Build-CodexRescueMediaMatrix.ps1' }
    [pscustomobject]@{ Operation = 'WriteUsb'; FileName = 'scripts/Write-CodexRescueUsb.ps1' }
    [pscustomobject]@{ Operation = 'RepairUefi'; FileName = 'scripts/Invoke-CodexRescueUefiRepair.ps1' }
    [pscustomobject]@{ Operation = 'SalvageBitLocker'; FileName = 'scripts/Invoke-CodexRescueBitLockerSalvage.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'scripts/Test-TechnicianWorkspacePrerequisite.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'scripts/Build-RescueIso.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'scripts/Test-RescueIso.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/Unlock-BitLockerWithRecoveryPassword.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/New-EvidenceManifest.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/Collect-OfflineWindowsInventory.ps1' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/Collect-RescueEvidence.cmd' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/Unlock-BitLockerWithRecoveryKey.cmd' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/diskpart-list.txt' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'winpe/startnet.cmd' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'config/technician-workspace-tools.json' }
    [pscustomobject]@{ Operation = 'Dependency'; FileName = 'config/media-build-matrix.json' }
)
if (!(Test-Path -LiteralPath $AssetsDirectory -PathType Container)) {
    throw 'Signed assets directory was not found.'
}
$observed = @(Get-ChildItem -LiteralPath $AssetsDirectory -File -Recurse | Where-Object Name -ne 'assets-manifest.json')
$observedNames = @($observed | ForEach-Object {
    $_.FullName.Substring([IO.Path]::GetFullPath($AssetsDirectory).TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
})
if ($observed.Count -ne $expected.Count -or
    @($observedNames | Where-Object { $_ -notin $expected.FileName }).Count -gt 0) {
    throw 'The signed asset directory has missing or unexpected files.'
}

$publisherThumbprint = $null
$assets = foreach ($entry in $expected) {
    $path = Join-Path $AssetsDirectory $entry.FileName
    $requiresAuthenticode = [IO.Path]::GetExtension($entry.FileName) -ieq '.ps1'
    $thumbprint = ''
    if ($requiresAuthenticode) {
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate) {
            throw "Privileged asset signature is not Valid: $($entry.Operation)"
        }
        $thumbprint = $signature.SignerCertificate.Thumbprint.ToUpperInvariant()
        if ($null -eq $publisherThumbprint) { $publisherThumbprint = $thumbprint }
        if ($thumbprint -cne $publisherThumbprint) { throw 'All privileged assets must have the same signer.' }
    }
    [ordered]@{
        Operation = $entry.Operation
        FileName = $entry.FileName
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        SignerThumbprint = $thumbprint
        RequireAuthenticode = $requiresAuthenticode
    }
}
$catalog = [ordered]@{
    SchemaVersion = 1
    PackageVersion = $PackageVersion
    SourceRevision = $SourceRevision.ToLowerInvariant()
    Assets = @($assets)
}
$outputPath = Join-Path $AssetsDirectory 'assets-manifest.json'
if (Test-Path -LiteralPath $outputPath) { throw 'Refusing to replace an existing assets-manifest.json.' }
$catalog | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputPath -Encoding UTF8
Get-Item -LiteralPath $outputPath
