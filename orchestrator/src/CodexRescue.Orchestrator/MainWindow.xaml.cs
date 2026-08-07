using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Text.Json;
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
