using CodexRescue.Contracts;

namespace CodexRescue.Broker;

public interface IBrokerAction
{
    Task<ActionReceiptV1> ExecuteAsync(ActionPlanV1 plan, CancellationToken cancellationToken);
}

public sealed class BrokerDispatcher
{
    private readonly IReadOnlyDictionary<BrokerOperation, IBrokerAction> handlers;

    public BrokerDispatcher(IReadOnlyDictionary<BrokerOperation, IBrokerAction> handlers)
    {
        this.handlers = handlers;
    }

    public Task<ActionReceiptV1> ExecuteAsync(
        BrokerOperation operation,
        ActionPlanV1 plan,
        CancellationToken cancellationToken)
    {
        if (!handlers.TryGetValue(operation, out var handler))
        {
            throw new InvalidOperationException("No signed handler is registered for this operation.");
        }

        return handler.ExecuteAsync(plan, cancellationToken);
    }
}
