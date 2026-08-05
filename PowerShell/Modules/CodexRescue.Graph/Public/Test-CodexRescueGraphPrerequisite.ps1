function Test-CodexRescueGraphPrerequisite {
    <#
    .SYNOPSIS
    Checks the local prerequisites for consent-bound read-only Graph visibility.
    .DESCRIPTION
    Performs local inspection only. It does not contact Microsoft Graph, load a
    token, or change the installed Microsoft.Graph modules.
    #>
    [CmdletBinding()]
    param()

    $modules = @(Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Sort-Object Version -Descending)
    $module = $modules | Select-Object -First 1
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        Supported = ($env:OS -eq 'Windows_NT' -and $null -ne $module)
        FullWindows = ($env:OS -eq 'Windows_NT')
        WindowsPowerShellVersion = $PSVersionTable.PSVersion.ToString()
        GraphAuthenticationModuleInstalled = ($null -ne $module)
        GraphAuthenticationModuleVersion = if ($module) { $module.Version.ToString() } else { $null }
        RequiredScopes = @(Get-CodexRescueGraphRequiredScope)
        RequiredScopeCount = @(Get-CodexRescueGraphRequiredScope).Count
        NetworkRequestPerformed = $false
        InstallationPerformed = $false
        CredentialsCollected = $false
    }
}
