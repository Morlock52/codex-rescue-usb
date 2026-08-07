using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using CodexRescue.Orchestrator.Services;
using CodexRescue.Orchestrator.Workflow;

namespace CodexRescue.Orchestrator.ViewModels;

public sealed class AuditCardViewModel : INotifyPropertyChanged
{
    private string status;
    private string detail;

    public AuditCardViewModel(string component, string status, string detail)
    {
        Component = component;
        this.status = status;
        this.detail = detail;
    }

    public string Component { get; }

    public string Status
    {
        get => status;
        set
        {
            status = value;
            OnPropertyChanged();
        }
    }

    public string Detail
    {
        get => detail;
        set
        {
            detail = value;
            OnPropertyChanged();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly HostAuditService auditService = new();
    private readonly OrchestratorStateMachine workflow = new();
    private bool isAuditRunning;
    private string auditSummary = "Audit has not run on this host.";

    public MainViewModel()
    {
        AuditCards = new ObservableCollection<AuditCardViewModel>(
        [
            new("Windows host", "PENDING", "Run the local audit."),
            new("WinPE toolchain", "PENDING", "Run the local audit."),
            new("Signing trust", "UNVERIFIED", "A signed release is required."),
            new("Codex CLI", "PENDING", "Run the local audit."),
            new("Proxmox connector", "OPTIONAL", "No endpoint is configured."),
            new("Network & telemetry", "DISABLED", "No requests are made by default."),
        ]);
    }

    public ObservableCollection<AuditCardViewModel> AuditCards { get; }

    public bool IsAuditRunning
    {
        get => isAuditRunning;
        private set
        {
            isAuditRunning = value;
            OnPropertyChanged();
        }
    }

    public string AuditSummary
    {
        get => auditSummary;
        private set
        {
            auditSummary = value;
            OnPropertyChanged();
        }
    }

    public async Task RunAuditAsync(CancellationToken cancellationToken)
    {
        if (IsAuditRunning)
        {
            return;
        }

        IsAuditRunning = true;
        AuditSummary = "Local audit is running. No network requests or changes are permitted.";
        workflow.StartAudit();
        try
        {
            var result = await auditService.AuditAsync(cancellationToken);
            foreach (var observed in result.Components)
            {
                var card = AuditCards.Single(item => item.Component == observed.Component);
                card.Status = observed.Disposition.ToString().ToUpperInvariant();
                card.Detail = observed.Detail;
            }

            var windowsReady = result.Components.Single(item => item.Component == "Windows host")
                .Disposition == AuditDisposition.Installed;
            workflow.CompleteAudit(windowsReady, "This host is not a supported Windows build host.");
            AuditSummary = workflow.Stage == OrchestratorStage.PlanReady
                ? "Audit complete. Review missing or unverified components before preparing an Apply plan."
                : workflow.BlockReason ?? "Audit is blocked.";
        }
        finally
        {
            IsAuditRunning = false;
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
