using CodexRescue.Broker;
using CodexRescue.Contracts;

namespace CodexRescue.Orchestrator.Tests;

[TestClass]
public sealed class PlanValidatorTests
{
    [TestMethod]
    public void ExpiredPlanIsRejected()
    {
        var plan = CreatePlan() with { ExpiresAtUtc = DateTimeOffset.UtcNow.AddMinutes(-1) };

        Assert.ThrowsExactly<InvalidDataException>(() => new PlanValidator().ValidateForExecution(
            plan,
            "0.1.0",
            new string('A', 64),
            DateTimeOffset.UtcNow));
    }

    [TestMethod]
    public void UnknownOperationIsRejected()
    {
        var plan = CreatePlan() with { ActionType = "RunAnything" };

        Assert.ThrowsExactly<InvalidDataException>(() => new PlanValidator().ValidateForExecution(
            plan,
            "0.1.0",
            new string('A', 64),
            DateTimeOffset.UtcNow));
    }

    private static ActionPlanV1 CreatePlan() => new(
        1,
        Guid.NewGuid(),
        "BuildMedia",
        "0.1.0",
        ["TARGET-1"],
        ["Audit passed"],
        ["Retain prior artifact"],
        "BUILD TARGET-1",
        DateTimeOffset.UtcNow.AddMinutes(10),
        new string('A', 64));
}
