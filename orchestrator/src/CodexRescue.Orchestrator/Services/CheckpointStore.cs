using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class CheckpointStore
{
    private readonly string checkpointPath;
    private readonly CheckpointProtector protector;

    public CheckpointStore(string applicationDataDirectory)
    {
        Directory.CreateDirectory(applicationDataDirectory);
        checkpointPath = Path.Combine(applicationDataDirectory, "checkpoint.v1.json");
        protector = new CheckpointProtector(applicationDataDirectory);
    }

    public void Save(CheckpointV1 checkpoint)
    {
        var sealedCheckpoint = protector.Seal(checkpoint);
        var temporaryPath = checkpointPath + $".{Guid.NewGuid():N}.tmp";
        try
        {
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None))
            {
                JsonSerializer.Serialize(stream, sealedCheckpoint);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporaryPath, checkpointPath, overwrite: true);
        }
        finally
        {
            File.Delete(temporaryPath);
        }
    }

    public CheckpointV1? Load()
    {
        if (!File.Exists(checkpointPath))
        {
            return null;
        }

        var checkpoint = JsonSerializer.Deserialize<CheckpointV1>(File.ReadAllBytes(checkpointPath))
            ?? throw new InvalidDataException("Saved checkpoint is empty.");
        if (!protector.Verify(checkpoint))
        {
            throw new InvalidDataException("Saved checkpoint failed its machine-scoped HMAC verification.");
        }

        return checkpoint;
    }

    public void Clear() => File.Delete(checkpointPath);
}
