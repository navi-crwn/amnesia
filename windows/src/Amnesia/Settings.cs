// settings.conf in %USERPROFILE%\.amnesia (Amnesia.Core\Conf.cs does the reading and writing).
using Amnesia.Core;

namespace Amnesia;

static class Settings
{
    public static string? Get(string key) => Conf.Get(key);
    public static void Set(string key, string? value) => Conf.Set(key, value);

    public static bool Enabled => Conf.Enabled;
    /// <summary>v0.3: shortcut to the Keep folder on the Desktop / pin in Explorer's side bar. On unless switched off.</summary>
    public static bool KeepShortcut => Get("KEEP_SHORTCUT") != "0";
    public static bool KeepPin => Get("KEEP_PIN") != "0";
    public static string KeepDir => Conf.KeepDir;
    public static string PauseFile => Conf.PauseFile;
    public static bool Paused => Conf.Paused;
    /// <summary>v0.7: days between automatic update checks (0 = never). Old "UPDATE_CHECK=0" (switch off) stays off.</summary>
    public static int UpdateDays => Get("UPDATE_DAYS") is { } d && int.TryParse(d, out var n) ? n : Get("UPDATE_CHECK") == "0" ? 0 : 7;
}
