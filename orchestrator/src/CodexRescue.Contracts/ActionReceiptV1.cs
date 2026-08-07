namespace CodexRescue.Contracts;

public sealed record ActionReceiptV1(
    int SchemaVersion,
    Guid ActionId,
    string Result,
    string NormalizedErrorCode,
    IReadOnlyDictionary<string, string> BeforeEvidence,
    IReadOnlyDictionary<string, string> AfterEvidence,
    IReadOnlyList<string> ChangesMade,
    string RestartState,
    string PrivacyDeclaration,
    DateTimeOffset CompletedAtUtc)
{
    public const int SupportedSchemaVersion = 1;
}
