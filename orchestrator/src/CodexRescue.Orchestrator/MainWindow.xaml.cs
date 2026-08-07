using System.Net.Http;
using System.Globalization;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Controls;
using System.Text.Json;
using CodexRescue.Contracts;
using CodexRescue.Orchestrator.Services;
using CodexRescue.Orchestrator.ViewModels;
using Microsoft.Win32;

namespace CodexRescue.Orchestrator;

public partial class MainWindow : Window
{
    private readonly MainViewModel viewModel = new();
    private readonly TelemetryQueueService telemetry = new();
    private readonly MaintenanceWindowService maintenance = new();
    private readonly HttpClient updateClient = new();

    public MainWindow()
    {
        InitializeComponent();
        DataContext = viewModel;
    }

    private async void RunAudit_Click(object sender, RoutedEventArgs e)
    {
        RunAuditButton.IsEnabled = false;
        try
        {
            await viewModel.RunAuditAsync(CancellationToken.None);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                this,
                exception.Message,
                "Audit blocked",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        finally
        {
            RunAuditButton.IsEnabled = true;
        }
    }

    private void Navigate_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string indexText } && int.TryParse(indexText, out var index))
        {
            WorkflowTabs.SelectedIndex = index;
        }
    }

    private void OpenMaintenance_Click(object sender, RoutedEventArgs e)
    {
        var window = maintenance.Open(NetworkConsent: true);
        MaintenanceStatus.Text = $"Open until {window.ExpiresAtUtc.LocalDateTime:t}; public release checks are allowed.";
    }

    private void CloseMaintenance_Click(object sender, RoutedEventArgs e)
    {
        maintenance.Close();
        MaintenanceStatus.Text = "Closed; network release checks are disabled.";
    }

    private async void CheckRelease_Click(object sender, RoutedEventArgs e)
    {
        UpdateButtonsEnabled(false);
        try
        {
            var bundle = await CreateReleaseUpdateService().DownloadLatestAsync(CancellationToken.None);
            new AppInstallerLauncher().LaunchVerified(bundle, "CodexRescue.appinstaller");
            MaintenanceStatus.Text = "Verified release downloaded; Windows App Installer is open for operator review.";
        }
        catch (Exception exception) when (
            exception is InvalidDataException or InvalidOperationException or
                System.Security.Cryptography.CryptographicException or HttpRequestException)
        {
            MaintenanceStatus.Text = exception.Message;
        }
        finally
        {
            UpdateButtonsEnabled(true);
        }
    }

    private async void ImportOfflineBundle_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select signed Codex Rescue offline bundle",
            Filter = "Codex Rescue offline bundle (*.zip)|*.zip",
            CheckFileExists = true,
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        UpdateButtonsEnabled(false);
        try
        {
            var cache = CreateReleaseCache();
            var importer = new OfflineBundleImporter(
                new SignedReleaseVerifier(),
                cache,
                PublisherIdentityService.GetCurrentPackagePublisher());
            var bundle = await importer.ImportAsync(dialog.FileName, CancellationToken.None);
            new AppInstallerLauncher().LaunchVerified(bundle, "CodexRescue.appinstaller");
            MaintenanceStatus.Text = "Offline bundle verified; Windows App Installer is open for operator review.";
        }
        catch (Exception exception) when (
            exception is InvalidOperationException or
                System.Security.Cryptography.CryptographicException or IOException)
        {
            MaintenanceStatus.Text = exception.Message;
        }
        finally
        {
            UpdateButtonsEnabled(true);
        }
    }

    private GitHubReleaseUpdateService CreateReleaseUpdateService() => new(
        updateClient,
        maintenance,
        new SignedReleaseVerifier(),
        CreateReleaseCache(),
        PublisherIdentityService.GetCurrentPackagePublisher());

    private static ReleaseCacheManager CreateReleaseCache() => new(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexRescue",
        "VerifiedReleases"));

    private void UpdateButtonsEnabled(bool enabled)
    {
        CheckReleaseButton.IsEnabled = enabled;
        ImportOfflineButton.IsEnabled = enabled;
    }

    private void DisableTelemetry_Click(object sender, RoutedEventArgs e)
    {
        telemetry.Disable();
        TelemetryConsent.IsChecked = false;
        TelemetryStatus.Text = "Disabled; queue cleared.";
    }

    private void ClearTelemetry_Click(object sender, RoutedEventArgs e)
    {
        telemetry.ClearQueue();
        TelemetryStatus.Text = "Queue cleared.";
    }

    private void TestTelemetry_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            telemetry.SetPolicy(TelemetryPolicyLoader.Load(TelemetryConsent.IsChecked == true));
            var endpoint = new Uri(TelemetryEndpoint.Text, UriKind.Absolute);
            TelemetryStatus.Text = telemetry.TestEndpoint(endpoint)
                ? "Synthetic allowlisted endpoint test sent."
                : "Endpoint did not accept the test within the bounded timeout.";
        }
        catch (Exception exception) when (
            exception is InvalidDataException or InvalidOperationException or UriFormatException)
        {
            TelemetryStatus.Text = exception.Message;
        }
    }

    private async void ApplyToolchain_Click(object sender, RoutedEventArgs e)
    {
        if (PackageAgreementsApproved.IsChecked != true)
        {
            MaintenanceStatus.Text = "Review and explicitly accept the applicable package agreements first.";
            return;
        }

        var folder = SelectFolder("Select a non-removable directory for toolchain receipts");
        if (folder is null) { return; }
        const string phrase = "INSTALL CODEX RESCUE TOOLCHAIN";
        var confirmation = new OperatorConfirmationDialog(
            this,
            "Apply exact allowlisted toolchain",
            "UAC begins after approval. The signed action installs only approved package IDs and versions; it does not sign in to any service.",
            phrase,
            destructive: false);
        if (confirmation.ShowDialog() != true) { return; }

        try
        {
            var plan = new BrokerPlanFactory().Create(
                "ApplyToolchain",
                [BrokerPlanFactory.Fingerprint("HOST", Environment.OSVersion.VersionString)],
                ["Package agreements approved", "Read-only host audit reviewed"],
                ["N-1 package cache retained where supported"],
                phrase);
            var request = new BrokerRequestV1(
                BrokerRequestV1.SupportedSchemaVersion,
                plan,
                new ToolchainApplyInputV1(true, folder),
                null,
                null,
                null,
                null);
            var receipt = await new BrokerClient().ExecuteAsync(request, CancellationToken.None);
            MaintenanceStatus.Text = ReceiptSummary(receipt);
        }
        catch (Exception exception)
        {
            MaintenanceStatus.Text = ActionFailure(exception);
        }
    }

    private async void BuildMedia_Click(object sender, RoutedEventArgs e)
    {
        var servicingReceipt = SelectFile("Select verified ADK servicing receipt", "JSON receipt (*.json)|*.json");
        if (servicingReceipt is null) { return; }
        var outputDirectory = SelectFolder("Select media output directory");
        if (outputDirectory is null) { return; }
        var selection = new OperatorInputDialog(this, "Select media profiles", [
            new("artifacts", "Comma-separated artifact IDs", "x64-2023CA,x64-2011CA,arm64-2023CA,arm64-2011CA")
        ]);
        if (selection.ShowDialog() != true) { return; }
        var artifacts = selection.GetValue("artifacts").Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        var target = BrokerPlanFactory.Fingerprint("MEDIA", $"{Path.GetFullPath(outputDirectory)}|{string.Join(',', artifacts)}");
        var phrase = $"BUILD MEDIA {target[^8..]}";
        if (new OperatorConfirmationDialog(
                this,
                "Build selected WinPE media",
                "The builder uses only the selected profiles compatible with the verified servicing receipt. A successful build is not boot evidence.",
                phrase,
                destructive: false).ShowDialog() != true) { return; }

        try
        {
            var plan = new BrokerPlanFactory().Create(
                "BuildMedia",
                [target],
                ["Servicing receipt reviewed", "Output directory selected"],
                ["Existing artifacts are not replaced unless Force is separately introduced"],
                phrase);
            var request = new BrokerRequestV1(
                1,
                plan,
                null,
                new MediaBuildInputV1(servicingReceipt, outputDirectory, artifacts, Force: false),
                null,
                null,
                null);
            BuildStatus.Text = ReceiptSummary(await new BrokerClient().ExecuteAsync(request, CancellationToken.None));
        }
        catch (Exception exception)
        {
            BuildStatus.Text = ActionFailure(exception);
        }
    }

    private async void WriteUsb_Click(object sender, RoutedEventArgs e)
    {
        var isoPath = SelectFile("Select verified Codex Rescue ISO", "ISO image (*.iso)|*.iso");
        if (isoPath is null) { return; }
        var verificationPath = SelectFile("Select matching ISO verification JSON", "JSON verification (*.json)|*.json");
        if (verificationPath is null) { return; }
        var receiptPath = SelectNewFile("Save USB action receipt", "JSON receipt (*.json)|*.json", ".json");
        if (receiptPath is null) { return; }
        var diskPrompt = new OperatorInputDialog(this, "Select one removable USB disk", [
            new("disk", "Windows disk number")
        ]);
        if (diskPrompt.ShowDialog() != true ||
            !int.TryParse(diskPrompt.GetValue("disk"), NumberStyles.None, CultureInfo.InvariantCulture, out var diskNumber))
        {
            UsbStatus.Text = "A numeric Windows disk number is required.";
            return;
        }

        try
        {
            var discovered = await new PackagedPlanRunner().RunAsync(
                ReadOnlyPlanOperation.WriteUsb,
                ["-Mode", "Plan", "-IsoPath", isoPath, "-VerificationPath", verificationPath,
                 "-DiskNumber", diskNumber.ToString(CultureInfo.InvariantCulture), "-AsJson"],
                CancellationToken.None);
            var phrase = RequiredString(discovered, "RequiredConfirmationPhrase");
            var fingerprint = RequiredString(discovered, "TargetFingerprint");
            var summary = $"Disk {diskNumber} · {RequiredString(discovered, "Model")} · serial {RequiredString(discovered, "Serial")} · {RequiredString(discovered, "Bus")} · {RequiredUInt64(discovered, "CapacityBytes"):N0} bytes\nISO {RequiredString(discovered, "TrustPath")} · SHA-256 {RequiredString(discovered, "IsoSha256")}";
            if (new OperatorConfirmationDialog(this, "Erase and write selected USB", summary, phrase, destructive: true).ShowDialog() != true)
            {
                UsbStatus.Text = "Plan reviewed; Apply cancelled with no write requested.";
                return;
            }

            var plan = new BrokerPlanFactory().Create(
                "WriteUsb",
                [fingerprint],
                ["Verified ISO hash matched", "Exactly one removable USB target passed Plan"],
                ["No in-place rollback; target is explicitly disposable"],
                phrase);
            var request = new BrokerRequestV1(
                1,
                plan,
                null,
                null,
                new UsbWriteInputV1(isoPath, verificationPath, diskNumber, receiptPath),
                null,
                null);
            UsbStatus.Text = ReceiptSummary(await new BrokerClient().ExecuteAsync(request, CancellationToken.None));
        }
        catch (Exception exception)
        {
            UsbStatus.Text = ActionFailure(exception);
        }
    }

    private async void PrepareUefi_Click(object sender, RoutedEventArgs e)
    {
        var input = new OperatorInputDialog(this, "Prepare rollback-backed UEFI repair", [
            new("backup", "New absolute backup directory on non-target storage"),
            new("receipt", "New absolute broker receipt JSON path")
        ]);
        if (input.ShowDialog() != true) { return; }
        var backup = input.GetValue("backup");
        var receiptPath = input.GetValue("receipt");
        const string phrase = "PREPARE UEFI BACKUP";
        if (new OperatorConfirmationDialog(
                this,
                "Create and prove UEFI rollback backup",
                "Prepare discovers one Windows/EFI pair, copies the EFI tree to non-target storage, hashes it, and proves the archive can be read. It does not run BCDBoot.",
                phrase,
                destructive: false).ShowDialog() != true) { return; }

        await ExecuteUefiAsync("Prepare", backup, null, receiptPath, phrase);
    }

    private async void ApplyUefi_Click(object sender, RoutedEventArgs e) =>
        await ExecutePreparedUefiAsync("Apply");

    private async void RollbackUefi_Click(object sender, RoutedEventArgs e) =>
        await ExecutePreparedUefiAsync("Rollback");

    private async Task ExecutePreparedUefiAsync(string mode)
    {
        var planPath = SelectFile("Select the proved UEFI repair plan", "UEFI repair plan (*.json)|*.json");
        if (planPath is null) { return; }
        var receiptPath = SelectNewFile($"Save UEFI {mode} receipt", "JSON receipt (*.json)|*.json", ".json");
        if (receiptPath is null) { return; }
        try
        {
            using var document = JsonDocument.Parse(await File.ReadAllBytesAsync(planPath));
            var root = document.RootElement;
            if (!RequiredBoolean(root, "BackupVerified"))
            {
                throw new InvalidDataException("The selected UEFI plan has no proved backup.");
            }
            var fingerprint = RequiredString(root, "TargetFingerprint");
            var phraseProperty = mode == "Apply" ? "RequiredConfirmationPhrase" : "RequiredRollbackPhrase";
            var phrase = RequiredString(root, phraseProperty);
            var title = mode == "Apply" ? "Run minimal BCDBoot repair" : "Restore proved Microsoft boot backup";
            if (new OperatorConfirmationDialog(this, title, $"Target fingerprint …{fingerprint[^8..]}. Identity is re-scanned immediately before {mode}.", phrase, destructive: true).ShowDialog() != true)
            {
                UefiStatus.Text = "Prepared plan reviewed; action cancelled.";
                return;
            }
            await ExecuteUefiAsync(mode, null, planPath, receiptPath, phrase, fingerprint);
        }
        catch (Exception exception)
        {
            UefiStatus.Text = ActionFailure(exception);
        }
    }

    private async Task ExecuteUefiAsync(
        string mode,
        string? backupDirectory,
        string? planPath,
        string receiptPath,
        string phrase,
        string? targetFingerprint = null)
    {
        try
        {
            var target = targetFingerprint ?? BrokerPlanFactory.Fingerprint("UEFI-PREPARE", backupDirectory!);
            var plan = new BrokerPlanFactory().Create(
                "RepairUefi",
                [target],
                [mode == "Prepare" ? "Non-target backup destination selected" : "Proved backup plan selected"],
                ["Readable hashed EFI backup and rollback manifest required"],
                phrase);
            var request = new BrokerRequestV1(
                1,
                plan,
                null,
                null,
                null,
                new UefiRepairInputV1(mode, backupDirectory, planPath, receiptPath),
                null);
            var receipt = await new BrokerClient().ExecuteAsync(request, CancellationToken.None);
            if (mode == "Prepare")
            {
                await WriteNewReceiptAsync(receiptPath, receipt);
                UefiStatus.Text = $"{ReceiptSummary(receipt)} Review {Path.Combine(backupDirectory!, "repair-plan.json")} before Apply.";
            }
            else
            {
                UefiStatus.Text = ReceiptSummary(receipt);
            }
        }
        catch (Exception exception)
        {
            UefiStatus.Text = ActionFailure(exception);
        }
    }

    private async void SalvageBitLocker_Click(object sender, RoutedEventArgs e)
    {
        var input = new OperatorInputDialog(this, "Advanced owner-authorized BitLocker salvage", [
            new("sourceDisk", "Source disk number"),
            new("outputDisk", "Blank disposable output disk number"),
            new("sourceDrive", "Source drive letter without colon"),
            new("outputDrive", "Output drive letter without colon"),
            new("material", "Directory containing exactly one owner-supplied .bek and optional .kpg"),
            new("marker", "Known non-secret marker relative path"),
            new("markerHash", "Known marker SHA-256"),
            new("receipt", "New absolute receipt JSON path")
        ]);
        if (input.ShowDialog() != true) { return; }
        if (!int.TryParse(input.GetValue("sourceDisk"), NumberStyles.None, CultureInfo.InvariantCulture, out var sourceDisk) ||
            !int.TryParse(input.GetValue("outputDisk"), NumberStyles.None, CultureInfo.InvariantCulture, out var outputDisk))
        {
            SalvageStatus.Text = "Numeric source and output disk numbers are required.";
            return;
        }

        try
        {
            var sourceDrive = input.GetValue("sourceDrive");
            var outputDrive = input.GetValue("outputDrive");
            var material = input.GetValue("material");
            var marker = input.GetValue("marker");
            var markerHash = input.GetValue("markerHash");
            var receiptPath = input.GetValue("receipt");
            var commonArguments = new[]
            {
                "-SourceDiskNumber", sourceDisk.ToString(CultureInfo.InvariantCulture),
                "-OutputDiskNumber", outputDisk.ToString(CultureInfo.InvariantCulture),
                "-SourceDrive", sourceDrive,
                "-OutputDrive", outputDrive,
                "-RecoveryMaterialDirectory", material,
                "-KnownMarkerRelativePath", marker,
                "-KnownMarkerSha256", markerHash,
            };
            var discovered = await new PackagedPlanRunner().RunAsync(
                ReadOnlyPlanOperation.SalvageBitLocker,
                ["-Mode", "Plan", .. commonArguments, "-AsJson"],
                CancellationToken.None);
            var phrase = RequiredString(discovered, "RequiredConfirmationPhrase");
            var sourceFingerprint = RequiredString(discovered, "SourceFingerprint");
            var outputFingerprint = RequiredString(discovered, "OutputFingerprint");
            var summary = $"Source disk {sourceDisk} …{sourceFingerprint[^8..]}\nOutput disk {outputDisk} …{outputFingerprint[^8..]} · {RequiredUInt64(discovered, "OutputCapacityBytes"):N0} bytes\nThe output volume will be completely overwritten. Recovery-material names are excluded.";
            if (new OperatorConfirmationDialog(this, "Completely overwrite salvage output", summary, phrase, destructive: true).ShowDialog() != true)
            {
                SalvageStatus.Text = "Plan reviewed; salvage cancelled before Apply.";
                return;
            }

            var plan = new BrokerPlanFactory().Create(
                "SalvageBitLocker",
                [sourceFingerprint, outputFingerprint],
                ["Distinct stable disk identities", "Output blank and at least source size", "Owner-supplied .bek present"],
                ["Source remains unchanged; output is disposable and has no in-place rollback"],
                phrase);
            var request = new BrokerRequestV1(
                1,
                plan,
                null,
                null,
                null,
                null,
                new BitLockerSalvageInputV1(sourceDisk, outputDisk, sourceDrive, outputDrive, material, marker, markerHash, receiptPath));
            SalvageStatus.Text = ReceiptSummary(await new BrokerClient().ExecuteAsync(request, CancellationToken.None));
        }
        catch (Exception exception)
        {
            SalvageStatus.Text = ActionFailure(exception);
        }
    }

    private async void TestProxmox_Click(object sender, RoutedEventArgs e)
    {
        var isoPath = SelectFile("Select verified x64 Codex Rescue ISO", "ISO image (*.iso)|*.iso");
        if (isoPath is null) { return; }
        var verificationPath = SelectFile("Select matching x64 verification JSON", "JSON verification (*.json)|*.json");
        if (verificationPath is null) { return; }
        var dialog = new OperatorInputDialog(this, "Configure one session-only Proxmox test", [
            new("endpoint", "HTTPS Proxmox endpoint", "https://proxmox.example:8006"),
            new("fingerprint", "Server certificate SHA-256 fingerprint"),
            new("node", "Proxmox node"),
            new("storage", "ISO and VM storage"),
            new("token", "Session API token", Secret: true),
            new("cores", "CPU cores", "4"),
            new("memory", "Memory MiB", "8192"),
            new("disk", "Disposable disk GiB", "64"),
            new("minutes", "Maximum run minutes", "20")
        ]);
        if (dialog.ShowDialog() != true) { return; }

        char[] token = [];
        try
        {
            using var verificationDocument = JsonDocument.Parse(await File.ReadAllBytesAsync(verificationPath));
            var verification = verificationDocument.RootElement;
            if (!RequiredBoolean(verification, "VerificationSucceeded") ||
                RequiredBoolean(verification, "ContainsRecoveryMaterial"))
            {
                throw new InvalidDataException("The ISO verification must be successful and secret-free.");
            }
            var architecture = RequiredString(verification, "Architecture");
            if (architecture is not ("amd64" or "x64"))
            {
                throw new InvalidDataException("The Proxmox connector accepts only verified x64 media.");
            }
            var isoHash = RequiredString(verification, "IsoSha256");
            var profile = new ProxmoxProfileV1(
                ProxmoxProfileV1.SupportedSchemaVersion,
                new Uri(dialog.GetValue("endpoint"), UriKind.Absolute),
                dialog.GetValue("fingerprint"),
                new ProxmoxResourceLimitsV1(
                    RequiredOperatorInt(dialog, "cores"),
                    RequiredOperatorInt(dialog, "memory"),
                    RequiredOperatorInt(dialog, "disk"),
                    RequiredOperatorInt(dialog, "minutes")),
                "SessionOnly");
            token = dialog.TakeSecretChars("token");
            using var session = ProxmoxConnectorFactory.Create(profile, token);
            Array.Clear(token);
            token = [];
            var connector = session.CreateConnector();
            var node = dialog.GetValue("node");
            var storage = dialog.GetValue("storage");
            ProxmoxStatus.Text = "Explicit network session open; uploading the hash-verified ISO.";
            var volume = await connector.UploadIsoAsync(node, storage, isoPath, isoHash, CancellationToken.None);
            var vm = await connector.CreateDisconnectedX64UefiVmAsync(node, storage, volume, CancellationToken.None);
            var evidence = await connector.BootAndCollectBoundedEvidenceAsync(vm, CancellationToken.None);
            ProxmoxStatus.Text = $"VM {vm.VmId} reports {evidence.Status}. This is hypervisor power-state evidence, not guest boot proof.";

            var deleteVmPhrase = $"DELETE VM {vm.VmId} {connector.ResourceLabel}";
            if (new OperatorConfirmationDialog(
                    this,
                    "Clean up this session's disposable VM",
                    "Deletion is limited to the tracked VM after its unique label is re-read. Cancelling leaves it in Proxmox for manual inspection.",
                    deleteVmPhrase,
                    destructive: true).ShowDialog() != true) { return; }
            await connector.DeleteTrackedVmAsync(vm, deleteVmPhrase, CancellationToken.None);

            var deleteIsoPhrase = $"DELETE ISO {connector.ResourceLabel}";
            if (new OperatorConfirmationDialog(
                    this,
                    "Delete this session's uploaded ISO",
                    "Deletion is limited to the ISO volume uploaded and tracked by this connector session.",
                    deleteIsoPhrase,
                    destructive: true).ShowDialog() != true)
            {
                ProxmoxStatus.Text = "Disposable VM deleted; labeled ISO retained for manual inspection.";
                return;
            }
            await connector.DeleteTrackedIsoAsync(node, storage, volume, deleteIsoPhrase, CancellationToken.None);
            ProxmoxStatus.Text = "Session VM and uploaded ISO deleted after separate target-bound confirmations.";
        }
        catch (Exception exception)
        {
            ProxmoxStatus.Text = ActionFailure(exception);
        }
        finally
        {
            Array.Clear(token);
        }
    }

    private static int RequiredOperatorInt(OperatorInputDialog dialog, string key) =>
        int.TryParse(dialog.GetValue(key), NumberStyles.None, CultureInfo.InvariantCulture, out var value)
            ? value
            : throw new InvalidDataException($"{key} must be a whole number.");

    private string? SelectFolder(string title)
    {
        var dialog = new OpenFolderDialog { Title = title, Multiselect = false };
        return dialog.ShowDialog(this) == true ? dialog.FolderName : null;
    }

    private string? SelectFile(string title, string filter)
    {
        var dialog = new OpenFileDialog
        {
            Title = title,
            Filter = filter,
            CheckFileExists = true,
            Multiselect = false,
        };
        return dialog.ShowDialog(this) == true ? dialog.FileName : null;
    }

    private string? SelectNewFile(string title, string filter, string extension)
    {
        var dialog = new SaveFileDialog
        {
            Title = title,
            Filter = filter,
            DefaultExt = extension,
            AddExtension = true,
            OverwritePrompt = false,
        };
        return dialog.ShowDialog(this) == true ? dialog.FileName : null;
    }

    private static string RequiredString(JsonElement root, string propertyName)
    {
        var value = root.TryGetProperty(propertyName, out var property) ? property.GetString() : null;
        return !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new InvalidDataException($"Plan lacks {propertyName}.");
    }

    private static ulong RequiredUInt64(JsonElement root, string propertyName) =>
        root.TryGetProperty(propertyName, out var property) && property.TryGetUInt64(out var value)
            ? value
            : throw new InvalidDataException($"Plan lacks {propertyName}.");

    private static bool RequiredBoolean(JsonElement root, string propertyName) =>
        root.TryGetProperty(propertyName, out var property) &&
        property.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? property.GetBoolean()
            : throw new InvalidDataException($"Plan lacks {propertyName}.");

    private static string ReceiptSummary(ActionReceiptV1 receipt) =>
        $"{receipt.Result} · {receipt.NormalizedErrorCode} · restart {receipt.RestartState} · action {receipt.ActionId}";

    private static string ActionFailure(Exception exception) => exception switch
    {
        OperationCanceledException => "Cancelled; no completion was recorded.",
        TimeoutException => "Blocked by a bounded timeout; target state was not inferred.",
        CryptographicException => "Blocked by signature, publisher, certificate, or hash verification.",
        UnauthorizedAccessException => "Blocked by Windows authorization policy.",
        InvalidDataException => "Blocked because the plan, evidence, or target contract is invalid.",
        _ => $"Blocked with normalized category {exception.GetType().Name}; no success receipt was issued.",
    };

    private static async Task WriteNewReceiptAsync(string path, ActionReceiptV1 receipt)
    {
        await using var stream = new FileStream(
            Path.GetFullPath(path),
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None);
        await JsonSerializer.SerializeAsync(stream, receipt);
    }

    private async void ExportSupportBundle_Click(object sender, RoutedEventArgs e)
    {
        var inputDialog = new OpenFileDialog
        {
            Title = "Select action receipts and ISO verification reports",
            Filter = "Codex Rescue JSON evidence (*.json)|*.json",
            CheckFileExists = true,
            Multiselect = true,
        };
        if (inputDialog.ShowDialog(this) != true)
        {
            return;
        }

        var outputDialog = new SaveFileDialog
        {
            Title = "Save sanitized Codex Rescue support bundle",
            Filter = "ZIP support bundle (*.zip)|*.zip",
            AddExtension = true,
            DefaultExt = ".zip",
            OverwritePrompt = false,
        };
        if (outputDialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            await new SupportBundleExporter().ExportAsync(
                inputDialog.FileNames,
                outputDialog.FileName,
                CancellationToken.None);
            ReceiptStatus.Text = "Sanitized support bundle created. Review it before sharing.";
        }
        catch (Exception exception) when (exception is IOException or JsonException)
        {
            ReceiptStatus.Text = exception.Message;
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        maintenance.Close();
        telemetry.Disable();
        updateClient.Dispose();
        base.OnClosed(e);
    }
}
