using CodexRescue.Contracts;

namespace CodexRescue.Broker;

public sealed class BrokerRequestValidator
{
    public void Validate(BrokerRequestV1 request, BrokerOperation operation)
    {
        ArgumentNullException.ThrowIfNull(request);
        var presentInputs = new object?[]
        {
            request.ApplyToolchain,
            request.BuildMedia,
            request.WriteUsb,
            request.RepairUefi,
            request.SalvageBitLocker,
        }.Count(input => input is not null);
        if (presentInputs != 1)
        {
            throw new InvalidDataException("Exactly one typed broker input is required.");
        }

        var matchesOperation = operation switch
        {
            BrokerOperation.ApplyToolchain => request.ApplyToolchain is not null,
            BrokerOperation.BuildMedia => request.BuildMedia is not null,
            BrokerOperation.WriteUsb => request.WriteUsb is not null,
            BrokerOperation.RepairUefi => request.RepairUefi is not null,
            BrokerOperation.SalvageBitLocker => request.SalvageBitLocker is not null,
            _ => false,
        };
        if (!matchesOperation)
        {
            throw new InvalidDataException("Typed broker input does not match the signed action plan.");
        }
    }
}
