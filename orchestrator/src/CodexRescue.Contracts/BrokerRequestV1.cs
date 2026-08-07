namespace CodexRescue.Contracts;

public sealed record ToolchainApplyInputV1(
    bool PackageAgreementsApproved,
    string ReceiptDirectory);

public sealed record MediaBuildInputV1(
    string ServicingReceiptPath,
    string OutputDirectory,
    IReadOnlyList<string> ArtifactIds,
    bool Force);

public sealed record UsbWriteInputV1(
    string IsoPath,
    string VerificationPath,
    int DiskNumber,
    string OutputReceiptPath);

public sealed record UefiRepairInputV1(
    string Mode,
    string? BackupDirectory,
    string? PlanPath,
    string OutputReceiptPath);

public sealed record BitLockerSalvageInputV1(
    int SourceDiskNumber,
    int OutputDiskNumber,
    string SourceDrive,
    string OutputDrive,
    string RecoveryMaterialDirectory,
    string KnownMarkerRelativePath,
    string KnownMarkerSha256,
    string OutputReceiptPath);

public sealed record BrokerRequestV1(
    int SchemaVersion,
    ActionPlanV1 Plan,
    ToolchainApplyInputV1? ApplyToolchain,
    MediaBuildInputV1? BuildMedia,
    UsbWriteInputV1? WriteUsb,
    UefiRepairInputV1? RepairUefi,
    BitLockerSalvageInputV1? SalvageBitLocker)
{
    public const int SupportedSchemaVersion = 1;
}
