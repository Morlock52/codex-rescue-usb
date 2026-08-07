using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace CodexRescue.Orchestrator.Services;

public sealed class PackagedBrokerVerifier
{
    private static readonly Guid GenericVerifyV2 =
        new("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");

    public void Verify(string brokerPath)
    {
        if (!File.Exists(brokerPath))
        {
            throw new FileNotFoundException("Packaged broker is missing.", brokerPath);
        }

        VerifyWindowsTrust(brokerPath);
        var expectedPublisher = new X500DistinguishedName(
            PublisherIdentityService.GetCurrentPackagePublisher());
        using var legacyCertificate = X509Certificate.CreateFromSignedFile(brokerPath);
        using var signer = new X509Certificate2(legacyCertificate);
        if (!CryptographicOperations.FixedTimeEquals(
                expectedPublisher.RawData,
                signer.SubjectName.RawData))
        {
            throw new CryptographicException("Broker signer does not match the installed MSIX publisher.");
        }

        var codeSigningOid = "1.3.6.1.5.5.7.3.3";
        var keyUsage = signer.Extensions.OfType<X509EnhancedKeyUsageExtension>().SingleOrDefault();
        if (keyUsage is null ||
            !keyUsage.EnhancedKeyUsages.Cast<Oid>().Any(oid => oid.Value == codeSigningOid))
        {
            throw new CryptographicException("Broker signer is not valid for code signing.");
        }
    }

    private static void VerifyWindowsTrust(string path)
    {
        var pathPointer = Marshal.StringToCoTaskMemUni(path);
        var fileInfoPointer = Marshal.AllocCoTaskMem(Marshal.SizeOf<WinTrustFileInfo>());
        var trustDataPointer = Marshal.AllocCoTaskMem(Marshal.SizeOf<WinTrustData>());
        try
        {
            var fileInfo = new WinTrustFileInfo
            {
                StructSize = (uint)Marshal.SizeOf<WinTrustFileInfo>(),
                FilePath = pathPointer,
            };
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
            Marshal.StructureToPtr(trustData, trustDataPointer, fDeleteOld: false);
            if (WinVerifyTrust(IntPtr.Zero, GenericVerifyV2, trustDataPointer) != 0)
            {
                throw new CryptographicException("Broker Authenticode trust validation failed.");
            }
        }
        finally
        {
            Marshal.FreeCoTaskMem(trustDataPointer);
            Marshal.FreeCoTaskMem(fileInfoPointer);
            Marshal.FreeCoTaskMem(pathPointer);
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
