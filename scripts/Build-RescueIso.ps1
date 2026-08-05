<#
.SYNOPSIS
Builds the Codex Rescue Windows PE ISO.

.DESCRIPTION
Stages an amd64 Windows PE working directory, injects the checked-in read-only
rescue launcher and evidence scripts into boot.wim, and creates an ISO using
Microsoft's current Windows UEFI CA 2023-signed boot files.

.PARAMETER OutputDirectory
Directory that receives the temporary work tree and completed ISO. Defaults to
the repository's dist directory.

.PARAMETER Name
Base name for the ISO file.

.PARAMETER Force
Recreates an existing work tree and permits replacement of an existing ISO.

.EXAMPLE
.\scripts\Build-RescueIso.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$Name = 'Codex-Rescue-ISO',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run the ISO build from an elevated Windows PowerShell session.'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot '..\dist'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$adkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit'
$deploymentTools = Join-Path $adkRoot 'Deployment Tools'
$setAdkEnvironment = Join-Path $deploymentTools 'DandISetEnv.bat'
$winPeTools = Join-Path $adkRoot 'Windows Preinstallation Environment'
$winPeOptionalComponents = Join-Path $winPeTools 'amd64\WinPE_OCs'
$copype = Join-Path $winPeTools 'copype.cmd'
$makeMedia = Join-Path $winPeTools 'MakeWinPEMedia.cmd'
if (!(Test-Path $setAdkEnvironment) -or !(Test-Path $copype) -or !(Test-Path $makeMedia) -or !(Test-Path $winPeOptionalComponents)) {
    throw 'Install Windows ADK Deployment Tools and the matching Windows PE add-on before building.'
}

function Invoke-AdkCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $quotedArguments = $Arguments | ForEach-Object {
        if ($_ -match '^/[A-Za-z0-9]+$') {
            $_
        }
        else {
            '"{0}"' -f ($_ -replace '"', '""')
        }
    }
    $batchPath = Join-Path ([IO.Path]::GetTempPath()) ("CodexRescueAdk-{0}.cmd" -f [guid]::NewGuid())
    @(
        '@echo off',
        ('call "{0}" >nul' -f $setAdkEnvironment),
        'if errorlevel 1 exit /b %errorlevel%',
        ('call "{0}" {1}' -f $Command, ($quotedArguments -join ' ')),
        'exit /b %errorlevel%'
    ) | Set-Content -Encoding ASCII $batchPath

    try {
        $process = Start-Process $env:ComSpec -ArgumentList @(
            '/d', '/c', ('"{0}"' -f $batchPath)
        ) -NoNewWindow -Wait -PassThru
    }
    finally {
        Remove-Item $batchPath -Force -ErrorAction SilentlyContinue
    }

    if ($process.ExitCode -ne 0) {
        throw "ADK command failed with exit code $($process.ExitCode): $Command"
    }
}

function Invoke-DismCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & dism.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "DISM failed with exit code $LASTEXITCODE."
    }
}

function Copy-BatchFile {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    Get-Content -LiteralPath $Source |
        Set-Content -LiteralPath $Destination -Encoding ASCII
}

$work = Join-Path $OutputDirectory 'work'
$iso = Join-Path $OutputDirectory "$Name.iso"
if (Test-Path $work) { if (!$Force) { throw "Build workspace exists: $work. Re-run with -Force." }; Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
Invoke-AdkCommand -Command $copype -Arguments @('amd64', $work)

$media = Join-Path $work 'media'
$bootWim = Join-Path $media 'sources\boot.wim'
$mount = Join-Path $work 'mount'
New-Item -ItemType Directory -Force $mount | Out-Null
$mounted = $false
try {
    Invoke-DismCommand -Arguments @(
        '/Mount-Image', "/ImageFile:$bootWim", '/Index:1', "/MountDir:$mount"
    )
    $mounted = $true

    $powerShellComponents = @(
        'WinPE-WMI',
        'WinPE-SecureStartup',
        'WinPE-NetFx',
        'WinPE-Scripting',
        'WinPE-PowerShell'
    )
    foreach ($component in $powerShellComponents) {
        $componentCab = Join-Path $winPeOptionalComponents "$component.cab"
        $languageCab = Join-Path $winPeOptionalComponents "en-us\${component}_en-us.cab"
        if (!(Test-Path $componentCab) -or !(Test-Path $languageCab)) {
            throw "Required WinPE optional component is missing: $component"
        }
        Invoke-DismCommand -Arguments @("/Image:$mount", '/Add-Package', "/PackagePath:$componentCab")
        Invoke-DismCommand -Arguments @("/Image:$mount", '/Add-Package', "/PackagePath:$languageCab")
    }

    $rescueDirectory = Join-Path $mount 'Rescue'
    New-Item -ItemType Directory -Force $rescueDirectory | Out-Null
    Copy-BatchFile -Source (Join-Path $PSScriptRoot '..\winpe\Collect-RescueEvidence.cmd') -Destination (Join-Path $rescueDirectory 'Collect-RescueEvidence.cmd')
    Copy-BatchFile -Source (Join-Path $PSScriptRoot '..\winpe\Unlock-BitLockerWithRecoveryKey.cmd') -Destination (Join-Path $rescueDirectory 'Unlock-BitLockerWithRecoveryKey.cmd')
    Copy-Item (Join-Path $PSScriptRoot '..\winpe\Unlock-BitLockerWithRecoveryPassword.ps1') (Join-Path $rescueDirectory 'Unlock-BitLockerWithRecoveryPassword.ps1')
    Copy-Item (Join-Path $PSScriptRoot '..\winpe\New-EvidenceManifest.ps1') (Join-Path $rescueDirectory 'New-EvidenceManifest.ps1')
    Copy-Item (Join-Path $PSScriptRoot '..\winpe\Collect-OfflineWindowsInventory.ps1') (Join-Path $rescueDirectory 'Collect-OfflineWindowsInventory.ps1')
    Copy-Item (Join-Path $PSScriptRoot '..\winpe\diskpart-list.txt') (Join-Path $rescueDirectory 'diskpart-list.txt')
    Copy-BatchFile -Source (Join-Path $PSScriptRoot '..\winpe\startnet.cmd') -Destination (Join-Path $mount 'Windows\System32\startnet.cmd')

    Invoke-DismCommand -Arguments @('/Unmount-Image', "/MountDir:$mount", '/Commit')
    $mounted = $false
}
catch {
    if ($mounted) {
        & dism.exe '/Unmount-Image' "/MountDir:$mount" '/Discard'
    }
    throw
}

$mediaArguments = @('/ISO')
if ($Force) {
    $mediaArguments += '/F'
}
$mediaArguments += @($work, $iso, '/BOOTEX')
Invoke-AdkCommand -Command $makeMedia -Arguments $mediaArguments
$verifier = Join-Path $PSScriptRoot 'Test-RescueIso.ps1'
& $verifier -IsoPath $iso -OutputPath "$iso.verification.json" | Out-Host
Write-Output "Created and verified $iso"
