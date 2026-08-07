using CodexRescue.Contracts;

namespace CodexRescue.Broker;

public sealed class SignedPowerShellAction : IBrokerAction
{
    private const string PrivacyDeclaration =
        "Receipt excludes credentials, recovery material, command output, filenames, and device identifiers.";
    private readonly BrokerOperation operation;
    private readonly BrokerRequestV1 request;
    private readonly SignedPowerShellRunner runner;

    public SignedPowerShellAction(
        BrokerOperation operation,
        BrokerRequestV1 request,
        SignedPowerShellRunner runner)
    {
        this.operation = operation;
        this.request = request;
        this.runner = runner;
    }

    public async Task<ActionReceiptV1> ExecuteAsync(
        ActionPlanV1 plan,
        CancellationToken cancellationToken)
    {
        var arguments = BuildArguments(plan);
        var exitCode = await runner.RunAsync(operation, arguments, cancellationToken);
        var succeeded = exitCode == 0;
        return new ActionReceiptV1(
            1,
            plan.ActionId,
            succeeded ? "Succeeded" : "Blocked",
            succeeded ? "NONE" : $"PACKAGED_ACTION_EXIT_{exitCode}",
            new Dictionary<string, string>
            {
                ["PlanManifestDigest"] = plan.ManifestDigest,
            },
            new Dictionary<string, string>
            {
                ["PackagedActionVerified"] = succeeded.ToString(),
            },
            succeeded ? [operation.ToString()] : Array.Empty<string>(),
            operation == BrokerOperation.RepairUefi ? "RequiredForBootTest" : "NotRequired",
            PrivacyDeclaration,
            DateTimeOffset.UtcNow);
    }

    private IReadOnlyList<string> BuildArguments(ActionPlanV1 plan)
    {
        return operation switch
        {
            BrokerOperation.ApplyToolchain => BuildToolchainArguments(plan),
            BrokerOperation.BuildMedia => BuildMediaArguments(),
            BrokerOperation.WriteUsb => BuildUsbArguments(plan),
            BrokerOperation.RepairUefi => BuildUefiArguments(plan),
            BrokerOperation.SalvageBitLocker => BuildSalvageArguments(plan),
            _ => throw new InvalidOperationException("Operation is not backed by a packaged PowerShell action."),
        };
    }

    private IReadOnlyList<string> BuildToolchainArguments(ActionPlanV1 plan)
    {
        var input = request.ApplyToolchain
            ?? throw new InvalidDataException("Toolchain input is required.");
        if (!input.PackageAgreementsApproved || !Path.IsPathFullyQualified(input.ReceiptDirectory))
        {
            throw new InvalidDataException("Toolchain agreements and an absolute receipt directory are required.");
        }
        return
        [
            "-Mode", "Apply",
            "-ConfirmationToken", plan.ConfirmationPhrase,
            "-PackageAgreementsApproved",
            "-ReceiptDirectory", input.ReceiptDirectory,
            "-AsJson",
        ];
    }

    private IReadOnlyList<string> BuildMediaArguments()
    {
        var input = request.BuildMedia ?? throw new InvalidDataException("Media-build input is required.");
        RequireAbsolutePaths(input.ServicingReceiptPath, input.OutputDirectory);
        var arguments = new List<string>
        {
            "-ServicingReceiptPath", input.ServicingReceiptPath,
            "-OutputDirectory", input.OutputDirectory,
        };
        if (input.ArtifactIds.Count > 0)
        {
            arguments.Add("-ArtifactId");
            foreach (var artifact in input.ArtifactIds)
            {
                if (artifact is not ("x64-2023CA" or "x64-2011CA" or "arm64-2023CA" or "arm64-2011CA"))
                {
                    throw new InvalidDataException("Media artifact is not allowlisted.");
                }
                arguments.Add(artifact);
            }
        }
        if (input.Force)
        {
            arguments.Add("-Force");
        }
        return arguments;
    }

    private IReadOnlyList<string> BuildUsbArguments(ActionPlanV1 plan)
    {
        var input = request.WriteUsb ?? throw new InvalidDataException("USB-write input is required.");
        RequireAbsolutePaths(input.IsoPath, input.VerificationPath, input.OutputReceiptPath);
        return
        [
            "-Mode", "Apply",
            "-IsoPath", input.IsoPath,
            "-VerificationPath", input.VerificationPath,
            "-DiskNumber", input.DiskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "-ConfirmationPhrase", plan.ConfirmationPhrase,
            "-OutputReceiptPath", input.OutputReceiptPath,
        ];
    }

    private IReadOnlyList<string> BuildUefiArguments(ActionPlanV1 plan)
    {
        var input = request.RepairUefi ?? throw new InvalidDataException("UEFI-repair input is required.");
        if (input.Mode is not ("Prepare" or "Apply" or "Rollback"))
        {
            throw new InvalidDataException("UEFI mode is not allowlisted.");
        }
        RequireAbsolutePaths(input.OutputReceiptPath);
        var arguments = new List<string> { "-Mode", input.Mode };
        if (input.Mode == "Prepare")
        {
            if (input.BackupDirectory is null) { throw new InvalidDataException("Backup directory is required."); }
            RequireAbsolutePaths(input.BackupDirectory);
            arguments.AddRange(["-BackupDirectory", input.BackupDirectory]);
        }
        else
        {
            if (input.PlanPath is null) { throw new InvalidDataException("Prepared plan is required."); }
            RequireAbsolutePaths(input.PlanPath);
            arguments.AddRange(["-PlanPath", input.PlanPath, "-ConfirmationPhrase", plan.ConfirmationPhrase]);
        }
        arguments.AddRange(["-OutputReceiptPath", input.OutputReceiptPath]);
        return arguments;
    }

    private IReadOnlyList<string> BuildSalvageArguments(ActionPlanV1 plan)
    {
        var input = request.SalvageBitLocker
            ?? throw new InvalidDataException("BitLocker-salvage input is required.");
        RequireAbsolutePaths(input.RecoveryMaterialDirectory, input.OutputReceiptPath);
        return
        [
            "-Mode", "Apply",
            "-SourceDiskNumber", input.SourceDiskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "-OutputDiskNumber", input.OutputDiskNumber.ToString(System.Globalization.CultureInfo.InvariantCulture),
            "-SourceDrive", input.SourceDrive,
            "-OutputDrive", input.OutputDrive,
            "-RecoveryMaterialDirectory", input.RecoveryMaterialDirectory,
            "-KnownMarkerRelativePath", input.KnownMarkerRelativePath,
            "-KnownMarkerSha256", input.KnownMarkerSha256,
            "-ConfirmationPhrase", plan.ConfirmationPhrase,
            "-OutputReceiptPath", input.OutputReceiptPath,
        ];
    }

    private static void RequireAbsolutePaths(params string[] paths)
    {
        if (paths.Any(path => string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path)))
        {
            throw new InvalidDataException("Packaged actions require absolute data paths.");
        }
    }
}
