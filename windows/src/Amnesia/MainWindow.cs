// The Amnesia window: a WebView2 that shows ui\index.html. Buttons on the page send a message
// to C# (Bridge.cs); C# does the real work and sends the answer back to the page.
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Amnesia;

sealed class MainWindow : Form
{
    const string Host = "app.amnesia"; // pages are served as https://app.amnesia/... from the ui folder, never from the internet
    readonly WebView2 web = new() { Dock = DockStyle.Fill };

    public MainWindow()
    {
        Text = "Amnesia";
        ClientSize = new Size(920, 640);
        MinimumSize = new Size(640, 480);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = AppInfo.Icon;
        BackColor = Color.FromArgb(7, 7, 10); // same as the page background, so there is no white flash
        web.DefaultBackgroundColor = BackColor;
        Controls.Add(web);
        Load += async (_, _) => await StartAsync();
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

        var bridge = new Bridge();
        core.WebMessageReceived += async (_, e) =>
        {
            if (!e.Source.StartsWith($"https://{Host}/", StringComparison.OrdinalIgnoreCase)) return;
            var answer = await bridge.HandleAsync(e.WebMessageAsJson);
            core.PostWebMessageAsJson(answer);
        };

        core.Navigate($"https://{Host}/index.html");
    }

    static void OpenInBrowser(string uri)
    {
        if (uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
    }
}
