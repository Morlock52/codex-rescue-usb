using CodexRescue.Orchestrator.Services;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class MaintenanceAndCacheTests
{
    [TestMethod]
    public void MaintenanceWindowNeedsConsentAndExpires()
    {
        var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-08-05T12:00:00Z"));
        var service = new MaintenanceWindowService(clock);

        Assert.ThrowsExactly<InvalidOperationException>(() => service.Open(NetworkConsent: false));
        service.Open(NetworkConsent: true);
        Assert.IsTrue(service.RequireOpen().NetworkConsent);

        clock.Advance(TimeSpan.FromMinutes(31));
        Assert.ThrowsExactly<InvalidOperationException>(service.RequireOpen);
    }

    [TestMethod]
    public void ReleaseCacheRefusesDowngradeAndRetainsCurrentPlusNMinusOne()
    {
        using var directory = new TemporaryDirectory();
        var cache = new ReleaseCacheManager(Path.Combine(directory.Path, "cache"));
        cache.PromoteVerifiedBundle(NewStaging(directory.Path, "one"), "1.0.0");
        cache.PromoteVerifiedBundle(NewStaging(directory.Path, "two"), "1.1.0");
        cache.PromoteVerifiedBundle(NewStaging(directory.Path, "three"), "1.2.0");

        CollectionAssert.AreEquivalent(
            new[] { "1.1.0", "1.2.0" },
            Directory.GetDirectories(Path.Combine(directory.Path, "cache"))
                .Select(Path.GetFileName)
                .ToArray());
        Assert.AreEqual(new Version(1, 1, 0), cache.GetRollbackCandidate().Version);
        Assert.ThrowsExactly<InvalidOperationException>(() =>
            cache.PromoteVerifiedBundle(NewStaging(directory.Path, "old"), "1.0.0"));
    }

    private static string NewStaging(string root, string name)
    {
        var path = Path.Combine(root, name);
        Directory.CreateDirectory(path);
        File.WriteAllText(Path.Combine(path, "release-manifest.json"), "verified test bundle");
        return path;
    }

    private sealed class ManualTimeProvider(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset _now = now;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now = _now.Add(duration);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"CodexRescueUpdateTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }
        public void Dispose() => Directory.Delete(Path, recursive: true);
    }
}
