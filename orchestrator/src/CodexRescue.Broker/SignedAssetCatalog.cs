using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace CodexRescue.Broker;

public sealed record SignedAssetEntryV1(
    string Operation,
    string FileName,
    string Sha256,
    string SignerThumbprint,
    bool RequireAuthenticode);

public sealed record SignedAssetCatalogV1(
    int SchemaVersion,
    string PackageVersion,
    IReadOnlyList<SignedAssetEntryV1> Assets);

public sealed class SignedAssetCatalog
{
    private static readonly IReadOnlyDictionary<BrokerOperation, string> ExpectedFiles =
        new Dictionary<BrokerOperation, string>
        {
            [BrokerOperation.ApplyToolchain] = "scripts/Install-TechnicianWorkspaceToolchain.ps1",
            [BrokerOperation.BuildMedia] = "scripts/Build-CodexRescueMediaMatrix.ps1",
            [BrokerOperation.WriteUsb] = "scripts/Write-CodexRescueUsb.ps1",
            [BrokerOperation.RepairUefi] = "scripts/Invoke-CodexRescueUefiRepair.ps1",
            [BrokerOperation.SalvageBitLocker] = "scripts/Invoke-CodexRescueBitLockerSalvage.ps1",
        };
    private static readonly IReadOnlySet<string> ExpectedDependencies = new HashSet<string>(
        [
            "scripts/Test-TechnicianWorkspacePrerequisite.ps1",
            "scripts/Build-RescueIso.ps1",
            "scripts/Test-RescueIso.ps1",
            "winpe/Unlock-BitLockerWithRecoveryPassword.ps1",
            "winpe/New-EvidenceManifest.ps1",
            "winpe/Collect-OfflineWindowsInventory.ps1",
            "winpe/Collect-RescueEvidence.cmd",
            "winpe/Unlock-BitLockerWithRecoveryKey.cmd",
            "winpe/diskpart-list.txt",
            "winpe/startnet.cmd",
            "config/technician-workspace-tools.json",
            "config/media-build-matrix.json",
        ],
        StringComparer.Ordinal);

    private readonly IReadOnlyDictionary<BrokerOperation, string> verifiedPaths;

    private SignedAssetCatalog(
        string digest,
        IReadOnlyDictionary<BrokerOperation, string> verifiedPaths)
    {
        Digest = digest;
        this.verifiedPaths = verifiedPaths;
    }

    public string Digest { get; }

    public static SignedAssetCatalog Load(string expectedPackageVersion)
    {
        var assetsRoot = Path.Combine(AppContext.BaseDirectory, "Assets");
        var catalogPath = Path.Combine(assetsRoot, "assets-manifest.json");
        var catalogBytes = File.ReadAllBytes(catalogPath);
        var digest = Convert.ToHexString(SHA256.HashData(catalogBytes));
        var catalog = JsonSerializer.Deserialize<SignedAssetCatalogV1>(catalogBytes)
            ?? throw new InvalidDataException("Signed asset catalog is empty.");
        if (catalog.SchemaVersion != 1 ||
            !string.Equals(catalog.PackageVersion, expectedPackageVersion, StringComparison.Ordinal))
        {
            throw new InvalidDataException("Signed asset catalog does not match this broker package.");
        }

        var expectedNames = ExpectedFiles.Values.Concat(ExpectedDependencies).ToHashSet(StringComparer.Ordinal);
        var looseScripts = Directory.GetFiles(assetsRoot, "*.ps1", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(assetsRoot, path).Replace('\\', '/'))
            .ToHashSet(StringComparer.Ordinal);
        var expectedScripts = expectedNames.Where(name => name.EndsWith(".ps1", StringComparison.Ordinal))
            .ToHashSet(StringComparer.Ordinal);
        if (!looseScripts.SetEquals(expectedScripts))
        {
            throw new InvalidDataException("Package contains an unexpected loose script or is missing a signed asset.");
        }

        if (catalog.Assets.Count != expectedNames.Count)
        {
            throw new InvalidDataException("Signed asset catalog has an unexpected operation count.");
        }

        var verified = new Dictionary<BrokerOperation, string>();
        foreach (var relativeName in expectedNames)
        {
            var mappedOperation = ExpectedFiles.SingleOrDefault(pair => pair.Value == relativeName);
            var operationName = mappedOperation.Equals(default(KeyValuePair<BrokerOperation, string>))
                ? "Dependency"
                : mappedOperation.Key.ToString();
            var entries = catalog.Assets.Where(asset =>
                string.Equals(asset.Operation, operationName, StringComparison.Ordinal) &&
                string.Equals(asset.FileName, relativeName, StringComparison.Ordinal)).ToArray();
            if (entries.Length != 1 ||
                entries[0].FileName.Contains("..", StringComparison.Ordinal) ||
                Path.IsPathRooted(entries[0].FileName))
            {
                throw new InvalidDataException("Signed asset mapping is missing, duplicated, or unsafe.");
            }

            var path = Path.GetFullPath(Path.Combine(
                assetsRoot,
                entries[0].FileName.Replace('/', Path.DirectorySeparatorChar)));
            var rootPrefix = Path.GetFullPath(assetsRoot) + Path.DirectorySeparatorChar;
            if (!path.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase) || !File.Exists(path))
            {
                throw new InvalidDataException("Signed asset path escaped the package or is missing.");
            }
            var actualHash = SHA256.HashData(File.ReadAllBytes(path));
            byte[] expectedHash;
            try
            {
                expectedHash = Convert.FromHexString(entries[0].Sha256);
            }
            catch (FormatException exception)
            {
                throw new InvalidDataException("Signed asset hash is malformed.", exception);
            }
            if (!CryptographicOperations.FixedTimeEquals(actualHash, expectedHash))
            {
                throw new CryptographicException("Signed asset hash changed.");
            }

            if (entries[0].RequireAuthenticode != path.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Authenticode policy does not match the asset type.");
            }
            if (entries[0].RequireAuthenticode)
            {
                using var signer = AuthenticodeTrustVerifier.Verify(path);
                if (!FixedHexEquals(signer.Thumbprint, entries[0].SignerThumbprint))
                {
                    throw new CryptographicException("Signed asset has an unexpected signer.");
                }
            }
            else if (!string.IsNullOrEmpty(entries[0].SignerThumbprint))
            {
                throw new InvalidDataException("Non-PowerShell dependency may not declare an Authenticode signer.");
            }
            if (!mappedOperation.Equals(default(KeyValuePair<BrokerOperation, string>)))
            {
                verified.Add(mappedOperation.Key, path);
            }
        }

        return new SignedAssetCatalog(digest, verified);
    }

    public string GetVerifiedPath(BrokerOperation operation) =>
        verifiedPaths.TryGetValue(operation, out var path)
            ? path
            : throw new InvalidOperationException("Operation has no packaged signed asset.");

    private static bool FixedHexEquals(string left, string right)
    {
        try
        {
            return CryptographicOperations.FixedTimeEquals(
                Convert.FromHexString(left.Replace(" ", string.Empty, StringComparison.Ordinal)),
                Convert.FromHexString(right.Replace(" ", string.Empty, StringComparison.Ordinal)));
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static class AuthenticodeTrustVerifier
    {
        private static readonly Guid GenericVerifyV2 =
            new("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");

        public static X509Certificate2 Verify(string path)
        {
            var filePathPointer = Marshal.StringToCoTaskMemUni(path);
            var fileInfo = new WinTrustFileInfo
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustFileInfo>(),
                FilePath = filePathPointer,
            };
            var fileInfoPointer = Marshal.AllocCoTaskMem(Marshal.SizeOf<WinTrustFileInfo>());
            Marshal.StructureToPtr(fileInfo, fileInfoPointer, fDeleteOld: false);

            var trustData = new WinTrustData
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustData>(),
                UIChoice = 2,
                RevocationChecks = 0,
                UnionChoice = 1,
                FileInfo = fileInfoPointer,
                StateAction = 0,
                ProviderFlags = 0x00001000,
                UIContext = 0,
            };
            var trustDataPointer = Marshal.AllocCoTaskMem(Marshal.SizeOf<WinTrustData>());
            Marshal.StructureToPtr(trustData, trustDataPointer, fDeleteOld: false);

            try
            {
                var result = WinVerifyTrust(IntPtr.Zero, GenericVerifyV2, trustDataPointer);
                if (result != 0)
                {
                    throw new CryptographicException("Authenticode trust validation failed.");
                }
                return new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
            }
            finally
            {
                Marshal.FreeCoTaskMem(trustDataPointer);
                Marshal.FreeCoTaskMem(fileInfoPointer);
                Marshal.FreeCoTaskMem(filePathPointer);
            }
        }

        [DllImport("wintrust.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern uint WinVerifyTrust(
            IntPtr windowHandle,
            [MarshalAs(UnmanagedType.LPStruct)] Guid actionId,
            IntPtr trustData);

        [StructLayout(LayoutKind.Sequential)]
        private struct WinTrustFileInfo
        {
            public uint StructSize;
            public IntPtr FilePath;
            public IntPtr FileHandle;
            public IntPtr KnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WinTrustData
        {
            public uint StructSize;
            public IntPtr PolicyCallbackData;
            public IntPtr SipClientData;
            public uint UIChoice;
            public uint RevocationChecks;
            public uint UnionChoice;
            public IntPtr FileInfo;
            public uint StateAction;
            public IntPtr StateData;
            public IntPtr UrlReference;
            public uint ProviderFlags;
            public uint UIContext;
        }
    }
}
