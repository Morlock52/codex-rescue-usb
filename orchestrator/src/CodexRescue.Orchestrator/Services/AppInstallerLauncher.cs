using System.Diagnostics;

namespace CodexRescue.Orchestrator.Services;

public sealed class AppInstallerLauncher
{
    public Process LaunchVerified(string verifiedBundleDirectory, string appInstallerName)
    {
        if (!string.Equals(Path.GetExtension(appInstallerName), ".appinstaller", StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(appInstallerName, Path.GetFileName(appInstallerName), StringComparison.Ordinal))
        {
            throw new InvalidDataException("The update entry point must be a local .appinstaller file.");
        }

        var bundleRoot = Path.GetFullPath(verifiedBundleDirectory) + Path.DirectorySeparatorChar;
        var appInstallerPath = Path.GetFullPath(Path.Combine(bundleRoot, appInstallerName));
        if (!appInstallerPath.StartsWith(bundleRoot, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(appInstallerPath))
        {
            throw new FileNotFoundException("The verified App Installer file is missing.", appInstallerPath);
        }

        return Process.Start(new ProcessStartInfo
        {
            FileName = appInstallerPath,
            UseShellExecute = true,
        }) ?? throw new InvalidOperationException("Windows App Installer did not start.");
    }
}
