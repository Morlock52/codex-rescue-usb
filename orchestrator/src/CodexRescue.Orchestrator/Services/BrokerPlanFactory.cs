using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class BrokerPlanFactory
{
    private static readonly IReadOnlySet<string> AllowedActions = new HashSet<string>(
        ["ApplyToolchain", "BuildMedia", "WriteUsb", "RepairUefi", "SalvageBitLocker"],
        StringComparer.Ordinal);

    public ActionPlanV1 Create(
        string actionType,
        IReadOnlyList<string> targetFingerprints,
        IReadOnlyList<string> prerequisites,
        IReadOnlyList<string> rollbackRequirements,
        string confirmationPhrase)
    {
        if (!AllowedActions.Contains(actionType) ||
            targetFingerprints.Count == 0 ||
            targetFingerprints.Any(string.IsNullOrWhiteSpace) ||
            string.IsNullOrWhiteSpace(confirmationPhrase))
        {
            throw new InvalidDataException("The action, target fingerprints, and confirmation phrase are required.");
        }

        var catalogPath = Path.Combine(
            AppContext.BaseDirectory,
            "Broker",
            "Assets",
            "assets-manifest.json");
        var catalogBytes = File.ReadAllBytes(catalogPath);
        using var document = JsonDocument.Parse(catalogBytes);
        var packageVersion = document.RootElement.GetProperty("PackageVersion").GetString();
        if (string.IsNullOrWhiteSpace(packageVersion))
        {
            throw new InvalidDataException("The packaged asset catalog has no package version.");
        }

        return new ActionPlanV1(
            ActionPlanV1.SupportedSchemaVersion,
            Guid.NewGuid(),
            actionType,
            packageVersion,
            TargetFingerprints: targetFingerprints,
            Prerequisites: prerequisites,
            RollbackRequirements: rollbackRequirements,
            ConfirmationPhrase: confirmationPhrase,
            ExpiresAtUtc: DateTimeOffset.UtcNow.Add(TimeSpan.FromMinutes(10)),
            ManifestDigest: Convert.ToHexString(SHA256.HashData(catalogBytes)));
    }

    public static string Fingerprint(string category, string value)
    {
        if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Fingerprint category and value are required.");
        }

        return $"{category}:{Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)))}";
    }
}
