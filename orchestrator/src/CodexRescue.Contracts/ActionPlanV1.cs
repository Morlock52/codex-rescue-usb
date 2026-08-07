namespace CodexRescue.Contracts;

public sealed record ActionPlanV1(
    int SchemaVersion,
    Guid ActionId,
    string ActionType,
    string PackageVersion,
    IReadOnlyList<string> TargetFingerprints,
    IReadOnlyList<string> Prerequisites,
    IReadOnlyList<string> RollbackRequirements,
    string ConfirmationPhrase,
    DateTimeOffset ExpiresAtUtc,
    string ManifestDigest)
{
    public const int SupportedSchemaVersion = 1;
}
