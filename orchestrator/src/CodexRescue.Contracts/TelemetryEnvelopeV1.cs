namespace CodexRescue.Contracts;

public sealed record TelemetryEnvelopeV1(
    int SchemaVersion,
    string EventName,
    string AppVersion,
    string ActionStage,
    string ResultCategory,
    string Architecture,
    string DurationBucket,
    DateTimeOffset RecordedAtUtc)
{
    public const int SupportedSchemaVersion = 1;
}
