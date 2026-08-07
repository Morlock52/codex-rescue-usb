using System.Diagnostics;

namespace CodexRescue.Broker;

public sealed class SignedPowerShellRunner
{
    private readonly SignedAssetCatalog catalog;

    public SignedPowerShellRunner(SignedAssetCatalog catalog)
    {
        this.catalog = catalog;
    }

    public async Task<int> RunAsync(
        BrokerOperation operation,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var windowsRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var executable = Path.Combine(
            windowsRoot,
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var fixedArgument in new[]
                 {
                     "-NoLogo",
                     "-NoProfile",
                     "-NonInteractive",
                     "-ExecutionPolicy",
                     "AllSigned",
                     "-File",
                     catalog.GetVerifiedPath(operation),
                 })
        {
            startInfo.ArgumentList.Add(fixedArgument);
        }
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("The packaged action could not start.");
        var discardedOutput = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var discardedError = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        await Task.WhenAll(discardedOutput, discardedError);
        return process.ExitCode;
    }
}
