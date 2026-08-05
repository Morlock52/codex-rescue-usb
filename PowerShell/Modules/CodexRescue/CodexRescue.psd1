@{
  RootModule        = 'CodexRescue.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = '434c389f-0b1c-49d5-98e8-ecac064f55f6'
  Author            = 'Codex Rescue USB contributors'
  CompanyName       = ''
  Copyright         = 'Copyright (c) 2026 Codex Rescue USB contributors'
  Description       = 'Read-only Windows 11, Autopilot, Intune, Entra, BitLocker, TPM, update, network, driver, and event diagnostics with privacy-safe reporting.'
  PowerShellVersion = '5.1'
  FunctionsToExport = @(
    'Export-CodexRescueLogs'
    'Get-CodexRescueAutopilotStatus'
    'Get-CodexRescueBitLockerStatus'
    'Get-CodexRescueCertificateHealth'
    'Get-CodexRescueDeviceHealth'
    'Get-CodexRescueDriverStatus'
    'Get-CodexRescueEntraStatus'
    'Get-CodexRescueEventErrors'
    'Get-CodexRescueIntuneStatus'
    'Get-CodexRescueNetworkStatus'
    'Get-CodexRescueTpmStatus'
    'Get-CodexRescueWindowsUpdateStatus'
    'Invoke-CodexRescueValidation'
    'New-CodexRescueReport'
  )
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  PrivateData       = @{
    PSData = @{
      Tags = @('Windows', 'Intune', 'Autopilot', 'Entra', 'Diagnostics', 'Recovery')
      ProjectUri = 'https://github.com/Morlock52/codex-rescue-usb'
    }
  }
}
