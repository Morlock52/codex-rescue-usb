using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed partial class SupportBundleExporter
{
    public async Task ExportAsync(
        IEnumerable<string> inputPaths,
        string outputPath,
        CancellationToken cancellationToken)
    {
        var receipts = new List<object>();
        var verifications = new List<object>();
        foreach (var path in inputPaths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var json = await File.ReadAllTextAsync(path, cancellationToken);
            RejectRecoveryMaterial(json);
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.TryGetProperty("ActionId", out _))
            {
                receipts.Add(ReadReceipt(json));
            }
            else if (root.TryGetProperty("VerificationSucceeded", out _))
            {
                verifications.Add(ReadVerification(root));
            }
            else
            {
                throw new InvalidDataException("Support input is not a supported action receipt or ISO verification report.");
            }
        }

        var summary = new
        {
            SchemaVersion = 1,
            CreatedAtUtc = DateTimeOffset.UtcNow,
            PrivacyDeclaration = "Sanitized support summary excludes raw evidence, device and tenant identifiers, filenames, command output, prompts, credentials, and recovery material.",
            Receipts = receipts,
            VerificationReports = verifications,
        };
        var bytes = JsonSerializer.SerializeToUtf8Bytes(summary, new JsonSerializerOptions { WriteIndented = true });
        RejectRecoveryMaterial(System.Text.Encoding.UTF8.GetString(bytes));

        await using var output = new FileStream(
            Path.GetFullPath(outputPath),
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None);
        using var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true);
        var entry = archive.CreateEntry("support-summary.json", CompressionLevel.Optimal);
        await using var entryStream = entry.Open();
        await entryStream.WriteAsync(bytes, cancellationToken);
    }

    private static object ReadReceipt(string json)
    {
        var receipt = JsonSerializer.Deserialize<ActionReceiptV1>(json)
            ?? throw new InvalidDataException("Action receipt is empty.");
        if (receipt.SchemaVersion != ActionReceiptV1.SupportedSchemaVersion ||
            !SafeToken().IsMatch(receipt.Result) ||
            !SafeToken().IsMatch(receipt.NormalizedErrorCode) ||
            !SafeToken().IsMatch(receipt.RestartState))
        {
            throw new InvalidDataException("Action receipt contains an unsupported schema or result category.");
        }

        return new
        {
            receipt.SchemaVersion,
            receipt.ActionId,
            receipt.Result,
            receipt.NormalizedErrorCode,
            BeforeEvidenceFieldCount = receipt.BeforeEvidence.Count,
            AfterEvidenceFieldCount = receipt.AfterEvidence.Count,
            ChangeCount = receipt.ChangesMade.Count,
            receipt.RestartState,
            receipt.CompletedAtUtc,
        };
    }

    private static object ReadVerification(JsonElement root)
    {
        if (RequiredInt(root, "SchemaVersion") != 1 ||
            !RequiredBoolean(root, "VerificationSucceeded") ||
            RequiredBoolean(root, "ContainsRecoveryMaterial"))
        {
            throw new InvalidDataException("ISO verification report is not a successful secret-free schema-v1 result.");
        }

        return new
        {
            SchemaVersion = 1,
            ArtifactId = RequiredSafeString(root, "ArtifactId"),
            Architecture = RequiredSafeString(root, "Architecture"),
            TrustPath = RequiredSafeString(root, "TrustPath"),
            IsoSha256 = RequiredHash(root, "IsoSha256"),
            VerificationSucceeded = true,
            ContainsRecoveryMaterial = false,
        };
    }

    private static void RejectRecoveryMaterial(string value)
    {
        if (RecoveryPassword().IsMatch(value) || RecoveryFile().IsMatch(value))
        {
            throw new InvalidDataException("Support input contains possible recovery material.");
        }
    }

    private static int RequiredInt(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.TryGetInt32(out var result)
            ? result
            : throw new InvalidDataException($"Verification report lacks {name}.");

    private static bool RequiredBoolean(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : throw new InvalidDataException($"Verification report lacks {name}.");

    private static string RequiredSafeString(JsonElement root, string name)
    {
        var value = root.TryGetProperty(name, out var property) ? property.GetString() : null;
        return value is not null && SafeToken().IsMatch(value)
            ? value
            : throw new InvalidDataException($"Verification report has an unsafe {name}.");
    }

    private static string RequiredHash(JsonElement root, string name)
    {
        var value = root.TryGetProperty(name, out var property) ? property.GetString() : null;
        return value is not null && Hash().IsMatch(value)
            ? value.ToUpperInvariant()
            : throw new InvalidDataException($"Verification report has an invalid {name}.");
    }

    [GeneratedRegex("^[A-Za-z0-9_.:-]{1,80}$", RegexOptions.CultureInvariant)]
    private static partial Regex SafeToken();

    [GeneratedRegex("^[A-Fa-f0-9]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Hash();

    [GeneratedRegex(@"(?<!\d)(?:\d{6}-){7}\d{6}(?!\d)", RegexOptions.CultureInvariant)]
    private static partial Regex RecoveryPassword();

    [GeneratedRegex("(?i)\\.(?:bek|kpg)(?:[\\\"'\\s,}]|$)", RegexOptions.CultureInvariant)]
    private static partial Regex RecoveryFile();
}
