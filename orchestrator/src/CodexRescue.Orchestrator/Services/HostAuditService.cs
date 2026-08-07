namespace CodexRescue.Orchestrator.Services;

public enum AuditDisposition
{
    Installed,
    Missing,
    Blocked,
    Unverified,
    Optional,
    Disabled
}

public sealed record AuditComponentResult(
    string Component,
    AuditDisposition Disposition,
    string Detail,
    string? DetectedVersion = null);

public sealed record HostAuditResult(
    DateTimeOffset CompletedAtUtc,
    IReadOnlyList<AuditComponentResult> Components,
    bool NetworkRequestsMade,
    bool ChangesMade);

public sealed class HostAuditService
{
    public Task<HostAuditResult> AuditAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var windows = OperatingSystem.IsWindows();
        var adkRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            "Windows Kits",
            "10",
            "Assessment and Deployment Kit");
        var winPeRoot = Path.Combine(adkRoot, "Windows Preinstallation Environment");

        var components = new List<AuditComponentResult>
        {
            new(
                "Windows host",
                windows ? AuditDisposition.Installed : AuditDisposition.Blocked,
                windows
                    ? "Windows host detected. The audit did not modify configuration."
                    : "A supported Windows 11 build host is required.",
                windows ? Environment.OSVersion.Version.ToString() : null),
            new(
                "WinPE toolchain",
                Directory.Exists(winPeRoot) ? AuditDisposition.Installed : AuditDisposition.Missing,
                Directory.Exists(winPeRoot)
                    ? "Windows ADK and WinPE paths are present; package versions still require manifest verification."
                    : "Windows ADK Deployment Tools and the matching WinPE add-on were not found."),
            new(
                "Signing trust",
                AuditDisposition.Unverified,
                "No publisher is trusted until a signed release manifest and artifact chain are verified."),
            new(
                "Codex CLI",
                FindOnPath("codex.exe", "codex.cmd") is not null
                    ? AuditDisposition.Installed
                    : AuditDisposition.Missing,
                "Codex remains a full-Windows tool and is never launched from WinPE."),
            new(
                "Proxmox connector",
                AuditDisposition.Optional,
                "No endpoint or session credential is stored by the read-only audit."),
            new(
                "Network & telemetry",
                AuditDisposition.Disabled,
                "Networking and telemetry are disabled by default; this audit made zero requests."),
        };

        return Task.FromResult(new HostAuditResult(
            DateTimeOffset.UtcNow,
            components,
            NetworkRequestsMade: false,
            ChangesMade: false));
    }

    private static string? FindOnPath(params string[] names)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var name in names)
            {
                var candidate = Path.Combine(directory.Trim('"'), name);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        return null;
    }
}
