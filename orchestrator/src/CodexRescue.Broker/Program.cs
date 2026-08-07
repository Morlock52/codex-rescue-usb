using System.Reflection;
using System.Security.Cryptography;
using System.IO.Pipes;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Broker;

internal static class Program
{
    public static async Task<int> Main(string[] arguments)
    {
        try
        {
            if (arguments is not ["--pipe", var channelText] ||
                !Guid.TryParseExact(channelText, "N", out var channelId) ||
                channelId == Guid.Empty)
            {
                throw new InvalidDataException("A valid orchestrator broker channel is required.");
            }

            using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(2));
            await using var pipe = new NamedPipeClientStream(
                ".",
                BrokerWireProtocol.GetPipeName(channelId),
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            await pipe.ConnectAsync(timeout.Token);
            var request = await BrokerWireProtocol.ReadAsync<BrokerRequestV1>(pipe, timeout.Token);
            if (request.SchemaVersion != BrokerRequestV1.SupportedSchemaVersion)
            {
                throw new InvalidDataException("Supported broker request is required.");
            }
            var plan = request.Plan;
            var packageVersion = typeof(Program).Assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion.Split('+')[0]
                ?? throw new InvalidDataException("Broker package version is unavailable.");
            var catalog = SignedAssetCatalog.Load(packageVersion);

            var operation = new PlanValidator().ValidateForExecution(
                plan,
                packageVersion,
                catalog.Digest,
                DateTimeOffset.UtcNow);
            var runner = new SignedPowerShellRunner(catalog);

            var handlers = new Dictionary<BrokerOperation, IBrokerAction>
            {
                [BrokerOperation.ApplyToolchain] = new SignedPowerShellAction(operation, request, runner),
                [BrokerOperation.BuildMedia] = new SignedPowerShellAction(operation, request, runner),
                [BrokerOperation.WriteUsb] = new SignedPowerShellAction(operation, request, runner),
                [BrokerOperation.RepairUefi] = new SignedPowerShellAction(operation, request, runner),
                [BrokerOperation.SalvageBitLocker] = new SignedPowerShellAction(operation, request, runner),
            };

            var receipt = await new BrokerDispatcher(handlers).ExecuteAsync(
                operation,
                plan,
                CancellationToken.None);
            await BrokerWireProtocol.WriteAsync(pipe, receipt, CancellationToken.None);
            return receipt.Result == "Succeeded" ? 0 : 10;
        }
        catch (Exception exception) when (
            exception is InvalidDataException or JsonException or ArgumentException or
                CryptographicException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine("Broker request rejected by package, signature, or action policy.");
            return 65;
        }
    }

}
