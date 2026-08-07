using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CodexRescue.Orchestrator;

public sealed class OperatorConfirmationDialog : Window
{
    private readonly string requiredPhrase;
    private readonly TextBox confirmation = new();
    private readonly Button applyButton;

    public OperatorConfirmationDialog(
        Window owner,
        string title,
        string summary,
        string requiredPhrase,
        bool destructive)
    {
        Owner = owner;
        Title = title;
        this.requiredPhrase = requiredPhrase;
        Width = 660;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        applyButton = new Button
        {
            Content = destructive ? "Approve destructive action" : "Approve and continue",
            IsDefault = true,
            IsEnabled = false,
            MinWidth = 170,
            Margin = new Thickness(8, 0, 0, 0),
        };

        var panel = new StackPanel { Margin = new Thickness(28) };
        panel.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 25,
            FontWeight = FontWeights.Bold,
            Foreground = destructive ? Brushes.Firebrick : Brushes.Black,
        });
        panel.Children.Add(new TextBlock
        {
            Text = summary,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 12, 0, 16),
        });
        panel.Children.Add(new TextBlock { Text = "Type this target-bound phrase exactly:", FontWeight = FontWeights.Bold });
        panel.Children.Add(new TextBlock
        {
            Text = requiredPhrase,
            FontFamily = new FontFamily("IBM Plex Mono, Consolas"),
            Margin = new Thickness(0, 7, 0, 8),
            TextWrapping = TextWrapping.Wrap,
        });
        confirmation.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, "Confirmation phrase");
        confirmation.TextChanged += (_, _) => applyButton.IsEnabled =
            string.Equals(confirmation.Text, this.requiredPhrase, StringComparison.Ordinal);
        panel.Children.Add(confirmation);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 20, 0, 0),
        };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 92 };
        applyButton.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel);
        buttons.Children.Add(applyButton);
        panel.Children.Add(buttons);
        Content = panel;
    }
}
