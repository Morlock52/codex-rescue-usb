using System.IO.Compression;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class OfflineBundleImporter
{
    private readonly SignedReleaseVerifier _verifier;
    private readonly ReleaseCacheManager _cache;
    private readonly string _expectedPublisherIdentity;

    public OfflineBundleImporter(
        SignedReleaseVerifier verifier,
        ReleaseCacheManager cache,
        string expectedPublisherIdentity)
    {
        _verifier = verifier;
        _cache = cache;
        _expectedPublisherIdentity = expectedPublisherIdentity;
    }

    public async Task<string> ImportAsync(string bundlePath, CancellationToken cancellationToken)
    {
        if (!string.Equals(Path.GetExtension(bundlePath), ".zip", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("An offline update must be a ZIP bundle.");
        }

        var stagingDirectory = Path.Combine(Path.GetTempPath(), $"CodexRescueUpdate-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stagingDirectory);

        try
        {
            var stagingRoot = Path.GetFullPath(stagingDirectory) + Path.DirectorySeparatorChar;
            using (var archive = ZipFile.OpenRead(bundlePath))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var destination = Path.GetFullPath(Path.Combine(stagingRoot, entry.FullName));
                    if (!destination.StartsWith(stagingRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("Offline bundle entry escapes the staging directory.");
                    }

                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(destination);
                        continue;
                    }

                    Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                    entry.ExtractToFile(destination, overwrite: false);
                }
            }

            var manifestPath = Path.Combine(stagingDirectory, "release-manifest.json");
            var signaturePath = Path.Combine(stagingDirectory, "release-manifest.json.p7");
            var manifestBytes = await File.ReadAllBytesAsync(manifestPath, cancellationToken);
            var signatureBytes = await File.ReadAllBytesAsync(signaturePath, cancellationToken);
            var verified = await _verifier.VerifyAsync(
                manifestBytes,
                signatureBytes,
                stagingDirectory,
                _expectedPublisherIdentity,
                requireTrustedChain: true,
                cancellationToken);

            _ = JsonSerializer.Deserialize<ReleaseManifestV1>(manifestBytes)
                ?? throw new InvalidDataException("Offline release manifest is empty.");
            return _cache.PromoteVerifiedBundle(stagingDirectory, verified.Manifest.Version);
        }
        catch
        {
            if (Directory.Exists(stagingDirectory))
            {
                Directory.Delete(stagingDirectory, recursive: true);
            }

            throw;
        }
    }
}
