using Microsoft.Win32;

namespace CodexRescue.Orchestrator.Services;

public static class TelemetryPolicyLoader
{
    private const string PolicyPath = @"SOFTWARE\Policies\CodexRescue";

    public static TelemetryPolicy Load(bool operatorConsent)
    {
        using var key = Registry.LocalMachine.OpenSubKey(PolicyPath, writable: false);
        var administratorPolicyAllows = key?.GetValue("EnableTelemetry") is int value && value == 1;
        return new TelemetryPolicy
        {
            AdministratorPolicyAllows = administratorPolicyAllows,
            OperatorConsent = operatorConsent,
        };
    }
}
