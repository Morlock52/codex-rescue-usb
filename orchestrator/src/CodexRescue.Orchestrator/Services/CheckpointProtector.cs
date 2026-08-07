using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class CheckpointProtector
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes(
        "CodexRescue.Orchestrator.CheckpointV1");
    private readonly string keyFile;

    public CheckpointProtector(string applicationDataDirectory)
    {
        Directory.CreateDirectory(applicationDataDirectory);
        keyFile = Path.Combine(applicationDataDirectory, "checkpoint.machine.key");
    }

    public CheckpointV1 Seal(CheckpointV1 checkpoint)
    {
        ValidateNonSecretState(checkpoint.NonSecretState);
        var unsigned = checkpoint with { Hmac = string.Empty };
        var body = JsonSerializer.SerializeToUtf8Bytes(unsigned);
        using var hmac = new HMACSHA256(GetOrCreateMachineProtectedKey());
        return checkpoint with { Hmac = Convert.ToHexString(hmac.ComputeHash(body)) };
    }

    public bool Verify(CheckpointV1 checkpoint)
    {
        if (checkpoint.SchemaVersion != CheckpointV1.SupportedSchemaVersion ||
            string.IsNullOrWhiteSpace(checkpoint.Hmac))
        {
            return false;
        }

        var unsigned = checkpoint with { Hmac = string.Empty };
        var body = JsonSerializer.SerializeToUtf8Bytes(unsigned);
        using var hmac = new HMACSHA256(GetOrCreateMachineProtectedKey());
        var actual = hmac.ComputeHash(body);

        try
        {
            var supplied = Convert.FromHexString(checkpoint.Hmac);
            return CryptographicOperations.FixedTimeEquals(actual, supplied);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private byte[] GetOrCreateMachineProtectedKey()
    {
        if (File.Exists(keyFile))
        {
            return ProtectedData.Unprotect(
                File.ReadAllBytes(keyFile),
                Entropy,
                DataProtectionScope.LocalMachine);
        }

        var key = RandomNumberGenerator.GetBytes(32);
        var protectedKey = ProtectedData.Protect(
            key,
            Entropy,
            DataProtectionScope.LocalMachine);
        File.WriteAllBytes(keyFile, protectedKey);
        return key;
    }

    private static void ValidateNonSecretState(IReadOnlyDictionary<string, string> state)
    {
        var forbidden = new[] { "password", "secret", "token", "recovery", "credential", "key" };
        foreach (var pair in state)
        {
            var candidate = $"{pair.Key} {pair.Value}";
            if (forbidden.Any(term => candidate.Contains(term, StringComparison.OrdinalIgnoreCase)))
            {
                throw new InvalidDataException("Checkpoint state may not contain secrets.");
            }
        }
    }
}
