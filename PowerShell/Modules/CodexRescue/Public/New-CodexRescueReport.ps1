function New-CodexRescueReport {
    <#
    .SYNOPSIS
    Writes a new HTML report for a Codex Rescue assessment.
    .DESCRIPTION
    HTML-encodes every assessment value and refuses to overwrite an existing
    report. Passing a sanitized assessment produces the shareable report view.
    .PARAMETER Assessment
    An object returned by Get-CodexRescueDeviceHealth or its sanitized form.
    .PARAMETER OutputPath
    A new .html file in an existing directory.
    .EXAMPLE
    $health = Get-CodexRescueDeviceHealth
    New-CodexRescueReport -Assessment $health -OutputPath C:\Temp\report.html
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object]$Assessment,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath
    )

    process {
        $fullPath = [IO.Path]::GetFullPath($OutputPath)
        if ([IO.Path]::GetExtension($fullPath) -ine '.html') {
            throw 'The report output path must use the .html extension.'
        }
        if (Test-Path -LiteralPath $fullPath) {
            throw "The report already exists and will not be overwritten: $fullPath"
        }
        $parent = Split-Path -Parent $fullPath
        if (!(Test-Path -LiteralPath $parent -PathType Container)) {
            throw "Create the report parent directory first: $parent"
        }
        if ($PSCmdlet.ShouldProcess($fullPath, 'Write new Codex Rescue HTML report')) {
            $html = ConvertTo-CodexRescueHtml -Assessment $Assessment
            [IO.File]::WriteAllText($fullPath, $html, [Text.UTF8Encoding]::new($false))
            Get-Item -LiteralPath $fullPath
        }
    }
}
