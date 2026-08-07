using System.Security.Cryptography;
using System.Text;
using CodexRescue.Contracts;

namespace CodexRescue.Broker;

public sealed class PlanValidator
{
    public BrokerOperation ValidateForExecution(
        ActionPlanV1 plan,
        string expectedPackageVersion,
        string expectedManifestDigest,
        DateTimeOffset nowUtc)
    {
        ArgumentNullException.ThrowIfNull(plan);

        if (plan.SchemaVersion != ActionPlanV1.SupportedSchemaVersion)
        {
            throw new InvalidDataException("Unsupported action-plan schema.");
        }

        if (plan.ActionId == Guid.Empty || plan.ExpiresAtUtc <= nowUtc)
        {
            throw new InvalidDataException("Action plan is missing an identity or has expired.");
        }

        if (!FixedEquals(plan.PackageVersion, expectedPackageVersion) ||
            !FixedEquals(plan.ManifestDigest, expectedManifestDigest))
        {
            throw new InvalidDataException("Package version or ManifestDigest does not match.");
        }

        if (plan.TargetFingerprints.Count == 0 ||
            plan.TargetFingerprints.Any(string.IsNullOrWhiteSpace))
        {
            throw new InvalidDataException("Stable target fingerprints are required.");
        }

        if (string.IsNullOrWhiteSpace(plan.ConfirmationPhrase))
        {
            throw new InvalidDataException("A target-bound confirmation phrase is required.");
        }

        if (!Enum.TryParse<BrokerOperation>(plan.ActionType, false, out var operation))
        {
            throw new InvalidDataException("Action type is not allowlisted.");
        }

        return operation;
    }

    private static bool FixedEquals(string left, string right)
    {
        var leftBytes = SHA256.HashData(Encoding.UTF8.GetBytes(left ?? string.Empty));
        var rightBytes = SHA256.HashData(Encoding.UTF8.GetBytes(right ?? string.Empty));
        return CryptographicOperations.FixedTimeEquals(leftBytes, rightBytes);
    }
}
