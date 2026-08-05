function Invoke-CodexRescueGraphQuerySafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RelativeUri
    )

    try {
        [pscustomobject][ordered]@{
            Outcome = 'Success'
            Response = Invoke-CodexRescueGraphGet -RelativeUri $RelativeUri
        }
    }
    catch {
        [pscustomobject][ordered]@{
            Outcome = Get-CodexRescueGraphErrorOutcome -ErrorRecord $_
            Response = $null
        }
    }
}
