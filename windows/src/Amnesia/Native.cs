// The few Windows functions .NET has no wrapper for.
using System.Runtime.InteropServices;

namespace Amnesia;

static class Native
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool ShutdownBlockReasonCreate(IntPtr hWnd, string reason);
    [DllImport("user32.dll")]
    public static extern bool ShutdownBlockReasonDestroy(IntPtr hWnd);
    [DllImport("kernel32.dll")]
    public static extern bool SetProcessShutdownParameters(uint level, uint flags);
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    /// <summary>Dark or light title bar, so it matches the page (Windows 10 2004+ / 11).</summary>
    public static void DarkTitleBar(IntPtr hwnd, bool dark)
    {
        int v = dark ? 1 : 0;
        if (DwmSetWindowAttribute(hwnd, 20, ref v, sizeof(int)) != 0) DwmSetWindowAttribute(hwnd, 19, ref v, sizeof(int));
    }

    /// <summary>True when Windows apps are set to dark (Settings → Personalization → Colors).</summary>
    public static bool AppsDark()
    {
        using var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return k?.GetValue("AppsUseLightTheme") is int i && i == 0;
    }
}
