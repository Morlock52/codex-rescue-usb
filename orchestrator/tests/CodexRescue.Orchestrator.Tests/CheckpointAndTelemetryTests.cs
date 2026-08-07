using CodexRescue.Contracts;
using CodexRescue.Orchestrator.Services;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class CheckpointAndTelemetryTests
{
    [TestMethod]
    public void CheckpointTamperingIsRejected()
    {
        using var directory = new TemporaryDirectory();
        var protector = new CheckpointProtector(directory.Path);
        var checkpoint = protector.Seal(new CheckpointV1(
            1,
            Guid.NewGuid(),
            "Verifying",
            DateTimeOffset.UtcNow,
            new Dictionary<string, string> { ["Artifact"] = "x64-2023CA" },
            string.Empty));

        Assert.IsTrue(protector.Verify(checkpoint));
        Assert.IsFalse(protector.Verify(checkpoint with { StateName = "Completed" }));
    }

    [TestMethod]
    public void SecretLikeCheckpointStateIsRejected()
    {
        using var directory = new TemporaryDirectory();
        var protector = new CheckpointProtector(directory.Path);
        var checkpoint = new CheckpointV1(
            1,
            Guid.NewGuid(),
            "PlanReady",
            DateTimeOffset.UtcNow,
            new Dictionary<string, string> { ["RecoveryKey"] = "redacted" },
            string.Empty);

        Assert.ThrowsExactly<InvalidDataException>(() => protector.Seal(checkpoint));
    }

    [TestMethod]
    public void CheckpointStorePersistsAndVerifiesResumableState()
    {
        using var directory = new TemporaryDirectory();
        var store = new CheckpointStore(directory.Path);
        var checkpoint = new CheckpointV1(
            1,
            Guid.NewGuid(),
            "RestartRequired",
            DateTimeOffset.UtcNow,
            new Dictionary<string, string> { ["ActionType"] = "RepairUefi" },
            string.Empty);

        store.Save(checkpoint);
        var loaded = store.Load();

        Assert.IsNotNull(loaded);
        Assert.AreEqual(checkpoint.WorkflowId, loaded.WorkflowId);
        Assert.AreEqual("RestartRequired", loaded.StateName);
    }

    [TestMethod]
    public void CheckpointStoreRejectsTamperedSavedState()
    {
        using var directory = new TemporaryDirectory();
        var store = new CheckpointStore(directory.Path);
        store.Save(new CheckpointV1(
            1,
            Guid.NewGuid(),
            "RestartRequired",
            DateTimeOffset.UtcNow,
            new Dictionary<string, string> { ["ActionType"] = "RepairUefi" },
            string.Empty));
        var path = System.IO.Path.Combine(directory.Path, "checkpoint.v1.json");
        File.WriteAllText(path, File.ReadAllText(path).Replace("RestartRequired", "Completed", StringComparison.Ordinal));

        Assert.ThrowsExactly<InvalidDataException>(() => store.Load());
    }

    [TestMethod]
    public void TelemetryRequiresPolicyAndConsent()
    {
        var envelope = new TelemetryEnvelopeV1(
            1,
            "audit.completed",
            "0.1.0",
            "verify",
            "success",
            "x64",
            "1-10s",
            DateTimeOffset.UtcNow);

        Assert.IsFalse(new TelemetryPolicy().CanTransmit(envelope));
        Assert.IsFalse(new TelemetryPolicy
        {
            AdministratorPolicyAllows = true,
        }.CanTransmit(envelope));
        Assert.IsTrue(new TelemetryPolicy
        {
            AdministratorPolicyAllows = true,
            OperatorConsent = true,
        }.CanTransmit(envelope));
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"CodexRescueTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose() => Directory.Delete(Path, recursive: true);
    }
}
