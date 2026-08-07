using System.ComponentModel;
using System.Diagnostics;
using System.IO.Pipes;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed class BrokerClient
{
    private const int ErrorCancelled = 1223;
    private readonly PackagedBrokerVerifier verifier;

    public BrokerClient(PackagedBrokerVerifier? verifier = null)
    {
        this.verifier = verifier ?? new PackagedBrokerVerifier();
    }

    public async Task<ActionReceiptV1> ExecuteAsync(
        BrokerRequestV1 request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.SchemaVersion != BrokerRequestV1.SupportedSchemaVersion)
        {
            throw new InvalidDataException("Unsupported broker request schema.");
        }

        var brokerPath = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "Broker",
            "CodexRescue.Broker.exe"));
        var expectedRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "Broker")) +
            Path.DirectorySeparatorChar;
        if (!brokerPath.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(brokerPath))
        {
            throw new InvalidDataException("The packaged broker is missing or outside its fixed package directory.");
        }

        verifier.Verify(brokerPath);
        var channelId = Guid.NewGuid();
        await using var pipe = new NamedPipeServerStream(
            BrokerWireProtocol.GetPipeName(channelId),
            PipeDirection.InOut,
            maxNumberOfServerInstances: 1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        using var process = StartElevatedBroker(brokerPath, channelId);
        using var connectionTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        connectionTimeout.CancelAfter(TimeSpan.FromMinutes(2));
        try
        {
            await pipe.WaitForConnectionAsync(connectionTimeout.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException("The elevated broker did not connect within two minutes.");
        }

        await BrokerWireProtocol.WriteAsync(pipe, request, cancellationToken);
        ActionReceiptV1 receipt;
        try
        {
            receipt = await BrokerWireProtocol.ReadAsync<ActionReceiptV1>(pipe, cancellationToken);
        }
        catch (EndOfStreamException exception)
        {
            throw new InvalidDataException("The broker rejected the signed plan or packaged action.", exception);
        }

        await process.WaitForExitAsync(cancellationToken);
        if (receipt.SchemaVersion != ActionReceiptV1.SupportedSchemaVersion ||
            receipt.ActionId != request.Plan.ActionId)
        {
            throw new InvalidDataException("Broker receipt identity or schema did not match the request.");
        }

        return receipt;
    }

    private static Process StartElevatedBroker(string brokerPath, Guid channelId)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = brokerPath,
            UseShellExecute = true,
            Verb = "runas",
            WorkingDirectory = Path.GetDirectoryName(brokerPath)!,
        };
        startInfo.ArgumentList.Add("--pipe");
        startInfo.ArgumentList.Add(channelId.ToString("N"));

        try
        {
            return Process.Start(startInfo)
                ?? throw new InvalidOperationException("The elevated broker could not start.");
        }
        catch (Win32Exception exception) when (exception.NativeErrorCode == ErrorCancelled)
        {
            throw new OperationCanceledException("ERROR_CANCELLED: The operator cancelled UAC elevation.", exception);
        }
    }
}
