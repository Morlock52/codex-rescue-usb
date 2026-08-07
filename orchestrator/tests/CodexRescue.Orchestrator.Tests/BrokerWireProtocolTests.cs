using System.Buffers.Binary;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class BrokerWireProtocolTests
{
    private sealed record WireFixture(int SchemaVersion, string Result);

    [TestMethod]
    public async Task RoundTrip_UsesOneBoundedLengthPrefixedMessage()
    {
        await using var stream = new MemoryStream();
        await BrokerWireProtocol.WriteAsync(
            stream,
            new WireFixture(1, "Succeeded"),
            CancellationToken.None);
        Assert.IsTrue(stream.Length > sizeof(int));
        stream.Position = 0;

        var result = await BrokerWireProtocol.ReadAsync<WireFixture>(stream, CancellationToken.None);

        Assert.AreEqual(1, result.SchemaVersion);
        Assert.AreEqual("Succeeded", result.Result);
    }

    [TestMethod]
    public async Task ReadAsync_RejectsOversizedDeclaredMessageBeforeAllocation()
    {
        var header = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32LittleEndian(header, BrokerWireProtocol.MaximumMessageBytes + 1);
        await using var stream = new MemoryStream(header);

        await Assert.ThrowsExactlyAsync<InvalidDataException>(() =>
            BrokerWireProtocol.ReadAsync<WireFixture>(stream, CancellationToken.None));
    }
}
