function Assert-CodexRescueWindows {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        throw 'CodexRescue diagnostics require full Windows. The module can be imported elsewhere, but probes cannot run outside Windows.'
    }
}
