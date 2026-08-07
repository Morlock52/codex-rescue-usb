using System.Diagnostics;
using System.Reflection;
using CodexRescue.Contracts;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace CodexRescue.Orchestrator.Services;

public sealed class TelemetryQueueService
{
    private const string SourceName = "CodexRescue.Orchestrator";
    private readonly Queue<TelemetryEnvelopeV1> _queue = new();
    private TelemetryPolicy _policy = new();

    public int Count
    {
        get { lock (_queue) { return _queue.Count; } }
    }

    public void SetPolicy(TelemetryPolicy policy) =>
        _policy = policy ?? throw new ArgumentNullException(nameof(policy));

    public IReadOnlyDictionary<string, string> ExactOutgoingFields(TelemetryEnvelopeV1 envelope) =>
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["schemaVersion"] = envelope.SchemaVersion.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["eventName"] = envelope.EventName,
            ["appVersion"] = envelope.AppVersion,
            ["actionStage"] = envelope.ActionStage,
            ["resultCategory"] = envelope.ResultCategory,
            ["architecture"] = envelope.Architecture,
            ["durationBucket"] = envelope.DurationBucket,
            ["recordedAtUtc"] = envelope.RecordedAtUtc.ToString("O", System.Globalization.CultureInfo.InvariantCulture),
        };

    public void Enqueue(TelemetryEnvelopeV1 envelope)
    {
        if (!_policy.CanTransmit(envelope))
        {
            throw new InvalidOperationException("Telemetry requires administrator policy and operator consent.");
        }

        lock (_queue) { _queue.Enqueue(envelope); }
    }

    public bool TestEndpoint(Uri endpoint)
    {
        var version = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion.Split('+')[0] ?? "unknown";
        Enqueue(new TelemetryEnvelopeV1(
            1,
            "endpoint.tested",
            version,
            "test",
            "synthetic",
            System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant(),
            "under-1s",
            DateTimeOffset.UtcNow));
        return TransmitQueued(endpoint);
    }

    public bool TransmitQueued(Uri endpoint)
    {
        if (!endpoint.IsAbsoluteUri || endpoint.Scheme != Uri.UriSchemeHttps)
        {
            throw new InvalidDataException("An absolute HTTPS OTLP endpoint is required.");
        }

        TelemetryEnvelopeV1[] batch;
        lock (_queue) { batch = _queue.ToArray(); }
        if (batch.Length == 0)
        {
            return true;
        }

        using var source = new ActivitySource(SourceName);
        using var provider = Sdk.CreateTracerProviderBuilder()
            .SetResourceBuilder(ResourceBuilder.CreateEmpty())
            .AddSource(SourceName)
            .AddOtlpExporter(options =>
            {
                options.Endpoint = BuildTraceEndpoint(endpoint);
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
                options.TimeoutMilliseconds = 5_000;
            })
            .Build();

        foreach (var envelope in batch)
        {
            if (!_policy.CanTransmit(envelope))
            {
                throw new InvalidOperationException("Telemetry consent or policy was revoked.");
            }

            using var activity = source.StartActivity(envelope.EventName, ActivityKind.Internal)
                ?? throw new InvalidOperationException("The OTLP activity source was not registered.");
            foreach (var field in ExactOutgoingFields(envelope))
            {
                activity.SetTag(field.Key, field.Value);
            }
        }

        if (!provider.ForceFlush(5_000))
        {
            return false;
        }

        lock (_queue)
        {
            for (var index = 0; index < batch.Length; index++)
            {
                _queue.Dequeue();
            }
        }

        return true;
    }

    public void ClearQueue()
    {
        lock (_queue) { _queue.Clear(); }
    }

    public void Disable()
    {
        _policy = new TelemetryPolicy();
        ClearQueue();
    }

    private static Uri BuildTraceEndpoint(Uri endpoint)
    {
        if (endpoint.AbsolutePath.EndsWith("/v1/traces", StringComparison.OrdinalIgnoreCase))
        {
            return endpoint;
        }

        return new Uri(endpoint.ToString().TrimEnd('/') + "/v1/traces", UriKind.Absolute);
    }
}
