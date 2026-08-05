function Assert-CodexRescueGraphSession {
    [CmdletBinding()]
    param()

    if (!(Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'Microsoft.Graph.Authentication is not loaded. Run Test-CodexRescueGraphPrerequisite first.'
    }
    $context = Get-MgContext -ErrorAction Stop
    if ($null -eq $context) {
        throw 'No Microsoft Graph session is active. Run Connect-CodexRescueGraphReadOnly first.'
    }
    if ($context.AuthType -ne 'Delegated') {
        throw 'Codex Rescue permits delegated Microsoft Graph authentication only.'
    }
    if ([string]$context.ContextScope -ne 'Process') {
        throw 'Codex Rescue requires Microsoft Graph ContextScope=Process.'
    }

    $requiredScopes = @(Get-CodexRescueGraphRequiredScope)
    $actualScopes = @($context.Scopes | ForEach-Object { [string]$_ })
    foreach ($requiredScope in $requiredScopes) {
        if ($actualScopes -notcontains $requiredScope) {
            throw "The active Graph session is missing required read-only scope: $requiredScope"
        }
    }
    $forbiddenPatterns = @(
        '(?i)ReadWrite',
        '(?i)PrivilegedOperations',
        '(?i)^Directory\.Read\.All$',
        '(?i)^Directory\.AccessAsUser\.All$',
        '(?i)^BitlockerKey\.Read\.All$'
    )
    foreach ($scope in $actualScopes) {
        foreach ($pattern in $forbiddenPatterns) {
            if ($scope -match $pattern) {
                throw "The active Graph session contains a prohibited scope: $scope"
            }
        }
    }
    $allowedSessionScopes = @($requiredScopes + @('openid', 'profile', 'email', 'offline_access'))
    foreach ($scope in $actualScopes) {
        if ($allowedSessionScopes -notcontains $scope) {
            throw "The active Graph session contains an unrelated scope: $scope"
        }
    }
    return $context
}
