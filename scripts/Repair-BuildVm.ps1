[CmdletBinding()]
param(
    [string]$OutputDirectory = 'C:\CodexRescueVmAudit'
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (!(Test-Administrator)) {
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-OutputDirectory', ('"{0}"' -f $OutputDirectory)
    )
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit 0
}

New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$logPath = Join-Path $OutputDirectory 'Repair-BuildVm.log'
Start-Transcript -Path $logPath -Force | Out-Null

try {
    Write-Host 'Codex Rescue build VM repair and audit'
    Write-Host 'No passwords, recovery keys, tokens, or user files are collected.'

    $virtioRoot = Get-Volume |
        Where-Object DriveLetter |
        ForEach-Object { "$($_.DriveLetter):\" } |
        Where-Object {
            (Test-Path (Join-Path $_ 'guest-agent\qemu-ga-x86_64.msi')) -and
            (Test-Path (Join-Path $_ 'vioserial\w11\amd64\vioser.inf'))
        } |
        Select-Object -First 1
    if (!$virtioRoot) {
        throw 'VirtIO tools were not found. Attach the VirtIO tools ISO and run this script again.'
    }

    $serialDriver = Join-Path $virtioRoot 'vioserial\w11\amd64\vioser.inf'
    Write-Host "Installing the signed VirtIO serial driver from $serialDriver"
    $driverInstall = Start-Process pnputil.exe -Wait -PassThru -ArgumentList @(
        '/add-driver', ('"{0}"' -f $serialDriver), '/install'
    )
    if ($driverInstall.ExitCode -notin 0, 259) {
        throw "VirtIO serial driver installation failed with exit code $($driverInstall.ExitCode)."
    }
    if ($driverInstall.ExitCode -eq 259) {
        Write-Host 'VirtIO serial driver is already current (Already exists in the system).'
    }

    $agentService = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
    if (!$agentService) {
        $agentMsi = Join-Path $virtioRoot 'guest-agent\qemu-ga-x86_64.msi'

        Write-Host "Installing QEMU Guest Agent from $agentMsi"
        $msiLog = Join-Path $OutputDirectory 'QemuGuestAgent-install.log'
        $installer = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
            '/i', ('"{0}"' -f $agentMsi), '/qn', '/norestart', '/l*v', ('"{0}"' -f $msiLog)
        )
        if ($installer.ExitCode -notin 0, 3010) {
            throw "QEMU Guest Agent installer failed with exit code $($installer.ExitCode)."
        }
        $agentService = Get-Service -Name 'QEMU-GA' -ErrorAction Stop
    }

    Set-Service -Name $agentService.Name -StartupType Automatic
    $agentService = Get-Service -Name $agentService.Name
    if ($agentService.Status -ne 'Running') {
        Start-Service -Name $agentService.Name
        $agentService.WaitForStatus('Running', (New-TimeSpan -Seconds 15))
        $agentService = Get-Service -Name $agentService.Name
    }
    Write-Host "QEMU Guest Agent: $($agentService.Status), automatic start"

    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $systemDrive = Get-Volume -DriveLetter ($env:SystemDrive).TrimEnd(':')
    $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1

    $commandNames = @(
        'winget', 'git', 'gh', 'code', 'cursor', 'node', 'npm',
        'python', 'py', 'pwsh', 'codex', 'roc', 'rock'
    )
    $commands = foreach ($name in $commandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        [ordered]@{
            Name = $name
            Installed = [bool]$command
            Path = if ($command) { $command.Source } else { $null }
        }
    }

    $adkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit'
    $deploymentTools = Join-Path $adkRoot 'Deployment Tools'
    $winPeTools = Join-Path $adkRoot 'Windows Preinstallation Environment'
    $adk = [ordered]@{
        Root = $adkRoot
        DeploymentTools = Test-Path $deploymentTools
        CopyPe = Test-Path (Join-Path $winPeTools 'copype.cmd')
        MakeWinPEMedia = Test-Path (Join-Path $winPeTools 'MakeWinPEMedia.cmd')
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $softwarePattern = 'Assessment and Deployment Kit|Windows Preinstallation Environment|QEMU Guest Agent|VirtIO|Git|GitHub|Cursor|Python|Node\.js|PowerShell|Codex'
    $software = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object DisplayName -Match $softwarePattern |
        Sort-Object DisplayName, DisplayVersion -Unique |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

    $audit = [ordered]@{
        SchemaVersion = 1
        CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
        ComputerName = $env:COMPUTERNAME
        OperatingSystem = [ordered]@{
            Caption = $operatingSystem.Caption
            Version = $operatingSystem.Version
            BuildNumber = $operatingSystem.BuildNumber
            LastBootUpTime = $operatingSystem.LastBootUpTime
        }
        Resources = [ordered]@{
            LogicalProcessors = $computerSystem.NumberOfLogicalProcessors
            Processor = $processor.Name
            MemoryTotalGiB = [math]::Round($operatingSystem.TotalVisibleMemorySize / 1MB, 2)
            MemoryFreeGiB = [math]::Round($operatingSystem.FreePhysicalMemory / 1MB, 2)
            SystemDriveTotalGiB = [math]::Round($systemDrive.Size / 1GB, 2)
            SystemDriveFreeGiB = [math]::Round($systemDrive.SizeRemaining / 1GB, 2)
            PageFiles = @($pageFiles | Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage)
        }
        QemuGuestAgent = [ordered]@{
            ServiceName = $agentService.Name
            Status = $agentService.Status.ToString()
            StartType = (Get-CimInstance Win32_Service -Filter "Name='$($agentService.Name)'").StartMode
        }
        Adk = $adk
        Commands = @($commands)
        RelevantSoftware = @($software)
        RecentHotFixes = @(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID, InstalledOn)
    }

    $auditPath = Join-Path $OutputDirectory 'BuildVm-Audit.json'
    $audit | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $auditPath
    Write-Host "Audit written to $auditPath"
    Write-Host "Free memory: $($audit.Resources.MemoryFreeGiB) GiB of $($audit.Resources.MemoryTotalGiB) GiB"
    Write-Host "Free system-drive space: $($audit.Resources.SystemDriveFreeGiB) GiB"
    Write-Host 'Build VM repair and audit completed.'
}
finally {
    Stop-Transcript | Out-Null
}
