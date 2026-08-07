using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Services;

public sealed record ProxmoxTestVm(
    int VmId,
    string Node,
    string ResourceLabel,
    string IsoVolume,
    string NetworkState);

public sealed record ProxmoxBootEvidence(
    int VmId,
    string ResourceLabel,
    string Status,
    DateTimeOffset CollectedAtUtc,
    string EvidenceTier);

public sealed class ProxmoxConnectorService
{
    private readonly HttpClient _httpClient;
    private readonly ProxmoxProfileV1 _profile;
    private readonly HashSet<int> _trackedVmIds = [];
    private readonly string _resourceLabel = $"codex-rescue-{Guid.NewGuid():N}";

    internal ProxmoxConnectorService(HttpClient httpClient, ProxmoxProfileV1 profile)
    {
        _httpClient = httpClient;
        _profile = profile;
    }

    public string ResourceLabel => _resourceLabel;

    public async Task<string> UploadIsoAsync(
        string node,
        string storage,
        string verifiedIsoPath,
        string expectedSha256,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(node, nameof(node));
        ValidateIdentifier(storage, nameof(storage));
        var isoPath = Path.GetFullPath(verifiedIsoPath);
        await using var stream = File.OpenRead(isoPath);
        var actualHash = Convert.ToHexString(await SHA256.HashDataAsync(stream, cancellationToken));
        if (!FixedPhraseEquals(actualHash, NormalizeHex(expectedSha256)))
        {
            throw new CryptographicException("Verified ISO hash changed before upload.");
        }

        stream.Position = 0;
        var uploadName = $"{_resourceLabel}-{Path.GetFileName(isoPath)}";
        using var form = new MultipartFormDataContent
        {
            { new StringContent("iso"), "content" },
            { new StreamContent(stream), "filename", uploadName },
        };
        using var response = await _httpClient.PostAsync(
            $"nodes/{node}/storage/{storage}/upload",
            form,
            cancellationToken);
        response.EnsureSuccessStatusCode();
        return $"{storage}:iso/{uploadName}";
    }

    public async Task<ProxmoxTestVm> CreateDisconnectedX64UefiVmAsync(
        string node,
        string storage,
        string isoVolume,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(node, nameof(node));
        ValidateIdentifier(storage, nameof(storage));
        if (!isoVolume.StartsWith($"{storage}:iso/{_resourceLabel}-", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("The ISO was not uploaded by this connector session.");
        }

        var vmId = await GetNextVmIdAsync(cancellationToken);
        var limits = _profile.ResourceLimits;
        var configuration = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["vmid"] = vmId.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["name"] = _resourceLabel,
            ["description"] = $"Disposable Codex Rescue VM; Disconnected; {_resourceLabel}",
            ["tags"] = _resourceLabel,
            ["bios"] = "ovmf",
            ["arch"] = "x86_64",
            ["machine"] = "q35",
            ["efidisk0"] = $"{storage}:1,efitype=4m,pre-enrolled-keys=1",
            ["scsihw"] = "virtio-scsi-single",
            ["scsi0"] = $"{storage}:{limits.DiskGigabytes},discard=on,ssd=1",
            ["ide2"] = $"{isoVolume},media=cdrom",
            ["boot"] = "order=ide2;scsi0",
            ["cores"] = limits.CpuCores.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["memory"] = limits.MemoryMegabytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["ostype"] = "win11",
            ["onboot"] = "0",
        };
        using var response = await _httpClient.PostAsync(
            $"nodes/{node}/qemu",
            new FormUrlEncodedContent(configuration),
            cancellationToken);
        response.EnsureSuccessStatusCode();
        _trackedVmIds.Add(vmId);
        return new ProxmoxTestVm(vmId, node, _resourceLabel, isoVolume, "Disconnected");
    }

    public async Task<ProxmoxBootEvidence> BootAndCollectBoundedEvidenceAsync(
        ProxmoxTestVm vm,
        CancellationToken cancellationToken)
    {
        RequireTracked(vm);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(_profile.ResourceLimits.MaximumRunMinutes));
        using (var start = await _httpClient.PostAsync(
                   $"nodes/{vm.Node}/qemu/{vm.VmId}/status/start",
                   content: null,
                   timeout.Token))
        {
            start.EnsureSuccessStatusCode();
        }

        using var statusResponse = await _httpClient.GetAsync(
            $"nodes/{vm.Node}/qemu/{vm.VmId}/status/current",
            timeout.Token);
        statusResponse.EnsureSuccessStatusCode();
        var envelope = await statusResponse.Content.ReadFromJsonAsync<ApiEnvelope<VmStatus>>(timeout.Token)
            ?? throw new InvalidDataException("Proxmox returned no VM status.");
        return new ProxmoxBootEvidence(
            vm.VmId,
            _resourceLabel,
            envelope.Data.Status,
            DateTimeOffset.UtcNow,
            "Proxmox x64 VM runtime; not physical hardware proof");
    }

    public async Task DeleteTrackedVmAsync(
        ProxmoxTestVm vm,
        string confirmationPhrase,
        CancellationToken cancellationToken)
    {
        RequireTracked(vm);
        var expectedPhrase = $"DELETE VM {vm.VmId} {_resourceLabel}";
        if (!FixedPhraseEquals(confirmationPhrase, expectedPhrase))
        {
            throw new InvalidOperationException("Target-bound cleanup confirmation did not match.");
        }

        var configuration = await GetVmConfigAsync(vm.Node, vm.VmId, cancellationToken);
        var tags = configuration.TryGetValue("tags", out var value) ? value : string.Empty;
        if (!tags.Split(';', StringSplitOptions.RemoveEmptyEntries).Contains(_resourceLabel, StringComparer.Ordinal))
        {
            throw new InvalidOperationException("Resource label changed; cleanup refused.");
        }

        var tracked = _trackedVmIds;
        if (!tracked.Contains(vm.VmId))
        {
            throw new InvalidOperationException("The VM is not tracked by this connector session.");
        }

        using var response = await _httpClient.DeleteAsync(
            $"nodes/{vm.Node}/qemu/{vm.VmId}?purge=1&destroy-unreferenced-disks=1",
            cancellationToken);
        response.EnsureSuccessStatusCode();
        _trackedVmIds.Remove(vm.VmId);
    }

    private async Task<int> GetNextVmIdAsync(CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync("cluster/nextid", cancellationToken);
        response.EnsureSuccessStatusCode();
        var envelope = await response.Content.ReadFromJsonAsync<ApiEnvelope<string>>(cancellationToken)
            ?? throw new InvalidDataException("Proxmox returned no VM identifier.");
        return int.Parse(envelope.Data, System.Globalization.CultureInfo.InvariantCulture);
    }

    private async Task<IReadOnlyDictionary<string, string>> GetVmConfigAsync(
        string node,
        int vmId,
        CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync($"nodes/{node}/qemu/{vmId}/config", cancellationToken);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(cancellationToken));
        return document.RootElement.GetProperty("data")
            .EnumerateObject()
            .ToDictionary(
                property => property.Name,
                property => property.Value.ToString(),
                StringComparer.Ordinal);
    }

    private void RequireTracked(ProxmoxTestVm vm)
    {
        if (!_trackedVmIds.Contains(vm.VmId) || vm.ResourceLabel != _resourceLabel || vm.NetworkState != "Disconnected")
        {
            throw new InvalidOperationException("Only this session's disconnected, labeled VM may be managed.");
        }
    }

    private static bool FixedPhraseEquals(string left, string right)
    {
        var leftBytes = Encoding.UTF8.GetBytes(left);
        var rightBytes = Encoding.UTF8.GetBytes(right);
        return leftBytes.Length == rightBytes.Length &&
               CryptographicOperations.FixedTimeEquals(leftBytes, rightBytes);
    }

    private static string NormalizeHex(string value) =>
        value.Replace(" ", string.Empty, StringComparison.Ordinal).ToUpperInvariant();

    private static void ValidateIdentifier(string value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Any(character =>
                !char.IsLetterOrDigit(character) && character is not '-' and not '_' and not '.'))
        {
            throw new ArgumentException("Proxmox identifier contains unsupported characters.", parameterName);
        }
    }

    private sealed record ApiEnvelope<T>(T Data);
    private sealed record VmStatus(string Status);
}
