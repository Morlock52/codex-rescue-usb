using System.IO.Compression;
using System.Text.Json;
using CodexRescue.Contracts;
using CodexRescue.Orchestrator.Services;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class SupportBundleExporterTests
{
    [TestMethod]
    public async Task ExportAsync_WritesOnlySanitizedReceiptSummary()
    {
        var root = Directory.CreateTempSubdirectory("codex-rescue-support-");
        try
        {
            var receiptPath = Path.Combine(root.FullName, "receipt.json");
            var bundlePath = Path.Combine(root.FullName, "support.zip");
            var receipt = new ActionReceiptV1(
                ActionReceiptV1.SupportedSchemaVersion,
                Guid.NewGuid(),
                "Succeeded",
                "None",
                new Dictionary<string, string> { ["private-source-path"] = @"C:\Users\Operator\Desktop" },
                new Dictionary<string, string> { ["device-name"] = "WORKSTATION-SECRET" },
                ["Changed a private boot path"],
                "NotRequired",
                "Sensitive details stay local.",
                DateTimeOffset.UtcNow);
            await File.WriteAllTextAsync(receiptPath, JsonSerializer.Serialize(receipt));

            await new SupportBundleExporter().ExportAsync([receiptPath], bundlePath, CancellationToken.None);

            using var archive = ZipFile.OpenRead(bundlePath);
            Assert.AreEqual(1, archive.Entries.Count);
            using var reader = new StreamReader(archive.GetEntry("support-summary.json")!.Open());
            var summary = await reader.ReadToEndAsync();
            StringAssert.Contains(summary, "BeforeEvidenceFieldCount");
            StringAssert.Contains(summary, "AfterEvidenceFieldCount");
            Assert.IsFalse(summary.Contains("WORKSTATION-SECRET", StringComparison.Ordinal));
            Assert.IsFalse(summary.Contains("Operator", StringComparison.Ordinal));
            Assert.IsFalse(summary.Contains("private-source-path", StringComparison.Ordinal));
        }
        finally
        {
            root.Delete(recursive: true);
        }
    }

    [TestMethod]
    public async Task ExportAsync_RejectsRecoveryPasswordMaterial()
    {
        var root = Directory.CreateTempSubdirectory("codex-rescue-support-");
        try
        {
            var receiptPath = Path.Combine(root.FullName, "receipt.json");
            var bundlePath = Path.Combine(root.FullName, "support.zip");
            await File.WriteAllTextAsync(
                receiptPath,
                "{\"ActionId\":\"00000000-0000-0000-0000-000000000000\",\"note\":\"111111-222222-333333-444444-555555-666666-777777-888888\"}");

            await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
                new SupportBundleExporter().ExportAsync([receiptPath], bundlePath, CancellationToken.None));
            Assert.IsFalse(File.Exists(bundlePath));
        }
        finally
        {
            root.Delete(recursive: true);
        }
    }
}
