using System.Runtime.InteropServices;
using Windows.ApplicationModel;

namespace CodexRescue.Orchestrator.Services;

public static class PublisherIdentityService
{
    public static string GetCurrentPackagePublisher()
    {
        try
        {
            var publisher = Package.Current.Id.Publisher;
            if (string.IsNullOrWhiteSpace(publisher))
            {
                throw new InvalidOperationException("The installed package publisher is empty.");
            }

            return publisher;
        }
        catch (COMException exception)
        {
            throw new InvalidOperationException(
                "Signed updates require a signed MSIX package context; source builds cannot self-update.",
                exception);
        }
        catch (InvalidOperationException exception) when (
            !exception.Message.Contains("signed MSIX package context", StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Signed updates require a signed MSIX package context; source builds cannot self-update.",
                exception);
        }
    }
}
