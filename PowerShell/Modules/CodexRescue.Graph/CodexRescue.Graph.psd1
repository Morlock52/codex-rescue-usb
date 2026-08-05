@{
  RootModule        = 'CodexRescue.Graph.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = 'a42e7869-75e7-42ac-b58d-1ca7553ebdcb'
  Author            = 'Codex Rescue USB contributors'
  CompanyName       = ''
  Copyright         = 'Copyright (c) 2026 Codex Rescue USB contributors'
  Description       = 'Consent-bound, delegated, process-scoped, read-only Microsoft Graph visibility for Codex Rescue.'
  PowerShellVersion = '5.1'
  FunctionsToExport = @(
    'Connect-CodexRescueGraphReadOnly'
    'Disconnect-CodexRescueGraphReadOnly'
    'Get-CodexRescueCloudDeviceHealth'
    'Test-CodexRescueGraphPrerequisite'
  )
  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()
  PrivateData       = @{
    PSData = @{
      Tags = @('Windows', 'MicrosoftGraph', 'Intune', 'Autopilot', 'Entra', 'ReadOnly')
      ProjectUri = 'https://github.com/Morlock52/codex-rescue-usb'
    }
  }
}
