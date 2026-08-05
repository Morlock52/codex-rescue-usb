function Get-CodexRescueGraphErrorOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ErrorRecord
    )

    $statusCode = $null
    $exception = $ErrorRecord.Exception
    $responseProperty = if ($exception) { $exception.PSObject.Properties['Response'] } else { $null }
    if ($responseProperty -and $responseProperty.Value) {
        $response = $responseProperty.Value
        if ($response.PSObject.Properties.Name -contains 'StatusCode') {
            $statusCode = [int]$response.StatusCode
        }
    }
    $message = [string]$ErrorRecord.Exception.Message
    if ($statusCode -in @(401, 403) -or $message -match '(?i)unauthorized|forbidden|insufficient privileges|permission') {
        return 'PermissionDenied'
    }
    if ($statusCode -eq 404 -or $message -match '(?i)not found|request_resource_not_found') {
        return 'NotFound'
    }
    return 'Unavailable'
}
