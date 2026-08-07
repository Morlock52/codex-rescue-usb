namespace CodexRescue.Contracts;

public sealed record ReleaseArtifactV1(
    string Name,
    string Architecture,
    string Sha256,
    long SizeBytes);

public sealed record ReleaseManifestV1(
    int SchemaVersion,
    string Version,
    string Architecture,
    IReadOnlyList<ReleaseArtifactV1> Artifacts,
    string PublisherIdentity,
    string MinimumOsVersion,
    string RollbackPackage,
    DateTimeOffset PublishedAtUtc)
{
    public const int SupportedSchemaVersion = 1;
}
