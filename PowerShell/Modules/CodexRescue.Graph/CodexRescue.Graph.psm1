Set-StrictMode -Version 2.0

$script:CodexRescueGraphRequestCount = 0
$private = Join-Path $PSScriptRoot 'Private'
$public = Join-Path $PSScriptRoot 'Public'

Get-ChildItem -LiteralPath $private -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
Get-ChildItem -LiteralPath $public -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

$exports = @(
    Get-ChildItem -LiteralPath $public -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { $_.BaseName }
)
Export-ModuleMember -Function $exports
