<#
.SYNOPSIS
Downloads and installs a Microsoft Windows ADK servicing update.

.DESCRIPTION
Downloads an ADK update ZIP from an approved Microsoft host, verifies that
every contained MSP has a valid Microsoft Authenticode signature, installs all
applicable patches, and writes a machine-readable result manifest. MSP files
for ADK features that are not installed are recorded as not applicable.

.PARAMETER DownloadUri
Official Microsoft URL for the current ADK servicing update ZIP.

.PARAMETER OutputDirectory
Directory that receives the downloaded package, installer logs, and manifest.

.EXAMPLE
.\scripts\Install-AdkServicingUpdate.ps1 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidatePattern('^https://(aka\.ms|download\.microsoft\.com)/')]
    [uri]$DownloadUri = 'https://aka.ms/Windows_ADK_10.1.26100.2454_Update_KB5101684.zip',

    [ValidateSet('10.1.26100.2454', '10.1.28000.1')]
    [string]$AdkVersion = '10.1.26100.2454',

    [ValidateSet('KB5101684', 'KB5101681')]
    [string]$KnowledgeBase = 'KB5101684',

    [string]$OutputDirectory = 'C:\CodexRescueVmAudit\ADK-Servicing'
)

$ErrorActionPreference = 'Stop'

$expectedPair = @{
    '10.1.26100.2454' = 'KB5101684'
    '10.1.28000.1' = 'KB5101681'
}
if ($expectedPair[$AdkVersion] -cne $KnowledgeBase) {
    throw "ADK $AdkVersion must use servicing update $($expectedPair[$AdkVersion])."
}
if ($DownloadUri.AbsoluteUri -notmatch [regex]::Escape($AdkVersion) -or
    $DownloadUri.AbsoluteUri -notmatch [regex]::Escape($KnowledgeBase)) {
    throw 'DownloadUri does not match the declared ADK version and servicing update.'
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

$runDirectory = Join-Path $OutputDirectory (Get-Date -Format 'yyyyMMdd-HHmmss')
$packagePath = Join-Path $runDirectory 'adk-servicing-update.zip'
$extractDirectory = Join-Path $runDirectory 'package'
$manifestPath = Join-Path $runDirectory 'result.json'
New-Item -ItemType Directory -Force $runDirectory, $extractDirectory | Out-Null

if (!$PSCmdlet.ShouldProcess($DownloadUri.AbsoluteUri, "Download and install the signed ADK servicing update into $runDirectory")) {
    return
}

Invoke-WebRequest -UseBasicParsing -Uri $DownloadUri -OutFile $packagePath
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash
Expand-Archive -LiteralPath $packagePath -DestinationPath $extractDirectory

$patches = @(Get-ChildItem -LiteralPath $extractDirectory -Filter '*.msp' -File -Recurse)
if ($patches.Count -eq 0) {
    throw 'The downloaded ADK servicing package contained no MSP files.'
}

$results = foreach ($patch in $patches) {
    $signature = Get-AuthenticodeSignature -LiteralPath $patch.FullName
    $isMicrosoft = $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match 'O=Microsoft Corporation'
    if ($signature.Status -ne 'Valid' -or !$isMicrosoft) {
        throw "Refusing unsigned or non-Microsoft patch: $($patch.Name)"
    }

    $logPath = Join-Path $runDirectory ("msiexec-{0}.log" -f $patch.BaseName)
    $installer = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
        '/p', ('"{0}"' -f $patch.FullName), '/qn', '/norestart',
        '/l*v', ('"{0}"' -f $logPath)
    )

    $status = switch ($installer.ExitCode) {
        0 { 'Applied'; break }
        1642 { 'NotApplicable'; break }
        3010 { 'AppliedRebootRequired'; break }
        default { throw "ADK patch $($patch.Name) failed with exit code $($installer.ExitCode). See $logPath" }
    }

    [ordered]@{
        Name = $patch.Name
        Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $patch.FullName).Hash
        Signature = $signature.Status.ToString()
        Signer = $signature.SignerCertificate.Subject
        ExitCode = $installer.ExitCode
        Status = $status
        Log = $logPath
    }
}

if (@($results | Where-Object Status -Like 'Applied*').Count -eq 0) {
    throw 'No ADK servicing patch applied to an installed component.'
}

$manifest = [ordered]@{
    SchemaVersion = 1
    CompletedAt = (Get-Date).ToUniversalTime().ToString('o')
    AdkVersion = $AdkVersion
    KnowledgeBase = $KnowledgeBase
    DownloadUri = $DownloadUri.AbsoluteUri
    PackageSha256 = $packageHash
    RestartRequired = [bool]($results.Status -contains 'AppliedRebootRequired')
    Patches = @($results)
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $manifestPath
$manifest
