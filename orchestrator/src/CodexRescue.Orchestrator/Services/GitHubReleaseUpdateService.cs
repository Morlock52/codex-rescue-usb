using System.Net.Http.Json;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class GitHubReleaseUpdateService
{
    private const string LatestReleaseApi =
        "https://api.github.com/repos/Morlock52/codex-rescue-usb/releases/latest";
    private readonly HttpClient _httpClient;
    private readonly MaintenanceWindowService _maintenance;
    private readonly SignedReleaseVerifier _verifier;
    private readonly ReleaseCacheManager _cache;
    private readonly string _expectedPublisherIdentity;

    public GitHubReleaseUpdateService(
        HttpClient httpClient,
        MaintenanceWindowService maintenance,
        SignedReleaseVerifier verifier,
        ReleaseCacheManager cache,
        string expectedPublisherIdentity)
    {
        _httpClient = httpClient;
        _maintenance = maintenance;
        _verifier = verifier;
        _cache = cache;
        _expectedPublisherIdentity = expectedPublisherIdentity;
    }

    public async Task<string> DownloadLatestAsync(CancellationToken cancellationToken)
    {
        _maintenance.RequireOpen();

        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseApi);
        request.Headers.UserAgent.ParseAdd("CodexRescue-Orchestrator/1.0");
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var release = await response.Content.ReadFromJsonAsync<GitHubRelease>(cancellationToken)
            ?? throw new InvalidDataException("GitHub returned an empty release record.");

        var assets = release.Assets.ToDictionary(asset => asset.Name, StringComparer.Ordinal);
        var manifestAsset = RequireAsset(assets, "release-manifest.json");
        var signatureAsset = RequireAsset(assets, "release-manifest.json.p7");
        var stagingDirectory = Path.Combine(Path.GetTempPath(), $"CodexRescueRelease-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stagingDirectory);

        try
        {
            var manifestBytes = await DownloadAsync(manifestAsset.BrowserDownloadUrl, cancellationToken);
            var signatureBytes = await DownloadAsync(signatureAsset.BrowserDownloadUrl, cancellationToken);
            await File.WriteAllBytesAsync(Path.Combine(stagingDirectory, manifestAsset.Name), manifestBytes, cancellationToken);
            await File.WriteAllBytesAsync(Path.Combine(stagingDirectory, signatureAsset.Name), signatureBytes, cancellationToken);

            var manifest = JsonSerializer.Deserialize<ReleaseManifestV1>(manifestBytes)
                ?? throw new InvalidDataException("Release manifest is empty.");
            foreach (var artifact in manifest.Artifacts)
            {
                var asset = RequireAsset(assets, artifact.Name);
                var payload = await DownloadAsync(asset.BrowserDownloadUrl, cancellationToken);
                var path = SafeStagingPath(stagingDirectory, asset.Name);
                await File.WriteAllBytesAsync(path, payload, cancellationToken);
            }

            var verified = await _verifier.VerifyAsync(
                manifestBytes,
                signatureBytes,
                stagingDirectory,
                _expectedPublisherIdentity,
                requireTrustedChain: true,
                cancellationToken);
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

    private async Task<byte[]> DownloadAsync(Uri uri, CancellationToken cancellationToken)
    {
        _maintenance.RequireOpen();
        if (uri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase) ||
            !uri.AbsolutePath.StartsWith(
                "/Morlock52/codex-rescue-usb/releases/download/",
                StringComparison.Ordinal))
        {
            throw new InvalidDataException("Release asset URL is outside the fixed GitHub release path.");
        }

        return await _httpClient.GetByteArrayAsync(uri, cancellationToken);
    }

    private static GitHubAsset RequireAsset(
        IReadOnlyDictionary<string, GitHubAsset> assets,
        string name) =>
        assets.TryGetValue(name, out var asset)
            ? asset
            : throw new InvalidDataException($"Required release asset is missing: {name}");

    private static string SafeStagingPath(string stagingDirectory, string name)
    {
        if (!string.Equals(name, Path.GetFileName(name), StringComparison.Ordinal))
        {
            throw new InvalidDataException("Release asset name is not a file name.");
        }

        return Path.Combine(stagingDirectory, name);
    }

    private sealed record GitHubRelease(IReadOnlyList<GitHubAsset> Assets);
    private sealed record GitHubAsset(string Name, Uri BrowserDownloadUrl);
}
