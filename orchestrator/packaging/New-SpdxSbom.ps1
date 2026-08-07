[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$PackageVersion,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $ArtifactDirectory -PathType Container) -or (Test-Path -LiteralPath $OutputPath)) {
    throw 'Artifact directory must exist and OutputPath must be new.'
}
$root = [IO.Path]::GetFullPath($ArtifactDirectory).TrimEnd('\')
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
    [ordered]@{
        fileName = "./$relative"
        SPDXID = "SPDXRef-File-$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.Substring(0, 16))"
        checksums = @([ordered]@{ algorithm = 'SHA256'; checksumValue = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
    }
})
$document = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = "Codex-Rescue-Orchestrator-$PackageVersion"
    documentNamespace = "https://github.com/Morlock52/codex-rescue-usb/sbom/$PackageVersion/$([guid]::NewGuid())"
    creationInfo = [ordered]@{
        created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        creators = @('Tool: CodexRescue.New-SpdxSbom/1')
    }
    packages = @([ordered]@{
        name = 'Codex Rescue Orchestrator'
        SPDXID = 'SPDXRef-Package-Orchestrator'
        versionInfo = $PackageVersion
        downloadLocation = 'NOASSERTION'
        filesAnalyzed = $true
        licenseConcluded = 'NOASSERTION'
        licenseDeclared = 'NOASSERTION'
        copyrightText = 'NOASSERTION'
    })
    files = $files
}
$document | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Get-Item -LiteralPath $OutputPath
