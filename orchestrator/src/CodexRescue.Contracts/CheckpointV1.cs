namespace CodexRescue.Contracts;

public sealed record CheckpointV1(
    int SchemaVersion,
    Guid WorkflowId,
    string StateName,
    DateTimeOffset SavedAtUtc,
    IReadOnlyDictionary<string, string> NonSecretState,
    string Hmac)
{
    public const int SupportedSchemaVersion = 1;
}
