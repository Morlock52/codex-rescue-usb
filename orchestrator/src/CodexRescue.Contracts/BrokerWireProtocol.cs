using System.Buffers.Binary;
using System.Text.Json;

namespace CodexRescue.Contracts;

public static class BrokerWireProtocol
{
    public const int MaximumMessageBytes = 1024 * 1024;
    private const string PipePrefix = "codex-rescue-broker-";

    public static string GetPipeName(Guid channelId)
    {
        if (channelId == Guid.Empty)
        {
            throw new ArgumentException("Broker channel identity is required.", nameof(channelId));
        }

        return PipePrefix + channelId.ToString("N");
    }

    public static async Task WriteAsync<T>(
        Stream stream,
        T message,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(stream);
        var payload = JsonSerializer.SerializeToUtf8Bytes(message);
        if (payload.Length is <= 0 or > MaximumMessageBytes)
        {
            throw new InvalidDataException("Broker message exceeds its bounded size.");
        }

        var header = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);
        await stream.WriteAsync(header, cancellationToken);
        await stream.WriteAsync(payload, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public static async Task<T> ReadAsync<T>(
        Stream stream,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(stream);
        var header = new byte[sizeof(int)];
        await ReadExactlyAsync(stream, header, cancellationToken);
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length is <= 0 or > MaximumMessageBytes)
        {
            throw new InvalidDataException("Broker message length is invalid.");
        }

        var payload = new byte[length];
        await ReadExactlyAsync(stream, payload, cancellationToken);
        return JsonSerializer.Deserialize<T>(payload)
            ?? throw new InvalidDataException("Broker message is empty.");
    }

    private static async Task ReadExactlyAsync(
        Stream stream,
        Memory<byte> buffer,
        CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer[offset..], cancellationToken);
            if (read == 0)
            {
                throw new EndOfStreamException("Broker channel closed before a complete message arrived.");
            }

            offset += read;
        }
    }
}
