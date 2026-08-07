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

    [TestMethod]
    public void BrokerRequestWithMultipleTypedInputsIsRejected()
    {
        var request = new BrokerRequestV1(
            1,
            CreatePlan(),
            null,
            new MediaBuildInputV1(@"C:\receipt.json", @"C:\output", ["x64-2023CA"], false),
            new UsbWriteInputV1(@"C:\rescue.iso", @"C:\verify.json", 7, @"C:\usb-receipt.json"),
            null,
            null);

        Assert.ThrowsExactly<InvalidDataException>(() =>
            new BrokerRequestValidator().Validate(request, BrokerOperation.BuildMedia));
    }

    [TestMethod]
    public void BrokerRequestInputMustMatchPlanOperation()
    {
        var request = new BrokerRequestV1(
            1,
            CreatePlan(),
            null,
            null,
            new UsbWriteInputV1(@"C:\rescue.iso", @"C:\verify.json", 7, @"C:\usb-receipt.json"),
            null,
            null);

        Assert.ThrowsExactly<InvalidDataException>(() =>
            new BrokerRequestValidator().Validate(request, BrokerOperation.BuildMedia));
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
