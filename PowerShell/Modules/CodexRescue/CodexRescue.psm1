Set-StrictMode -Version 2.0

$public = Join-Path $PSScriptRoot 'Public'
$private = Join-Path $PSScriptRoot 'Private'

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
