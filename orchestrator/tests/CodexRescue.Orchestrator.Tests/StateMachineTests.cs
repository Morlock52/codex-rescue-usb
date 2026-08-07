using CodexRescue.Orchestrator.Workflow;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class StateMachineTests
{
    [TestMethod]
    public void UacCancellationDoesNotAdvanceWorkflow()
    {
        var workflow = new OrchestratorStateMachine();
        workflow.StartAudit();
        workflow.CompleteAudit(prerequisitesSatisfied: true);
        workflow.RequestApproval();

        workflow.ApplyStarted(elevationAccepted: false);

        Assert.AreEqual(OrchestratorStage.PlanReady, workflow.Stage);
    }

    [TestMethod]
    public void InvalidTransitionIsRejected()
    {
        var workflow = new OrchestratorStateMachine();

        Assert.ThrowsExactly<InvalidOperationException>(workflow.RequestApproval);
    }
}
