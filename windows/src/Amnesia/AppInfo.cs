// Where Amnesia keeps its things. Same layout as the Mac: everything lives in ~\.amnesia.
namespace Amnesia;

static class AppInfo
{
    public static string Version =>
        typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

    /// <summary>The Amnesia logo (from amnesia.ico, built into Amnesia.exe).</summary>
    public static Icon Icon => icon ??= Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application;
    static Icon? icon;

    /// <summary>Folder next to Amnesia.exe (ui\ and scripts\ ship there).</summary>
    public static string BaseDir => AppContext.BaseDirectory;

    /// <summary>%USERPROFILE%\.amnesia: settings.conf, keep.conf, logs.</summary>
    public static string Home => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".amnesia");

    /// <summary>WebView2's own data. Kept out of the cleanup (see scripts\clean.ps1).</summary>
    public static string WebViewData => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Amnesia", "WebView2");
}
