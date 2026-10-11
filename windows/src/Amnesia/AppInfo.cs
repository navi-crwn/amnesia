// Where Amnesia keeps its things. Same layout as the Mac: everything lives in ~\.amnesia (see Amnesia.Core\Home.cs).
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

    /// <summary>%USERPROFILE%\.amnesia: settings.conf, keep.conf, vault, logs.</summary>
    public static string Home => Core.Home.Dir;

    /// <summary>One line in %USERPROFILE%\.amnesia\trace.log. Steps only, never file names.</summary>
    public static void Trace(string step) => Core.Home.Trace("app", step);

    /// <summary>WebView2's own data. Kept out of the cleanup.</summary>
    public static string WebViewData => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Amnesia", "WebView2");

    /// <summary>English or Indonesian: LANG in settings (Settings page), else the language of Windows.</summary>
    public static bool Id => Core.Conf.Get("LANG") switch
    {
        "id" => true,
        "en" => false,
        _ => System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "id",
    };
}
