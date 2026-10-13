// v0.7 Lab lock (Settings → Advanced → Lab lock). For a PC many people use (computer lab, library): an administrator
// sets a PIN, and from then on this Windows user can't switch Amnesia off, pause it, quit it, uninstall it or change
// its settings or Keep List without that PIN. The locked copy lives in a folder only administrators can change:
//   %ProgramData%\Amnesia\lab\lab.conf   PIN (hashed, see Pin.cs) + the settings that were active when it was locked
//   %ProgramData%\Amnesia\lab\keep.conf  the Keep List at that moment
// Amnesia always counts as On while locked, and Windows starts it for this user from HKLM\...\Run (admins only).
// Honest limits: someone can still end Amnesia in Task Manager; the next sign in check cleans anyway.
namespace Amnesia.Core;

public static class Lab
{
    /// <summary>Settings an administrator locks. Everything else (language, last update check...) stays per user.</summary>
    public static readonly string[] PolicyKeys =
    {
        "KEEP_DIR", "IDLE_MIN", "PANIC_HOTKEY", "USB_KEY", "USB_KEY_NAME", "USB_ACTION", "REMOVE_NEW_APPS",
        "EXTRA_LIST", "KEEP_SHORTCUT", "KEEP_PIN", "UPDATE_DAYS", "DOOMSDAY",
    };

    public static string Dir => Environment.GetEnvironmentVariable("AMNESIA_LAB_DIR") is { Length: > 0 } d ? d
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Amnesia", "lab");
    public static string ConfFile => Path.Combine(Dir, "lab.conf");
    public static string KeepFile => Path.Combine(Dir, "keep.conf");

    public static bool Active
    {
        get { try { return File.Exists(ConfFile); } catch { return false; } }
    }

    /// <summary>A value from lab.conf (null when not locked or not set there).</summary>
    public static string? Get(string key)
    {
        if (!Active) return null;
        try
        {
            string? v = null;
            foreach (var l in File.ReadAllLines(ConfFile))
                if (l.StartsWith(key + "=", StringComparison.Ordinal)) v = l[(key.Length + 1)..];
            return v;
        }
        catch { return null; }
    }

    /// <summary>Checks a PIN against the one in lab.conf.</summary>
    public static bool Check(string pin) => Pin.Verify(pin, Get("PIN"));

    /// <summary>Writes what the administrator copy will move into the locked folder: lab.conf + keep.conf, into stage.</summary>
    public static void Stage(string stage, string pin, string exe)
    {
        Directory.CreateDirectory(stage);
        var lines = new List<string> { "PIN=" + Pin.Hash(pin), "EXE=" + exe, "LOCKED=" + DateTime.Now.ToString("yyyy-MM-dd HH:mm") };
        foreach (var k in PolicyKeys) if (Conf.GetOwn(k) is { } v) lines.Add($"{k}={v}");
        File.WriteAllLines(Path.Combine(stage, "lab.conf"), lines);
        var keep = Path.Combine(Home.Dir, "keep.conf");
        if (File.Exists(keep)) File.Copy(keep, Path.Combine(stage, "keep.conf"), true);
        else File.WriteAllText(Path.Combine(stage, "keep.conf"), "");
    }
}
