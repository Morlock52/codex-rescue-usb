[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
    [string]$Name = 'Codex-Rescue-ISO',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$adkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment'
$copype = Join-Path $adkRoot 'copype.cmd'
$makeMedia = Join-Path $adkRoot 'MakeWinPEMedia.cmd'
if (!(Test-Path $copype) -or !(Test-Path $makeMedia)) {
    throw 'Install Windows ADK Deployment Tools and the matching Windows PE add-on before building.'
}

$work = Join-Path $OutputDirectory 'work'
$iso = Join-Path $OutputDirectory "$Name.iso"
if (Test-Path $work) { if (!$Force) { throw "Build workspace exists: $work. Re-run with -Force." }; Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
& $copype amd64 $work

$media = Join-Path $work 'media'
New-Item -ItemType Directory -Force (Join-Path $media 'Rescue') | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\winpe\startnet.cmd') (Join-Path $media 'Rescue\startnet.cmd')
Copy-Item (Join-Path $PSScriptRoot '..\winpe\Collect-RescueEvidence.cmd') (Join-Path $media 'Rescue\Collect-RescueEvidence.cmd')
Copy-Item (Join-Path $PSScriptRoot '..\winpe\diskpart-list.txt') (Join-Path $media 'Rescue\diskpart-list.txt')

$startnet = Join-Path $media 'Windows\System32\startnet.cmd'
Add-Content $startnet "call X:\Rescue\startnet.cmd"
& $makeMedia /ISO $work $iso
Write-Host "Created $iso"
