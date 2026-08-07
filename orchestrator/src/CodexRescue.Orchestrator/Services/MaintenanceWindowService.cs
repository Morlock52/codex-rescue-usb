namespace CodexRescue.Orchestrator.Services;

public sealed record MaintenanceWindow(
    bool NetworkConsent,
    DateTimeOffset OpenedAtUtc,
    DateTimeOffset ExpiresAtUtc);

public sealed class MaintenanceWindowService
{
    private static readonly TimeSpan MaximumDuration = TimeSpan.FromMinutes(30);
    private readonly TimeProvider _timeProvider;
    private MaintenanceWindow? _active;

    public MaintenanceWindowService(TimeProvider? timeProvider = null) =>
        _timeProvider = timeProvider ?? TimeProvider.System;

    public MaintenanceWindow Open(bool NetworkConsent)
    {
        if (!NetworkConsent)
        {
            throw new InvalidOperationException("Network consent is required to open a maintenance window.");
        }

        var now = _timeProvider.GetUtcNow();
        _active = new MaintenanceWindow(NetworkConsent, now, now.Add(MaximumDuration));
        return _active;
    }

    public MaintenanceWindow RequireOpen()
    {
        var window = _active;
        if (window is null || !window.NetworkConsent || window.ExpiresAtUtc <= _timeProvider.GetUtcNow())
        {
            Close();
            throw new InvalidOperationException("The operator-approved maintenance window is closed or expired.");
        }

        return window;
    }

    public void Close() => _active = null;
}
