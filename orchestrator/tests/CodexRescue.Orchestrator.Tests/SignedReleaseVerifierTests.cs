using System.Security.Cryptography;
using System.Security.Cryptography.Pkcs;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using CodexRescue.Contracts;
using CodexRescue.Orchestrator.Services;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class SignedReleaseVerifierTests
{
    [TestMethod]
    public async Task ManifestSignatureAndArtifactHashAreVerified()
    {
        using var bundle = new SignedTestBundle();

        var result = await new SignedReleaseVerifier().VerifyAsync(
            bundle.ManifestBytes,
            bundle.SignatureBytes,
            bundle.DirectoryPath,
            bundle.Certificate.Subject,
            requireTrustedChain: false,
            CancellationToken.None);

        Assert.AreEqual("0.1.0", result.Manifest.Version);
        Assert.AreEqual(1, result.VerifiedArtifacts.Count);
    }

    [TestMethod]
    public async Task ChangedArtifactHashIsRejected()
    {
        using var bundle = new SignedTestBundle();
        await File.AppendAllTextAsync(bundle.ArtifactPath, "changed");

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            new SignedReleaseVerifier().VerifyAsync(
                bundle.ManifestBytes,
                bundle.SignatureBytes,
                bundle.DirectoryPath,
                bundle.Certificate.Subject,
                requireTrustedChain: false,
                CancellationToken.None));
    }

    [TestMethod]
    public async Task TrustedReleaseWithoutRfc3161TimestampIsRejected()
    {
        using var bundle = new SignedTestBundle();

        await Assert.ThrowsExactlyAsync<CryptographicException>(() =>
            new SignedReleaseVerifier().VerifyAsync(
                bundle.ManifestBytes,
                bundle.SignatureBytes,
                bundle.DirectoryPath,
                bundle.Certificate.Subject,
                requireTrustedChain: true,
                CancellationToken.None));
    }

    [TestMethod]
    public async Task UnexpectedPublisherIdentityIsRejected()
    {
        using var bundle = new SignedTestBundle();

        await Assert.ThrowsExactlyAsync<CryptographicException>(() =>
            new SignedReleaseVerifier().VerifyAsync(
                bundle.ManifestBytes,
                bundle.SignatureBytes,
                bundle.DirectoryPath,
                "CN=Different Publisher",
                requireTrustedChain: false,
                CancellationToken.None));
    }

    private sealed class SignedTestBundle : IDisposable
    {
        public SignedTestBundle()
        {
            DirectoryPath = Path.Combine(Path.GetTempPath(), $"CodexRescueBundle-{Guid.NewGuid():N}");
            Directory.CreateDirectory(DirectoryPath);
            ArtifactPath = Path.Combine(DirectoryPath, "orchestrator.msix");
            File.WriteAllText(ArtifactPath, "signed-test-artifact");
            var artifactBytes = File.ReadAllBytes(ArtifactPath);

            using var rsa = RSA.Create(2048);
            var request = new CertificateRequest(
                "CN=Codex Rescue Test Publisher",
                rsa,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);
            request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(
                new OidCollection { new("1.3.6.1.5.5.7.3.3") },
                critical: true));
            Certificate = request.CreateSelfSigned(
                DateTimeOffset.UtcNow.AddMinutes(-1),
                DateTimeOffset.UtcNow.AddHours(1));

            var manifest = new ReleaseManifestV1(
                1,
                "0.1.0",
                "x64",
                [new ReleaseArtifactV1(
                    "orchestrator.msix",
                    "x64",
                    Convert.ToHexString(SHA256.HashData(artifactBytes)),
                    artifactBytes.LongLength)],
                Certificate.Subject,
                "10.0.22621.0",
                "orchestrator-n-1.msix",
                DateTimeOffset.UtcNow);
            ManifestBytes = JsonSerializer.SerializeToUtf8Bytes(manifest);

            var cms = new SignedCms(new ContentInfo(ManifestBytes), detached: true);
            cms.ComputeSignature(new CmsSigner(SubjectIdentifierType.IssuerAndSerialNumber, Certificate));
            SignatureBytes = cms.Encode();
        }

        public string DirectoryPath { get; }

        public string ArtifactPath { get; }

        public X509Certificate2 Certificate { get; }

        public byte[] ManifestBytes { get; }

        public byte[] SignatureBytes { get; }

        public void Dispose()
        {
            Certificate.Dispose();
            Directory.Delete(DirectoryPath, recursive: true);
        }
    }
}
