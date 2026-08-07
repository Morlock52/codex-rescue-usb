namespace CodexRescue.Contracts;

public sealed record ProxmoxResourceLimitsV1(
    int CpuCores,
    int MemoryMegabytes,
    int DiskGigabytes,
    int MaximumRunMinutes);

public sealed record ProxmoxProfileV1(
    int SchemaVersion,
    Uri Endpoint,
    string CertificateFingerprint,
    ProxmoxResourceLimitsV1 ResourceLimits,
    string CredentialStoragePolicy)
{
    public const int SupportedSchemaVersion = 1;
}
