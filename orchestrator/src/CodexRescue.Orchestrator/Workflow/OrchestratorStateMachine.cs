namespace CodexRescue.Orchestrator.Workflow;

public enum OrchestratorStage
{
    Idle,
    AuditRunning,
    PlanReady,
    AwaitingApproval,
    Applying,
    RestartRequired,
    Verifying,
    Completed,
    Blocked
}

public sealed class OrchestratorStateMachine
{
    public OrchestratorStage Stage { get; private set; } = OrchestratorStage.Idle;

    public string? BlockReason { get; private set; }

    public void StartAudit()
    {
        Require(OrchestratorStage.Idle, OrchestratorStage.Completed, OrchestratorStage.Blocked);
        BlockReason = null;
        Stage = OrchestratorStage.AuditRunning;
    }

    public void CompleteAudit(bool prerequisitesSatisfied, string? reason = null)
    {
        Require(OrchestratorStage.AuditRunning);
        if (!prerequisitesSatisfied)
        {
            Block(reason ?? "One or more prerequisites are blocked.");
            return;
        }

        Stage = OrchestratorStage.PlanReady;
    }

    public void RequestApproval()
    {
        Require(OrchestratorStage.PlanReady);
        Stage = OrchestratorStage.AwaitingApproval;
    }

    public void ApplyStarted(bool elevationAccepted)
    {
        Require(OrchestratorStage.AwaitingApproval);
        if (!elevationAccepted)
        {
            UacCancelled();
            return;
        }

        Stage = OrchestratorStage.Applying;
    }

    public void UacCancelled()
    {
        Require(OrchestratorStage.AwaitingApproval);
        Stage = OrchestratorStage.PlanReady;
    }

    public void CompleteApply(bool restartRequired)
    {
        Require(OrchestratorStage.Applying);
        Stage = restartRequired
            ? OrchestratorStage.RestartRequired
            : OrchestratorStage.Verifying;
    }

    public void ResumeAfterRestart()
    {
        Require(OrchestratorStage.RestartRequired);
        Stage = OrchestratorStage.Verifying;
    }

    public void CompleteVerification(bool verified, string? reason = null)
    {
        Require(OrchestratorStage.Verifying);
        if (!verified)
        {
            Block(reason ?? "Post-action verification did not pass.");
            return;
        }

        Stage = OrchestratorStage.Completed;
    }

    private void Block(string reason)
    {
        BlockReason = reason;
        Stage = OrchestratorStage.Blocked;
    }

    private void Require(params OrchestratorStage[] allowed)
    {
        if (!allowed.Contains(Stage))
        {
            throw new InvalidOperationException(
                $"Stage {Stage} cannot perform this transition. Allowed: {string.Join(", ", allowed)}.");
        }
    }
}
