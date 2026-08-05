function Connect-CodexRescueGraphReadOnly {
    <#
    .SYNOPSIS
    Opens a delegated, process-scoped, read-only Microsoft Graph session.
    .PARAMETER ConfirmationToken
    Must exactly match CONNECT CODEX RESCUE READ ONLY GRAPH.
    .PARAMETER UseDeviceCode
    Uses Microsoft Graph device-code authentication instead of the default
    interactive browser flow. Authentication remains delegated and process scoped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmationToken,

        [switch]$UseDeviceCode
    )

    $requiredToken = 'CONNECT CODEX RESCUE READ ONLY GRAPH'
    if ($ConfirmationToken -cne $requiredToken) {
        throw "Graph connection requires the exact confirmation token: $requiredToken"
    }
    $prerequisite = Test-CodexRescueGraphPrerequisite
    if (!$prerequisite.Supported) {
        throw 'Microsoft.Graph.Authentication is required in full Windows before Graph connection.'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    $connectParameters = @{
        Scopes = @(Get-CodexRescueGraphRequiredScope)
        ContextScope = 'Process'
        NoWelcome = $true
    }
    if ($UseDeviceCode) {
        $connectParameters.UseDeviceCode = $true
    }
    Connect-MgGraph @connectParameters | Out-Null
    $context = Get-MgContext -ErrorAction Stop
    if ($context.AuthType -ne 'Delegated') {
        Disconnect-MgGraph | Out-Null
        throw 'Codex Rescue permits delegated Microsoft Graph authentication only.'
    }
    if ([string]$context.ContextScope -ne 'Process') {
        Disconnect-MgGraph | Out-Null
        throw 'Codex Rescue requires Microsoft Graph ContextScope=Process.'
    }
    try {
        $null = Assert-CodexRescueGraphSession
    }
    catch {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        throw
    }

    [pscustomobject][ordered]@{
        SchemaVersion = 1
        Connected = $true
        AuthType = 'Delegated'
        ContextScope = 'Process'
        RequiredScopes = @(Get-CodexRescueGraphRequiredScope)
        RequiredScopeCount = @(Get-CodexRescueGraphRequiredScope).Count
        ReadOnly = $true
        AccountIncluded = $false
        TenantIdentifierIncluded = $false
        TokenIncluded = $false
        CredentialsCollected = $false
    }
}
