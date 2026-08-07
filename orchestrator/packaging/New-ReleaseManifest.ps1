[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PublisherIdentity,
    [Parameter(Mandatory)][string]$RollbackPackage,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputPath) { throw 'Refusing to replace a release manifest.' }
$artifacts = @(Get-ChildItem -LiteralPath $ArtifactDirectory -File | Where-Object Name -ne ([IO.Path]::GetFileName($OutputPath)) | Sort-Object Name | ForEach-Object {
    $architecture = if ($_.Name -match '(?i)arm64') { 'arm64' } elseif ($_.Name -match '(?i)x64') { 'x64' } else { 'neutral' }
    [ordered]@{
        Name = $_.Name
        Architecture = $architecture
        Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        SizeBytes = $_.Length
    }
})
$manifest = [ordered]@{
    SchemaVersion = 1
    Version = $Version
    Architecture = 'x64-arm64-bundle'
    Artifacts = $artifacts
    PublisherIdentity = $PublisherIdentity
    MinimumOsVersion = '10.0.22621.0'
    RollbackPackage = $RollbackPackage
    PublishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Get-Item -LiteralPath $OutputPath
