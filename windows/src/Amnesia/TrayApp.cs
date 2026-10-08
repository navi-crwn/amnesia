// The tray icon (next to the clock) and its menu. The window is only created while it is open,
// so when it is closed Amnesia is just this small icon.
namespace Amnesia;

sealed class TrayApp : ApplicationContext
{
    readonly NotifyIcon icon;
    MainWindow? window;

    public TrayApp()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open Amnesia", null, (_, _) => Open());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Quit());

        icon = new NotifyIcon
        {
            Icon = AppInfo.Icon,
            Text = $"Amnesia {AppInfo.Version} (early preview)",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) Open(); };
        Open();
    }

    void Open()
    {
        if (window is { IsDisposed: false }) { window.Activate(); return; }
        window = new MainWindow();
        window.FormClosed += (_, _) => window = null;
        window.Show();
    }

    void Quit()
    {
        window?.Close();
        icon.Visible = false;
        icon.Dispose();
        ExitThread();
    }
}
