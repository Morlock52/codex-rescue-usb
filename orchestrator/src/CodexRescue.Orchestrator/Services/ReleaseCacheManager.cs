namespace CodexRescue.Orchestrator.Services;

public sealed record CachedRelease(Version Version, string Directory);

public sealed class ReleaseCacheManager
{
    private readonly string _cacheRoot;

    public ReleaseCacheManager(string cacheRoot)
    {
        _cacheRoot = Path.GetFullPath(cacheRoot);
        Directory.CreateDirectory(_cacheRoot);
    }

    public string PromoteVerifiedBundle(string stagingDirectory, string version)
    {
        if (!Version.TryParse(version, out var incomingVersion))
        {
            throw new InvalidDataException("Release version is not a supported numeric version.");
        }

        var existing = GetVersionDirectories().ToArray();
        var current = existing.FirstOrDefault();
        if (current.Version is not null && incomingVersion <= current.Version)
        {
            throw new InvalidOperationException("Update refused because it is a downgrade or duplicate version.");
        }

        var destination = Path.Combine(_cacheRoot, incomingVersion.ToString());
        if (Directory.Exists(destination))
        {
            throw new IOException("The verified release cache destination already exists.");
        }

        Directory.Move(Path.GetFullPath(stagingDirectory), destination);

        // Retain only the current release and N-1 rollback package.
        foreach (var stale in GetVersionDirectories().OrderByDescending(item => item.Version).Skip(2))
        {
            Directory.Delete(stale.Path, recursive: true);
        }

        return destination;
    }

    public CachedRelease GetRollbackCandidate()
    {
        var versions = GetVersionDirectories().Take(2).ToArray();
        if (versions.Length != 2)
        {
            throw new InvalidOperationException("A verified N-1 rollback package is not available.");
        }
        var rollback = versions[1];
        var rollbackVersion = rollback.Version
            ?? throw new InvalidOperationException("The N-1 rollback version is invalid.");

        return new CachedRelease(rollbackVersion, rollback.Path);
    }

    private IEnumerable<(Version? Version, string Path)> GetVersionDirectories() =>
        Directory.EnumerateDirectories(_cacheRoot)
            .Select(path => (Version.TryParse(Path.GetFileName(path), out var version) ? version : null, path))
            .Where(item => item.Item1 is not null)
            .OrderByDescending(item => item.Item1);
}
