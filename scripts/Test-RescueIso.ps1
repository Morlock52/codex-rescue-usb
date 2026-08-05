<#
.SYNOPSIS
Verifies one locally built Codex Rescue Windows PE ISO.

.DESCRIPTION
Records the exact ISO size and SHA-256, confirms the required BIOS and UEFI
boot payloads, mounts boot.wim read-only, verifies that every checked-in rescue
source matches its embedded copy, and confirms the required WinPE packages are
installed. The JSON result contains no recovery material.

.PARAMETER IsoPath
Path to the ISO produced by Build-RescueIso.ps1.

.PARAMETER SourceDirectory
Directory containing the checked-in WinPE source files. Defaults to winpe in
the repository containing this script.

.PARAMETER OutputPath
Path for the verification JSON. Defaults to <ISO path>.verification.json.

.EXAMPLE
.\scripts\Test-RescueIso.ps1 -IsoPath .\dist\Codex-Rescue-ISO.iso
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$IsoPath,

    [string]$SourceDirectory,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run ISO verification from an elevated Windows PowerShell session.'
}
$IsoPath = [IO.Path]::GetFullPath($IsoPath)
if (!(Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
    throw "ISO does not exist: $IsoPath"
}
if ([IO.Path]::GetExtension($IsoPath) -ine '.iso') {
    throw "Expected an .iso file: $IsoPath"
}
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $PSScriptRoot '..\winpe'
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
if (!(Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "WinPE source directory does not exist: $SourceDirectory"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = "$IsoPath.verification.json"
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($OutputPath -ieq $IsoPath) {
    throw 'Verification output must not replace the ISO.'
}
if ([IO.Path]::GetExtension($OutputPath) -ine '.json') {
    throw "Verification output must be a .json file: $OutputPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
$existingDiskImage = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
if ($null -ne $existingDiskImage -and $existingDiskImage.Attached) {
    throw 'The ISO is already mounted. Dismount it before verification.'
}

function Invoke-DismCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & dism.exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed with exit code $LASTEXITCODE."
    }
}

$requiredBootFiles = @(
    'bootmgr',
    'boot\bcd',
    'boot\boot.sdi',
    'efi\boot\bootx64.efi',
    'efi\microsoft\boot\bcd',
    'sources\boot.wim'
)
$embeddedSourceMap = [ordered]@{
    'Collect-RescueEvidence.cmd' = 'Rescue\Collect-RescueEvidence.cmd'
    'Unlock-BitLockerWithRecoveryKey.cmd' = 'Rescue\Unlock-BitLockerWithRecoveryKey.cmd'
    'Unlock-BitLockerWithRecoveryPassword.ps1' = 'Rescue\Unlock-BitLockerWithRecoveryPassword.ps1'
    'New-EvidenceManifest.ps1' = 'Rescue\New-EvidenceManifest.ps1'
    'diskpart-list.txt' = 'Rescue\diskpart-list.txt'
    'startnet.cmd' = 'Windows\System32\startnet.cmd'
}
$requiredPackages = @(
    'WinPE-WMI',
    'WinPE-SecureStartup',
    'WinPE-NetFx',
    'WinPE-Scripting',
    'WinPE-PowerShell'
)

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'CodexRescue-IsoVerify-{0}' -f [guid]::NewGuid()
)
$wimMount = Join-Path $temporaryDirectory 'wim'
New-Item -ItemType Directory -Force $wimMount | Out-Null
$isoMounted = $false
$wimMounted = $false
$result = $null
try {
    $diskImage = Mount-DiskImage -ImagePath $IsoPath -Access ReadOnly -PassThru
    $isoMounted = $true
    $volumes = @($diskImage | Get-Volume)
    if ($volumes.Count -ne 1 -or [string]::IsNullOrWhiteSpace($volumes[0].DriveLetter)) {
        throw 'Expected the mounted ISO to expose exactly one drive-letter volume.'
    }
    $isoRoot = "$($volumes[0].DriveLetter):\"

    foreach ($relativePath in $requiredBootFiles) {
        $candidate = Join-Path $isoRoot $relativePath
        if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Required ISO boot file is missing: $relativePath"
        }
    }

    $bootWim = Join-Path $isoRoot 'sources\boot.wim'
    Invoke-DismCommand -Arguments @(
        '/Mount-Image',
        "/ImageFile:$bootWim",
        '/Index:1',
        "/MountDir:$wimMount",
        '/ReadOnly'
    )
    $wimMounted = $true

    $embeddedFiles = @()
    foreach ($sourceName in $embeddedSourceMap.Keys) {
        $sourcePath = Join-Path $SourceDirectory $sourceName
        $embeddedPath = Join-Path $wimMount $embeddedSourceMap[$sourceName]
        if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Checked-in WinPE source is missing: $sourceName"
        }
        if (!(Test-Path -LiteralPath $embeddedPath -PathType Leaf)) {
            throw "Embedded WinPE file is missing: $($embeddedSourceMap[$sourceName])"
        }
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $embeddedHash = (Get-FileHash -LiteralPath $embeddedPath -Algorithm SHA256).Hash
        if ($sourceHash -cne $embeddedHash) {
            throw "Embedded WinPE file does not match source: $sourceName"
        }
        $embeddedFiles += [ordered]@{
            SourceFile = $sourceName
            EmbeddedPath = $embeddedSourceMap[$sourceName]
            Sha256 = $sourceHash
        }
    }

    $installedPackages = @(
        Get-WindowsPackage -Path $wimMount |
            Where-Object PackageState -eq 'Installed'
    )
    foreach ($requiredPackage in $requiredPackages) {
        $packageMatches = @($installedPackages | Where-Object {
            $_.PackageName -like "*$requiredPackage*"
        })
        if ($packageMatches.Count -eq 0) {
            $observedWinPePackages = @(
                $installedPackages |
                    Where-Object PackageName -like '*WinPE*' |
                    ForEach-Object PackageName
            ) -join ', '
            throw "Required WinPE package is not installed: $requiredPackage. Observed installed WinPE packages: $observedWinPePackages"
        }
    }

    $isoFile = Get-Item -LiteralPath $IsoPath
    $result = [ordered]@{
        SchemaVersion = 1
        VerifiedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        ClockSource = 'Windows build environment system clock'
        ClockExternallyValidated = $false
        VerificationSucceeded = $true
        IsoFile = $isoFile.Name
        IsoSize = $isoFile.Length
        IsoSha256 = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
        RequiredBootFiles = $requiredBootFiles
        EmbeddedFiles = $embeddedFiles
        RequiredPackages = $requiredPackages
        ContainsRecoveryMaterial = $false
    }
}
finally {
    if ($wimMounted) {
        & dism.exe '/Unmount-Image' "/MountDir:$wimMount" '/Discard' | Out-Host
    }
    if ($isoMounted) {
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    }
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

$outputDirectory = Split-Path -Parent $OutputPath
if (!(Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Force $outputDirectory | Out-Null
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result
