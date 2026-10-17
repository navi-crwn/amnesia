// v0.7: a small "enter your PIN / password" window, for the lab lock and the Keep lock (outside the main page:
// tray menu, Desktop shortcut, the uninstaller).
namespace Amnesia;

static class PinPrompt
{
    /// <summary>Shows the prompt until check() accepts the text or you cancel. Returns the accepted text, or null.</summary>
    public static string? Ask(IWin32Window? owner, string title, string text, bool digitsOnly, Func<string, bool> check)
    {
        using var f = new Form
        {
            Text = title, FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
            StartPosition = owner == null ? FormStartPosition.CenterScreen : FormStartPosition.CenterParent,
            ClientSize = new Size(360, 150), TopMost = owner == null, ShowInTaskbar = owner == null, Icon = AppInfo.Icon,
            Font = new Font("Segoe UI", 9.5f),
        };
        var label = new Label { Text = text, Left = 14, Top = 12, Width = 332, Height = 38 };
        var box = new TextBox { Left = 14, Top = 54, Width = 332, UseSystemPasswordChar = true };
        if (digitsOnly) box.KeyPress += (_, e) => { if (!char.IsControl(e.KeyChar) && !char.IsAsciiDigit(e.KeyChar)) e.Handled = true; };
        var wrong = new Label { Left = 14, Top = 82, Width = 332, Height = 20, ForeColor = Color.Firebrick };
        var ok = new Button { Text = "OK", Left = 178, Top = 110, Width = 80 };
        var cancel = new Button { Text = AppInfo.Id ? "Batal" : "Cancel", Left = 266, Top = 110, Width = 80, DialogResult = DialogResult.Cancel };
        string? result = null;
        ok.Click += (_, _) =>
        {
            if (check(box.Text)) { result = box.Text; f.DialogResult = DialogResult.OK; f.Close(); }
            else { wrong.Text = AppInfo.Id ? "Salah, coba lagi." : "Wrong, try again."; box.SelectAll(); box.Focus(); }
        };
        // v0.8: longer texts (the uninstaller's question) get the room they need
        int extra = Math.Max(0, TextRenderer.MeasureText(text, f.Font, new Size(label.Width, 1000), TextFormatFlags.WordBreak).Height - label.Height);
        if (extra > 0)
        {
            label.Height += extra;
            foreach (var c in new Control[] { box, wrong, ok, cancel }) c.Top += extra;
            f.ClientSize = new Size(f.ClientSize.Width, f.ClientSize.Height + extra);
        }
        f.Controls.AddRange(new Control[] { label, box, wrong, ok, cancel });
        f.AcceptButton = ok; f.CancelButton = cancel;
        f.ShowDialog(owner);
        return result;
    }
}
