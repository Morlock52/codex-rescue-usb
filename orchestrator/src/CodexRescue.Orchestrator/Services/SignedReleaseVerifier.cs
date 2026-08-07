using System.Security.Cryptography;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed record VerifiedRelease(
    ReleaseManifestV1 Manifest,
    string PublisherIdentity,
    IReadOnlyDictionary<string, string> VerifiedArtifacts);

public sealed class SignedReleaseVerifier
{
    public async Task<VerifiedRelease> VerifyAsync(
        byte[] manifestBytes,
        byte[] detachedSignature,
        string artifactDirectory,
        string expectedPublisherIdentity,
        bool requireTrustedChain,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(manifestBytes);
        ArgumentNullException.ThrowIfNull(detachedSignature);

        var signedCms = new SignedCms(new ContentInfo(manifestBytes), detached: true);
        signedCms.Decode(detachedSignature);
        signedCms.CheckSignature(verifySignatureOnly: true);
        if (signedCms.SignerInfos.Count != 1)
        {
            throw new CryptographicException("Exactly one release signer is required.");
        }

        var signerInfo = signedCms.SignerInfos[0];
        var certificate = signerInfo.Certificate
            ?? throw new CryptographicException("The release signer certificate is missing.");
        var expectedPublisher = new X500DistinguishedName(expectedPublisherIdentity);
        if (!CryptographicOperations.FixedTimeEquals(
                certificate.SubjectName.RawData,
                expectedPublisher.RawData))
        {
            throw new CryptographicException("Release publisher does not match policy.");
        }

        var codeSigningOid = "1.3.6.1.5.5.7.3.3";
        var enhancedKeyUsage = certificate.Extensions
            .OfType<X509EnhancedKeyUsageExtension>()
            .SingleOrDefault();
        if (enhancedKeyUsage is null ||
            !enhancedKeyUsage.EnhancedKeyUsages.Cast<Oid>().Any(oid => oid.Value == codeSigningOid))
        {
            throw new CryptographicException("Release signer is not valid for code signing.");
        }

        var now = DateTimeOffset.UtcNow;
        DateTimeOffset verificationTime;
        if (requireTrustedChain)
        {
            var timestamp = GetVerifiedTimestamp(
                signerInfo,
                signedCms.Certificates,
                now);
            verificationTime = timestamp.Timestamp;
            using (timestamp.Certificate)
            {
                BuildTrustedChain(
                    timestamp.Certificate,
                    verificationTime,
                    "1.3.6.1.5.5.7.3.8",
                    signedCms.Certificates,
                    "timestamp authority");
            }

            BuildTrustedChain(
                certificate,
                verificationTime,
                codeSigningOid,
                signedCms.Certificates,
                "release signer");
        }
        else
        {
            verificationTime = now;
            if (now < certificate.NotBefore || now > certificate.NotAfter)
            {
                throw new CryptographicException("Release signer certificate is not currently valid.");
            }
        }

        var manifest = JsonSerializer.Deserialize<ReleaseManifestV1>(manifestBytes)
            ?? throw new InvalidDataException("Release manifest is empty.");
        if (manifest.SchemaVersion != ReleaseManifestV1.SupportedSchemaVersion)
        {
            throw new InvalidDataException("Unsupported release-manifest schema.");
        }

        var manifestPublisher = new X500DistinguishedName(manifest.PublisherIdentity);
        if (!CryptographicOperations.FixedTimeEquals(
                manifestPublisher.RawData,
                certificate.SubjectName.RawData))
        {
            throw new CryptographicException("Manifest publisher identity does not match its signer.");
        }

        if (requireTrustedChain &&
            Math.Abs((manifest.PublishedAtUtc - verificationTime).TotalHours) > 24)
        {
            throw new CryptographicException("Manifest publication time does not match its trusted timestamp.");
        }

        var root = Path.GetFullPath(artifactDirectory) + Path.DirectorySeparatorChar;
        var verified = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var artifact in manifest.Artifacts)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var artifactPath = Path.GetFullPath(Path.Combine(root, artifact.Name));
            if (!artifactPath.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
                !File.Exists(artifactPath))
            {
                throw new InvalidDataException("Manifest artifact path is missing or escapes its bundle.");
            }

            await using var stream = File.OpenRead(artifactPath);
            if (stream.Length != artifact.SizeBytes)
            {
                throw new InvalidDataException($"Artifact size changed: {artifact.Name}");
            }

            var actual = await SHA256.HashDataAsync(stream, cancellationToken);
            var expected = Convert.FromHexString(NormalizeHex(artifact.Sha256));
            if (!CryptographicOperations.FixedTimeEquals(actual, expected))
            {
                throw new CryptographicException($"Artifact hash changed: {artifact.Name}");
            }

            verified.Add(artifact.Name, Convert.ToHexString(actual));
        }

        return new VerifiedRelease(manifest, certificate.Subject, verified);
    }

    private static string NormalizeHex(string value) =>
        value.Replace(" ", string.Empty, StringComparison.Ordinal).ToUpperInvariant();

    private static (DateTimeOffset Timestamp, X509Certificate2 Certificate) GetVerifiedTimestamp(
        SignerInfo signerInfo,
        X509Certificate2Collection candidates,
        DateTimeOffset now)
    {
        const string rfc3161Oid = "1.2.840.113549.1.9.16.2.14";
        var timestampAttributes = signerInfo.UnsignedAttributes
            .Cast<CryptographicAttributeObject>()
            .Where(attribute => attribute.Oid?.Value == rfc3161Oid)
            .ToArray();
        if (timestampAttributes.Length != 1 || timestampAttributes[0].Values.Count != 1 ||
            !Rfc3161TimestampToken.TryDecode(
                timestampAttributes[0].Values[0].RawData,
                out var token,
                out var bytesConsumed) ||
            token is null ||
            bytesConsumed != timestampAttributes[0].Values[0].RawData.Length ||
            !token.VerifySignatureForSignerInfo(signerInfo, out var tsaCertificate, candidates) ||
            tsaCertificate is null)
        {
            throw new CryptographicException("A valid RFC 3161 release timestamp is required.");
        }

        var timestamp = token.TokenInfo.Timestamp;
        if (timestamp > now.AddMinutes(5))
        {
            tsaCertificate.Dispose();
            throw new CryptographicException("Release timestamp is in the future.");
        }

        return (timestamp, tsaCertificate);
    }

    private static void BuildTrustedChain(
        X509Certificate2 certificate,
        DateTimeOffset verificationTime,
        string applicationPolicyOid,
        X509Certificate2Collection candidates,
        string role)
    {
        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.NoFlag;
        chain.ChainPolicy.VerificationTime = verificationTime.UtcDateTime;
        chain.ChainPolicy.ApplicationPolicy.Add(new Oid(applicationPolicyOid));
        chain.ChainPolicy.ExtraStore.AddRange(candidates);
        if (!chain.Build(certificate))
        {
            throw new CryptographicException($"The trusted {role} chain is invalid at the signed time.");
        }
    }
}
