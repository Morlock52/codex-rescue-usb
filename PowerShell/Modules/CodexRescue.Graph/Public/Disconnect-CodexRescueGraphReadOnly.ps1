function Disconnect-CodexRescueGraphReadOnly {
    <#
    .SYNOPSIS
    Ends the process-scoped Microsoft Graph session.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
        Disconnect-MgGraph -ErrorAction Stop | Out-Null
    }
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        Connected = $false
        ContextScope = 'Process'
        TokenIncluded = $false
        CredentialsCollected = $false
    }
}
