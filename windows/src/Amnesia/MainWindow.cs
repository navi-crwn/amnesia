// The Amnesia window: a WebView2 that shows ui\index.html. Buttons on the page send a message
// to C# (Bridge.cs); C# does the real work and sends the answer back to the page.
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Amnesia;

sealed class MainWindow : Form
{
    const string Host = "app.amnesia"; // pages are served as https://app.amnesia/... from the ui folder, never from the internet
    readonly WebView2 web = new() { Dock = DockStyle.Fill };
    readonly TrayApp tray;

    public MainWindow(TrayApp tray)
    {
        this.tray = tray;
        Text = "Amnesia";
        // v0.4: fits small screens (and "Larger text"): at most 90% of the screen, never smaller than 520 x 460
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        // v0.6: same shape as the Mac window (a narrow column), taller if the screen allows
        ClientSize = new Size(Math.Min(560, (int)(area.Width * 0.9)), Math.Min(780, (int)(area.Height * 0.9)));
        MinimumSize = new Size(420, 460);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = AppInfo.Icon;
        BackColor = Color.FromArgb(7, 7, 10); // same as the page background, so there is no white flash
        web.DefaultBackgroundColor = BackColor;
        Controls.Add(web);
        Load += async (_, _) => await StartAsync();
        HandleCreated += (_, _) => Native.DarkTitleBar(Handle, Native.AppsDark());
        // follow Windows when the user switches light/dark while Amnesia is open
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += ThemeChanged;
        FormClosed += (_, _) => Microsoft.Win32.SystemEvents.UserPreferenceChanged -= ThemeChanged;
    }

    void ThemeChanged(object? sender, Microsoft.Win32.UserPreferenceChangedEventArgs e)
    {
        if (e.Category == Microsoft.Win32.UserPreferenceCategory.General && IsHandleCreated)
            BeginInvoke(() => { Native.DarkTitleBar(Handle, Native.AppsDark()); Refresh(); });
    }

    async Task StartAsync()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, AppInfo.WebViewData);
            await web.EnsureCoreWebView2Async(env);
        }
        catch (WebView2RuntimeNotFoundException)
        {
            MessageBox.Show(this,
                "Amnesia needs Microsoft Edge WebView2, which is part of Windows 10 and 11.\n" +
                "It seems to be missing. Install it from https://go.microsoft.com/fwlink/p/?LinkId=2124703 and open Amnesia again.",
                "Amnesia", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            Close();
            return;
        }

        var core = web.CoreWebView2;
        var s = core.Settings;
        s.AreDevToolsEnabled = System.Diagnostics.Debugger.IsAttached;
        s.AreDefaultContextMenusEnabled = false;
        s.IsStatusBarEnabled = false;
        s.IsZoomControlEnabled = false;
        s.AreBrowserAcceleratorKeysEnabled = false;

        core.SetVirtualHostNameToFolderMapping(Host, Path.Combine(AppInfo.BaseDir, "ui"), CoreWebView2HostResourceAccessKind.Deny);
        // links to websites open in the normal browser, never inside Amnesia
        core.NewWindowRequested += (_, e) => { e.Handled = true; OpenInBrowser(e.Uri); };
        core.NavigationStarting += (_, e) =>
        {
            if (!e.Uri.StartsWith($"https://{Host}/", StringComparison.OrdinalIgnoreCase)) { e.Cancel = true; OpenInBrowser(e.Uri); }
        };

        var bridge = new Bridge(tray,
            // progress of long jobs, sent from worker threads
            ev => BeginInvoke(() => { try { core.PostWebMessageAsJson(ev.ToJsonString()); } catch { } }),
            // folder / file pickers need the window thread and the window as owner
            show =>
            {
                var tcs = new TaskCompletionSource<string?>();
                BeginInvoke(() => { try { tcs.SetResult(show(this)); } catch (Exception e) { tcs.SetException(e); } });
                return tcs.Task;
            });
        core.WebMessageReceived += async (_, e) =>
        {
            if (!e.Source.StartsWith($"https://{Host}/", StringComparison.OrdinalIgnoreCase)) return;
            var answer = await bridge.HandleAsync(e.WebMessageAsJson);
            core.PostWebMessageAsJson(answer);
        };

        // v0.3: the page only scrolls with the mouse wheel when it has the keyboard focus (it sometimes didn't
        // after opening from the tray), so give it the focus when it has loaded and whenever the window comes forward
        core.NavigationCompleted += (_, _) => web.Focus();
        Activated += (_, _) => web.Focus();

        core.Navigate($"https://{Host}/index.html");
    }

    /// <summary>Shows a page (tray menu "Review and sign out", notifications).</summary>
    public void ShowView(string view)
    {
        try { web.CoreWebView2?.PostWebMessageAsJson(new System.Text.Json.Nodes.JsonObject { ["event"] = "view", ["view"] = view }.ToJsonString()); } catch { }
    }

    /// <summary>Loads the page again (after Turn On / Off from the tray menu).</summary>
    public void Reload() { try { web.CoreWebView2?.Reload(); } catch { } }

    static void OpenInBrowser(string uri)
    {
        if (uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
    }
}
