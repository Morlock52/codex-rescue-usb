using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace CodexRescue.Orchestrator.Services;

public enum ReadOnlyPlanOperation
{
    Toolchain,
    WriteUsb,
    SalvageBitLocker,
}

public sealed class PackagedPlanRunner
{
    private static readonly IReadOnlyDictionary<ReadOnlyPlanOperation, (string Operation, string FileName)> FixedAssets =
        new Dictionary<ReadOnlyPlanOperation, (string, string)>
        {
            [ReadOnlyPlanOperation.Toolchain] = ("ApplyToolchain", "scripts/Install-TechnicianWorkspaceToolchain.ps1"),
            [ReadOnlyPlanOperation.WriteUsb] = ("WriteUsb", "scripts/Write-CodexRescueUsb.ps1"),
            [ReadOnlyPlanOperation.SalvageBitLocker] = ("SalvageBitLocker", "scripts/Invoke-CodexRescueBitLockerSalvage.ps1"),
        };

    private readonly PackagedBrokerVerifier verifier = new();

    public async Task<JsonElement> RunAsync(
        ReadOnlyPlanOperation operation,
        IReadOnlyList<string> dataArguments,
        CancellationToken cancellationToken)
    {
        var scriptPath = GetVerifiedScript(operation);
        var powershell = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32",
            "WindowsPowerShell",
            "v1.0",
            "powershell.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = powershell,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in new[]
                 {
                     "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "AllSigned",
                     "-File", scriptPath,
                 })
        {
            startInfo.ArgumentList.Add(argument);
        }
        foreach (var argument in dataArguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("The packaged read-only plan could not start.");
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var discardedErrorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        var output = await outputTask;
        _ = await discardedErrorTask;
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"The signed plan was blocked with normalized exit code {process.ExitCode}.");
        }

        using var document = JsonDocument.Parse(output);
        return document.RootElement.Clone();
    }

    private string GetVerifiedScript(ReadOnlyPlanOperation operation)
    {
        if (!FixedAssets.TryGetValue(operation, out var expected))
        {
            throw new InvalidDataException("Read-only plan operation is not allowlisted.");
        }

        var assetsRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "Broker", "Assets"));
        var manifestPath = Path.Combine(assetsRoot, "assets-manifest.json");
        using var document = JsonDocument.Parse(File.ReadAllBytes(manifestPath));
        var matches = document.RootElement.GetProperty("Assets").EnumerateArray().Where(asset =>
            string.Equals(asset.GetProperty("Operation").GetString(), expected.Operation, StringComparison.Ordinal) &&
            string.Equals(asset.GetProperty("FileName").GetString(), expected.FileName, StringComparison.Ordinal)).ToArray();
        if (matches.Length != 1)
        {
            throw new InvalidDataException("The fixed plan asset is missing or duplicated.");
        }

        var scriptPath = Path.GetFullPath(Path.Combine(
            assetsRoot,
            expected.FileName.Replace('/', Path.DirectorySeparatorChar)));
        var rootPrefix = assetsRoot + Path.DirectorySeparatorChar;
        if (!scriptPath.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) || !File.Exists(scriptPath))
        {
            throw new InvalidDataException("The fixed plan asset escaped the package or is missing.");
        }

        var expectedHash = Convert.FromHexString(matches[0].GetProperty("Sha256").GetString()
            ?? throw new InvalidDataException("The fixed plan asset hash is missing."));
        var actualHash = SHA256.HashData(File.ReadAllBytes(scriptPath));
        if (!CryptographicOperations.FixedTimeEquals(expectedHash, actualHash))
        {
            throw new CryptographicException("The fixed plan asset hash changed.");
        }

        verifier.Verify(scriptPath);
        return scriptPath;
    }
}
