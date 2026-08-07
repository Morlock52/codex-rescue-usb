using System.Text;
using System.Xml;

namespace CodexRescue.Orchestrator.Services;

public sealed record PreparedRollback(string Directory, string AppInstallerName, string Version);

public sealed class RollbackInstallerService
{
    private const string AppInstallerNamespace = "http://schemas.microsoft.com/appx/appinstaller/2021";
    private readonly ReleaseCacheManager cache;
    private readonly SignedReleaseVerifier verifier;
    private readonly string publisherIdentity;

    public RollbackInstallerService(
        ReleaseCacheManager cache,
        SignedReleaseVerifier verifier,
        string publisherIdentity)
    {
        this.cache = cache;
        this.verifier = verifier;
        this.publisherIdentity = publisherIdentity;
    }

    public async Task<PreparedRollback> PrepareAsync(CancellationToken cancellationToken)
    {
        var candidate = cache.GetRollbackCandidate();
        var manifestPath = Path.Combine(candidate.Directory, "release-manifest.json");
        var signaturePath = Path.Combine(candidate.Directory, "release-manifest.json.p7");
        var manifestBytes = await File.ReadAllBytesAsync(manifestPath, cancellationToken);
        var signatureBytes = await File.ReadAllBytesAsync(signaturePath, cancellationToken);
        var verified = await verifier.VerifyAsync(
            manifestBytes,
            signatureBytes,
            candidate.Directory,
            publisherIdentity,
            requireTrustedChain: true,
            cancellationToken);
        if (!Version.TryParse(verified.Manifest.Version, out var manifestVersion) ||
            manifestVersion != candidate.Version)
        {
            throw new InvalidDataException("N-1 cache directory does not match its signed release version.");
        }

        var bundles = verified.Manifest.Artifacts.Where(artifact =>
            artifact.Name.EndsWith(".msixbundle", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (bundles.Length != 1)
        {
            throw new InvalidDataException("The signed N-1 manifest must identify exactly one MSIX bundle.");
        }

        var bundlePath = Path.GetFullPath(Path.Combine(candidate.Directory, bundles[0].Name));
        var rootPrefix = Path.GetFullPath(candidate.Directory) + Path.DirectorySeparatorChar;
        if (!bundlePath.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("N-1 bundle escaped its verified cache directory.");
        }

        var rollbackName = $"CodexRescue.rollback.{Guid.NewGuid():N}.appinstaller";
        var rollbackPath = Path.Combine(candidate.Directory, rollbackName);
        var packageVersion = new Version(
            manifestVersion.Major,
            manifestVersion.Minor,
            Math.Max(0, manifestVersion.Build),
            Math.Max(0, manifestVersion.Revision)).ToString(4);
        var settings = new XmlWriterSettings
        {
            Encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false),
            Indent = true,
            CloseOutput = true,
        };
        using (var stream = new FileStream(rollbackPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
        using (var writer = XmlWriter.Create(stream, settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("AppInstaller", AppInstallerNamespace);
            writer.WriteAttributeString("Version", packageVersion);
            writer.WriteAttributeString("Uri", new Uri(rollbackPath).AbsoluteUri);
            writer.WriteStartElement("MainBundle", AppInstallerNamespace);
            writer.WriteAttributeString("Name", "CodexRescue.Orchestrator");
            writer.WriteAttributeString("Publisher", verified.Manifest.PublisherIdentity);
            writer.WriteAttributeString("Version", packageVersion);
            writer.WriteAttributeString("Uri", new Uri(bundlePath).AbsoluteUri);
            writer.WriteEndElement();
            writer.WriteStartElement("UpdateSettings", AppInstallerNamespace);
            writer.WriteElementString("ForceUpdateFromAnyVersion", AppInstallerNamespace, "true");
            writer.WriteEndElement();
            writer.WriteEndElement();
            writer.WriteEndDocument();
        }

        return new PreparedRollback(candidate.Directory, rollbackName, manifestVersion.ToString());
    }
}
