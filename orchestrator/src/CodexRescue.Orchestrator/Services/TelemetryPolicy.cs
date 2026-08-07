using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class TelemetryPolicy
{
    public const bool EnabledByDefault = false;

    public static readonly IReadOnlySet<string> AllowedEventNames = new HashSet<string>(
        [
            "audit.completed",
            "update.completed",
            "build.completed",
            "proxmox-test.completed",
            "usb-write.completed",
            "uefi-repair.completed",
            "bitlocker-salvage.completed",
            "support-export.completed",
            "endpoint.tested",
        ],
        StringComparer.Ordinal);

    public bool AdministratorPolicyAllows { get; init; }

    public bool OperatorConsent { get; init; }

    public bool CanTransmit(TelemetryEnvelopeV1 envelope)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        return AdministratorPolicyAllows &&
               OperatorConsent &&
               envelope.SchemaVersion == TelemetryEnvelopeV1.SupportedSchemaVersion &&
               AllowedEventNames.Contains(envelope.EventName) &&
               IsDurationBucketAllowed(envelope.DurationBucket);
    }

    private static bool IsDurationBucketAllowed(string value) => value is
        "under-1s" or "1-10s" or "10-60s" or "1-5m" or "5-30m" or "over-30m";
}
