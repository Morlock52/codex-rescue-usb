<#
.SYNOPSIS
Builds one unsigned MSIX from already-signed release payloads.

.DESCRIPTION
This step never signs or creates certificates. It refuses any executable,
library, or privileged PowerShell payload whose Authenticode status is not
Valid and whose signer subject does not match the MSIX publisher. The release
pipeline signs the completed MSIX with Azure Artifact Signing afterward.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppPublishDirectory,
    [Parameter(Mandatory)][string]$BrokerPublishDirectory,
    [Parameter(Mandatory)][string]$SignedAssetsDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Architecture,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$Publisher,
    [string]$IdentityName = 'CodexRescue.Orchestrator'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SignedPayload {
    param([Parameter(Mandatory)][string[]]$Paths)
    foreach ($path in $Paths) {
        $files = @(Get-ChildItem -LiteralPath $path -File -Recurse | Where-Object {
            $_.Extension -in @('.exe', '.dll', '.ps1')
        })
        if ($files.Count -eq 0) { throw "No signable payload was found in $path." }
        foreach ($file in $files) {
            $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
            if ($signature.Status -ne 'Valid' -or
                $null -eq $signature.SignerCertificate -or
                $signature.SignerCertificate.Subject -cne $Publisher) {
                throw "Release payload is not signed by the declared publisher: $($file.Name)"
            }
        }
    }
}

foreach ($requiredDirectory in @($AppPublishDirectory, $BrokerPublishDirectory, $SignedAssetsDirectory)) {
    if (!(Test-Path -LiteralPath $requiredDirectory -PathType Container)) {
        throw "Required package input is missing: $requiredDirectory"
    }
}
if (!(Test-Path -LiteralPath (Join-Path $AppPublishDirectory 'CodexRescue.Orchestrator.exe') -PathType Leaf) -or
    !(Test-Path -LiteralPath (Join-Path $BrokerPublishDirectory 'CodexRescue.Broker.exe') -PathType Leaf) -or
    !(Test-Path -LiteralPath (Join-Path $SignedAssetsDirectory 'assets-manifest.json') -PathType Leaf)) {
    throw 'Published application, CodexRescue.Broker.exe, or assets-manifest.json is missing.'
}
Assert-SignedPayload -Paths @($AppPublishDirectory, $BrokerPublishDirectory, $SignedAssetsDirectory)

$templatePath = Join-Path $PSScriptRoot 'AppxManifest.template.xml'
$packageAssetRoot = Join-Path $PSScriptRoot 'PackageAssets'
if (!(Test-Path -LiteralPath $packageAssetRoot -PathType Container)) {
    throw 'Figma-derived package artwork is missing.'
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$stage = Join-Path $OutputDirectory "stage-$Architecture"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $AppPublishDirectory '*') -Destination $stage -Recurse -Force
$brokerStage = Join-Path $stage 'Broker'
New-Item -ItemType Directory -Path $brokerStage | Out-Null
Copy-Item -Path (Join-Path $BrokerPublishDirectory '*') -Destination $brokerStage -Recurse -Force
Copy-Item -LiteralPath $SignedAssetsDirectory -Destination (Join-Path $brokerStage 'Assets') -Recurse
Copy-Item -LiteralPath $packageAssetRoot -Destination (Join-Path $stage 'PackageAssets') -Recurse

$escapedPublisher = [Security.SecurityElement]::Escape($Publisher)
$manifestText = Get-Content -LiteralPath $templatePath -Raw
$manifestText = $manifestText.Replace('$IDENTITY_NAME$', $IdentityName)
$manifestText = $manifestText.Replace('$PUBLISHER$', $escapedPublisher)
$manifestText = $manifestText.Replace('$VERSION$', $Version)
$manifestText = $manifestText.Replace('$ARCHITECTURE$', $Architecture)
$manifestPath = Join-Path $stage 'AppxManifest.xml'
$manifestText | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$makeAppx = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if ($null -eq $makeAppx) {
    $makeAppx = Get-ChildItem -Path (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin\*\x64\makeappx.exe') -File |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($null -eq $makeAppx) { throw 'makeappx.exe from the Windows SDK was not found.' }
$packagePath = Join-Path $OutputDirectory "CodexRescue.Orchestrator_$Version`_$Architecture.msix"
if (Test-Path -LiteralPath $packagePath) { throw 'Refusing to replace an existing MSIX.' }
& $makeAppx.FullName pack /d $stage /p $packagePath /o
if ($LASTEXITCODE -ne 0) { throw "makeappx.exe failed with exit code $LASTEXITCODE." }
Get-Item -LiteralPath $packagePath
