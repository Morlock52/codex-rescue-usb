<#
.SYNOPSIS
Creates a machine-readable manifest and SHA-256 list for a collected evidence package.

.DESCRIPTION
Revalidates the prepared destination, hashes the evidence files already written
by Collect-RescueEvidence.cmd, writes manifest.json, and then writes a checksum
list that includes the manifest itself. It never reads outside the selected
CodexRescueEvidence directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$directory = Get-Item -LiteralPath $OutputDirectory -ErrorAction Stop
if (!$directory.PSIsContainer -or $directory.Name -ne 'CodexRescueEvidence') {
    throw 'The output path is not a CodexRescueEvidence directory.'
}

$root = [IO.Path]::GetPathRoot($directory.FullName)
if ($root -notmatch '^[D-WYZ]:\\$') {
    throw 'The evidence directory is not on an allowed prepared destination.'
}
if (!(Test-Path -LiteralPath (Join-Path $root 'CODEX_EVIDENCE.DEST') -PathType Leaf)) {
    throw 'The destination marker is missing.'
}

$manifestPath = Join-Path $directory.FullName 'manifest.json'
$checksumPath = Join-Path $directory.FullName 'SHA256SUMS.txt'
$reservedNames = @('manifest.json', 'SHA256SUMS.txt')
$evidenceFiles = @(
    Get-ChildItem -LiteralPath $directory.FullName -File |
        Where-Object Name -NotIn $reservedNames |
        Sort-Object Name
)
if (!$evidenceFiles.Count) {
    throw 'No evidence files are available to manifest.'
}

$entries = foreach ($file in $evidenceFiles) {
    [ordered]@{
        Name = $file.Name
        Length = $file.Length
        Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

$manifest = [ordered]@{
    SchemaVersion = 1
    CreatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    ClockSource = 'WinPE system clock'
    ClockExternallyValidated = $false
    CollectionMode = 'read-only diagnostics'
    Files = @($entries)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$checksumFiles = @(
    Get-ChildItem -LiteralPath $directory.FullName -File |
        Where-Object Name -ne 'SHA256SUMS.txt' |
        Sort-Object Name
)
$checksumLines = foreach ($file in $checksumFiles) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    "$hash  $($file.Name)"
}
$checksumLines | Set-Content -LiteralPath $checksumPath -Encoding ASCII

[pscustomobject]@{
    Manifest = $manifestPath
    Checksums = $checksumPath
    EvidenceFileCount = $evidenceFiles.Count
}
