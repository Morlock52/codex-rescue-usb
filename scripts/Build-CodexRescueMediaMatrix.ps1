<#
.SYNOPSIS
Builds the Codex Rescue artifacts compatible with one verified ADK profile.

.DESCRIPTION
Reads the checked-in four-artifact matrix and an ADK servicing receipt. The
script builds only entries whose exact ADK version and servicing update match
that receipt. Run it once on the x64 profile and once on the Arm64 profile.
It performs no downloads and never treats emulation as hardware proof.
#>
[CmdletBinding()]
param(
    [string]$MatrixPath = (Join-Path $PSScriptRoot '..\config\media-build-matrix.json'),

    [Parameter(Mandatory)]
    [string]$ServicingReceiptPath,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist\media'),

    [string[]]$ArtifactId,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (!(Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required JSON file was not found: $LiteralPath"
    }
    try {
        return Get-Content -LiteralPath $LiteralPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON file '$LiteralPath': $($_.Exception.Message)"
    }
}

$matrix = Read-JsonFile -LiteralPath $MatrixPath
$receipt = Read-JsonFile -LiteralPath $ServicingReceiptPath
if ($matrix.schemaVersion -ne 1 -or $receipt.SchemaVersion -ne 1) {
    throw 'Unsupported matrix or servicing-receipt schema.'
}
if ($receipt.AdkVersion -notmatch '^10\.1\.(26100\.2454|28000\.1)$' -or
    $receipt.KnowledgeBase -notmatch '^KB510168[14]$' -or
    $receipt.PackageSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw 'Servicing receipt is missing exact AdkVersion, KnowledgeBase, or PackageSha256 evidence.'
}

$patches = @($receipt.Patches)
$invalidPatches = @($patches | Where-Object {
    $_.Signature -cne 'Valid' -or
    $_.Signer -notmatch 'O=Microsoft Corporation' -or
    $_.Status -notin @('Applied', 'AppliedRebootRequired', 'NotApplicable')
})
$appliedPatches = @($patches | Where-Object Status -Like 'Applied*')
if ($patches.Count -eq 0 -or $invalidPatches.Count -gt 0 -or $appliedPatches.Count -eq 0) {
    throw 'Servicing receipt contains a patch without a Valid Microsoft signature or applied status.'
}

$compatible = @($matrix.artifacts | Where-Object {
    $_.adkVersion -ceq $receipt.AdkVersion -and
    $_.servicingUpdate -ceq $receipt.KnowledgeBase
})
if (@($ArtifactId).Count -gt 0) {
    $compatible = @($compatible | Where-Object artifactId -In $ArtifactId)
}
if ($compatible.Count -eq 0) {
    throw 'No compatible artifacts match the verified ADK servicing receipt and selection.'
}

$builder = Join-Path $PSScriptRoot 'Build-RescueIso.ps1'
$results = foreach ($artifact in $compatible) {
    $artifactDirectory = Join-Path $OutputDirectory $artifact.artifactId
    $name = "Codex-Rescue-$($artifact.artifactId)"
    $parameters = @{
        OutputDirectory = $artifactDirectory
        Name = $name
        Architecture = [string]$artifact.architecture
        TrustPath = [string]$artifact.trustPath
        ArtifactId = [string]$artifact.artifactId
        AdkVersion = [string]$artifact.adkVersion
        ServicingUpdate = [string]$artifact.servicingUpdate
        Force = $Force
    }
    & $builder @parameters

    $isoPath = Join-Path $artifactDirectory "$name.iso"
    $verificationPath = "$isoPath.verification.json"
    if (!(Test-Path -LiteralPath $isoPath -PathType Leaf) -or
        !(Test-Path -LiteralPath $verificationPath -PathType Leaf)) {
        throw "Artifact did not produce its ISO and verification JSON: $($artifact.artifactId)"
    }

    [ordered]@{
        ArtifactId = [string]$artifact.artifactId
        Architecture = [string]$artifact.architecture
        TrustPath = [string]$artifact.trustPath
        EvidenceTier = [string]$artifact.evidenceTier
        IsoPath = $isoPath
        VerificationPath = $verificationPath
        IsoSha256 = (Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash
        PhysicalHardwareVerified = $false
    }
}

$matrixReceipt = [ordered]@{
    SchemaVersion = 1
    CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    AdkVersion = [string]$receipt.AdkVersion
    KnowledgeBase = [string]$receipt.KnowledgeBase
    ServicingPackageSha256 = [string]$receipt.PackageSha256
    Artifacts = @($results)
    ContainsRecoveryMaterial = $false
}
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$matrixReceiptPath = Join-Path $OutputDirectory "matrix-$($receipt.AdkVersion).verification.json"
$matrixReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $matrixReceiptPath -Encoding UTF8
$matrixReceipt
