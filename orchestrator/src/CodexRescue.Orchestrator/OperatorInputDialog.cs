using System.Windows;
using System.Windows.Controls;

namespace CodexRescue.Orchestrator;

public sealed record OperatorField(
    string Key,
    string Label,
    string DefaultValue = "",
    bool Secret = false);

public sealed class OperatorInputDialog : Window
{
    private readonly Dictionary<string, Control> controls = new(StringComparer.Ordinal);

    public OperatorInputDialog(Window owner, string title, IReadOnlyList<OperatorField> fields)
    {
        Owner = owner;
        Title = title;
        Width = 680;
        MaxHeight = 820;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var form = new StackPanel { Margin = new Thickness(28) };
        form.Children.Add(new TextBlock { Text = title, FontSize = 25, FontWeight = FontWeights.Bold });
        foreach (var field in fields)
        {
            form.Children.Add(new TextBlock
            {
                Text = field.Label,
                FontWeight = FontWeights.Bold,
                Margin = new Thickness(0, 14, 0, 5),
            });
            Control control;
            if (field.Secret)
            {
                control = new PasswordBox { Password = field.DefaultValue };
            }
            else
            {
                control = new TextBox { Text = field.DefaultValue };
            }
            control.SetValue(System.Windows.Automation.AutomationProperties.NameProperty, field.Label);
            controls.Add(field.Key, control);
            form.Children.Add(control);
        }

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 22, 0, 0),
        };
        buttons.Children.Add(new Button { Content = "Cancel", IsCancel = true, MinWidth = 92 });
        var next = new Button
        {
            Content = "Review plan",
            IsDefault = true,
            MinWidth = 120,
            Margin = new Thickness(8, 0, 0, 0),
        };
        next.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(next);
        form.Children.Add(buttons);
        Content = new ScrollViewer { Content = form, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    public string GetValue(string key) => controls.TryGetValue(key, out var control)
        ? control switch
        {
            TextBox textBox => textBox.Text.Trim(),
            PasswordBox passwordBox => passwordBox.Password,
            _ => throw new InvalidOperationException("Unsupported operator field control."),
        }
        : throw new KeyNotFoundException("Operator field was not defined.");

    public char[] TakeSecretChars(string key)
    {
        if (!controls.TryGetValue(key, out var control) || control is not PasswordBox passwordBox)
        {
            throw new KeyNotFoundException("Secret operator field was not defined.");
        }

        var value = passwordBox.Password.ToCharArray();
        passwordBox.Clear();
        return value;
    }
}
