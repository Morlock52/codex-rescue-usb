<#
.SYNOPSIS
Installs the supported Codex Rescue build-VM development tools with WinGet.

.DESCRIPTION
Installs the small, general-purpose toolchain used to maintain this repository:
Git, GitHub CLI, PowerShell 7, and Python 3.14. Node.js, VS Code, Cursor, and
Codex are audited but are not reinstalled when already present. The script
writes a non-secret JSON manifest and transcript for later verification.

.PARAMETER OutputDirectory
Directory that receives the transcript and result manifest.

.EXAMPLE
.\scripts\Install-BuildVmToolchain.ps1 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$OutputDirectory = 'C:\CodexRescueVmAudit\Toolchain'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$logPath = Join-Path $OutputDirectory 'Install-BuildVmToolchain.log'
$manifestPath = Join-Path $OutputDirectory 'result.json'
Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue
Start-Transcript -Path $logPath -Force | Out-Null

try {
    $winget = Get-Command winget.exe -ErrorAction Stop
    $packages = @(
        [ordered]@{ Id = 'Git.Git'; Name = 'Git' },
        [ordered]@{ Id = 'GitHub.cli'; Name = 'GitHub CLI' },
        [ordered]@{ Id = 'Microsoft.PowerShell'; Name = 'PowerShell 7' },
        [ordered]@{ Id = 'Python.Python.3.14'; Name = 'Python 3.14' }
    )
    # WinGet returns 0x8A15002B when the requested exact package is installed
    # and the configured sources have no newer version. That is a healthy,
    # idempotent result rather than an installation failure.
    $noApplicableUpgradeExitCode = -1978335189

    $packageResults = foreach ($package in $packages) {
        $exitCode = $null
        $status = 'SkippedByWhatIf'
        $wingetOutput = @()
        if ($PSCmdlet.ShouldProcess($package.Id, "Install or upgrade $($package.Name) with WinGet")) {
            $wingetOutput = @(
                & $winget.Source install --id $package.Id --exact --silent --disable-interactivity --scope machine --accept-package-agreements --accept-source-agreements 2>&1 |
                    ForEach-Object { $_.ToString() }
            )
            $exitCode = $LASTEXITCODE
            $status = if ($exitCode -eq 0) {
                'InstalledOrCurrent'
            }
            elseif ($exitCode -eq $noApplicableUpgradeExitCode) {
                'AlreadyCurrent'
            }
            else {
                'Failed'
            }
        }

        [ordered]@{
            Id = $package.Id
            Name = $package.Name
            Status = $status
            ExitCode = $exitCode
            Output = @($wingetOutput)
        }
    }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"

    $commandNames = @('git', 'gh', 'pwsh', 'python', 'py', 'node', 'npm', 'code', 'cursor', 'codex', 'roc', 'rock')
    $commands = foreach ($name in $commandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        [ordered]@{
            Name = $name
            Installed = [bool]$command
            Path = if ($command) { $command.Source } else { $null }
        }
    }

    $manifest = [ordered]@{
        SchemaVersion = 1
        CompletedAt = (Get-Date).ToUniversalTime().ToString('o')
        Packages = @($packageResults)
        Commands = @($commands)
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $manifestPath
    $manifest

    if ($packageResults.Status -contains 'Failed') {
        throw "One or more WinGet installs failed. Review $manifestPath and $logPath."
    }
}
finally {
    Stop-Transcript | Out-Null
}
