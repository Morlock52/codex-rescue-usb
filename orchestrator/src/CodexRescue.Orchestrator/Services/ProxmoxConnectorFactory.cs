using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public static class ProxmoxConnectorFactory
{
    private static readonly HashSet<string> CredentialPolicies =
        new(StringComparer.Ordinal) { "SessionOnly", "WindowsCredentialManager" };

    public static ProxmoxConnectorSession Create(
        ProxmoxProfileV1 profile,
        ReadOnlySpan<char> apiToken,
        bool administratorPolicyAllowsCredentialStorage = false)
    {
        ValidateProfile(profile, administratorPolicyAllowsCredentialStorage);
        if (apiToken.IsEmpty)
        {
            throw new ArgumentException("A session API token is required.", nameof(apiToken));
        }

        var expectedFingerprint = Convert.FromHexString(NormalizeHex(profile.CertificateFingerprint));
        var handler = new HttpClientHandler();
        handler.ServerCertificateCustomValidationCallback = (_, certificate, _, errors) =>
            CertificateMatches(certificate, errors, expectedFingerprint);

        var tokenHandler = new SessionTokenHandler(apiToken, handler);
        var client = new HttpClient(tokenHandler, disposeHandler: true)
        {
            BaseAddress = new Uri(profile.Endpoint, "/api2/json/"),
            Timeout = TimeSpan.FromMinutes(2),
        };
        return new ProxmoxConnectorSession(client, profile);
    }

    private static void ValidateProfile(
        ProxmoxProfileV1 profile,
        bool administratorPolicyAllowsCredentialStorage)
    {
        if (profile.SchemaVersion != ProxmoxProfileV1.SupportedSchemaVersion ||
            profile.Endpoint.Scheme != Uri.UriSchemeHttps ||
            !profile.Endpoint.IsAbsoluteUri)
        {
            throw new InvalidDataException("The Proxmox profile schema or HTTPS endpoint is invalid.");
        }

        var fingerprint = NormalizeHex(profile.CertificateFingerprint);
        if (fingerprint.Length != 64 || !fingerprint.All(Uri.IsHexDigit))
        {
            throw new InvalidDataException("CertificateFingerprint must be a SHA-256 fingerprint.");
        }

        if (!CredentialPolicies.Contains(profile.CredentialStoragePolicy) ||
            (profile.CredentialStoragePolicy == "WindowsCredentialManager" &&
             !administratorPolicyAllowsCredentialStorage))
        {
            throw new InvalidDataException("Credential storage policy is not allowed by administrator policy.");
        }

        var limits = profile.ResourceLimits;
        if (limits.CpuCores is < 1 or > 8 ||
            limits.MemoryMegabytes is < 2048 or > 32768 ||
            limits.DiskGigabytes is < 16 or > 256 ||
            limits.MaximumRunMinutes is < 1 or > 240)
        {
            throw new InvalidDataException("Proxmox resource limits exceed the connector policy.");
        }
    }

    private static bool CertificateMatches(
        X509Certificate2? certificate,
        SslPolicyErrors errors,
        byte[] expectedFingerprint)
    {
        if (certificate is null || errors.HasFlag(SslPolicyErrors.RemoteCertificateNotAvailable) ||
            errors.HasFlag(SslPolicyErrors.RemoteCertificateNameMismatch))
        {
            return false;
        }

        var actualFingerprint = certificate.GetCertHash(HashAlgorithmName.SHA256);
        return CryptographicOperations.FixedTimeEquals(actualFingerprint, expectedFingerprint);
    }

    private static string NormalizeHex(string value) =>
        value.Replace(":", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .ToUpperInvariant();

    private sealed class SessionTokenHandler : DelegatingHandler
    {
        private readonly char[] _token;

        public SessionTokenHandler(ReadOnlySpan<char> token, HttpMessageHandler innerHandler)
            : base(innerHandler) => _token = token.ToArray();

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"PVEAPIToken={new string(_token)}");
            return await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
        }

        protected override void Dispose(bool disposing)
        {
            Array.Clear(_token);
            base.Dispose(disposing);
        }
    }
}

public sealed class ProxmoxConnectorSession : IDisposable
{
    internal ProxmoxConnectorSession(HttpClient client, ProxmoxProfileV1 profile)
    {
        Client = client;
        Profile = profile;
    }

    internal HttpClient Client { get; }
    internal ProxmoxProfileV1 Profile { get; }

    public ProxmoxConnectorService CreateConnector() => new(Client, Profile);
    public void Dispose() => Client.Dispose();
}
