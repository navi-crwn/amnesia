// v0.3: quick ways to your Keep folder. A shortcut on the Desktop ("Keep.lnk") and a pin in Explorer's side bar
// (Quick access). The Desktop and Windows' recent items (where the pin lives) are wiped at every sign out, so
// Amnesia puts both back after each sign in check, at Turn On, and when you switch them in Settings.
// clean.ps1 leaves the Desktop shortcut alone (KEEP_SHORTCUT in settings.conf).
// v0.7.1: while the Keep lock is on and Keep is locked, the pin is taken out (Explorer kept trying to read the locked
// folder through it); it comes back when you open Keep. And after the Keep icon changes, the pin is taken out and put
// back once, so the side bar shows the new icon too (it kept the plain yellow one).
namespace Amnesia;

static class KeepLinks
{
    const string QuickAccess = "shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}";
    static readonly object Lock = new();

    static string DesktopDir => Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    public static string DesktopLink => Path.Combine(DesktopDir, Path.GetFileName(Settings.KeepDir) + ".lnk");

    /// <summary>Puts the shortcut and the pin in place (or takes them away) to match Settings. Never blocks the caller.</summary>
    public static void Sync() => Start();

    /// <summary>Same as Sync, but waits until it is done (uninstall).</summary>
    public static void SyncNow() => Start().Join(10_000);

    /// <summary>v0.7.1: only the Quick access pin (Keep was locked or opened). Never blocks the caller.</summary>
    public static void SyncPin() => Start(pinOnly: true);

    static Thread Start(bool pinOnly = false)
    {
        // Windows' shell objects want a single-threaded apartment
        var t = new Thread(() =>
        {
            lock (Lock)
            {
                bool iconChanged = false;
                if (!pinOnly)
                {
                    // v0.7.1: desktop.ini can be read while Keep is locked, so the lock is only opened when the icon must change
                    try { iconChanged = !IconOk() && KeepLock.With(Icon); } catch (Exception e) { AppInfo.Trace($"keep icon failed: {e.GetType().Name}"); }
                    try { Shortcut(); } catch (Exception e) { AppInfo.Trace($"keep shortcut failed: {e.GetType().Name}"); }
                }
                try { Pin(repin: iconChanged); } catch (Exception e) { AppInfo.Trace($"keep pin failed: {e.GetType().Name}"); }
            }
        }) { IsBackground = true };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        return t;
    }

    /// <summary>Opens the Keep folder in Explorer (makes it first if it is missing).</summary>
    public static void OpenKeep()
    {
        var keep = Settings.KeepDir;
        Directory.CreateDirectory(keep);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe") { ArgumentList = { keep } });
    }

    static bool Same(string? a, string? b) =>
        !string.IsNullOrEmpty(a) && !string.IsNullOrEmpty(b) &&
        string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    static dynamic Com(string progId) => Activator.CreateInstance(Type.GetTypeFromProgID(progId)!)!;

    static void Shortcut()
    {
        var keep = Settings.KeepDir;
        var link = DesktopLink;
        // a Keep folder on the Desktop itself needs no shortcut
        bool onDesktop = keep.StartsWith(DesktopDir.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
        bool want = Settings.Enabled && Settings.KeepShortcut && !onDesktop;
        dynamic sh = Com("WScript.Shell");
        // v0.7: with the Keep lock on, the shortcut opens Amnesia ("--open-keep"), which asks the Keep password
        var exe = Settings.Get("APP_PATH") is { } ap && File.Exists(ap) ? ap : Environment.ProcessPath!;
        bool viaApp = KeepLock.On;
        bool Ours(dynamic x) => Same((string)x.TargetPath, keep) || ((string)x.Arguments).Contains("--open-keep");
        if (!want)
        {
            // only our own shortcut goes, never a file of yours with the same name
            if (File.Exists(link) && Ours(sh.CreateShortcut(link))) File.Delete(link);
            return;
        }
        Directory.CreateDirectory(keep);
        dynamic l;
        if (File.Exists(link))
        {
            l = sh.CreateShortcut(link);
            if (!Ours(l)) return; // a file of yours with the same name: leave it
            bool right = viaApp ? Same((string)l.TargetPath, exe) : Same((string)l.TargetPath, keep);
            // v0.6: shortcuts made by older versions get the Keep icon too
            if (right && (!File.Exists(IconFile) || ((string)l.IconLocation).Contains("keep.ico", StringComparison.OrdinalIgnoreCase))) return;
        }
        else l = sh.CreateShortcut(link);
        l.TargetPath = viaApp ? exe : keep;
        l.Arguments = viaApp ? "--open-keep" : "";
        if (File.Exists(IconFile)) l.IconLocation = IconFile + ",0";
        l.Description = "Amnesia: files in here are never wiped";
        l.Save();
        AppInfo.Trace("keep shortcut made");
    }

    // v0.6 (asked by the user): the Keep folder shows a folder with the Amnesia logo, in Explorer and on the Desktop.
    // Windows reads the icon from desktop.ini inside the folder (the folder needs the read-only flag for that).
    static string IconFile => Path.Combine(AppInfo.BaseDir, "ui", "keep.ico");

    static string IniText => $"[.ShellClassInfo]\r\nIconResource={IconFile},0\r\n";

    /// <summary>Nothing to do for the icon (it is right, or there is none to set).</summary>
    static bool IconOk()
    {
        var keep = Settings.KeepDir;
        if (!Settings.Enabled || !Directory.Exists(keep) || !File.Exists(IconFile)) return true;
        try { var ini = Path.Combine(keep, "desktop.ini"); return File.Exists(ini) && File.ReadAllText(ini) == IniText; } catch { return false; }
    }

    /// <summary>Writes Keep\desktop.ini. True when the icon changed.</summary>
    static bool Icon()
    {
        var keep = Settings.KeepDir;
        if (!Settings.Enabled || !Directory.Exists(keep) || !File.Exists(IconFile)) return false;
        var ini = Path.Combine(keep, "desktop.ini");
        var text = IniText;
        if (File.Exists(ini) && File.ReadAllText(ini) == text) return false;
        if (File.Exists(ini)) File.SetAttributes(ini, FileAttributes.Normal);
        File.WriteAllText(ini, text);
        File.SetAttributes(ini, FileAttributes.Hidden | FileAttributes.System);
        var d = new DirectoryInfo(keep);
        d.Attributes |= FileAttributes.ReadOnly;
        SHChangeNotify(0x00002000 /* UPDATEITEM */, 0x0005 /* PATHW */, keep, IntPtr.Zero);
        AppInfo.Trace("keep icon set");
        return true;
    }

    /// <summary>v0.7.1: tells Explorer the Keep folder changed (after its lock was put on or taken off).</summary>
    public static void Notify(string dir)
    {
        try
        {
            SHChangeNotify(0x00002000 /* UPDATEITEM */, 0x0005 /* PATHW */, dir, IntPtr.Zero);
            SHChangeNotify(0x00001000 /* UPDATEDIR */, 0x0005, dir, IntPtr.Zero);
        }
        catch { }
    }

    /// <summary>Uninstall: the Keep folder goes back to a plain folder (your files stay).</summary>
    public static void RemoveIcon()
    {
        try
        {
            var keep = Settings.KeepDir;
            var ini = Path.Combine(keep, "desktop.ini");
            if (File.Exists(ini) && File.ReadAllText(ini).Contains("keep.ico", StringComparison.OrdinalIgnoreCase))
            {
                File.SetAttributes(ini, FileAttributes.Normal);
                File.Delete(ini);
                var d = new DirectoryInfo(keep);
                d.Attributes &= ~FileAttributes.ReadOnly;
                SHChangeNotify(0x00002000, 0x0005, keep, IntPtr.Zero);
            }
        }
        catch { }
    }

    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);

    /// <summary>repin: the icon just changed; take the pin out and put it back so the side bar shows the new icon.</summary>
    static void Pin(bool repin = false)
    {
        var keep = Settings.KeepDir;
        bool locked = KeepLock.On && KeepLock.IsLocked;
        bool want = Settings.Enabled && Settings.KeepPin && !locked;
        dynamic shell = Com("Shell.Application");
        if (want)
        {
            Directory.CreateDirectory(keep);
            var have = Pinned(shell, keep, sure: true);
            if (have != null && !repin) return; // pinning twice does nothing either
            if (have != null) { have.InvokeVerb("unpinfromhome"); Thread.Sleep(300); }
            shell.NameSpace(keep).Self.InvokeVerb("pintohome");
            AppInfo.Trace(repin ? "keep pinned again (new icon)" : "keep pinned to Quick access");
            return;
        }
        var pin = Pinned(shell, keep, sure: false);
        if (pin == null) return;
        pin.InvokeVerb("unpinfromhome");
        if (locked) AppInfo.Trace("keep taken out of Quick access while locked");
    }

    /// <summary>The Keep folder's entry in Quick access. sure: only when Windows says it is pinned (not just used often).</summary>
    static dynamic? Pinned(dynamic shell, string keep, bool sure)
    {
        dynamic? qa = shell.NameSpace(QuickAccess);
        if (qa == null) return null;
        dynamic items = qa.Items();
        int n = items.Count;
        for (int i = 0; i < n; i++)
        {
            dynamic it = items.Item(i);
            string? path = null;
            try { path = it.Path; } catch { }
            if (!Same(path, keep)) continue;
            // Quick access also lists folders you used often; only a real pin counts
            object? pinned = null;
            try { pinned = it.ExtendedProperty("System.Home.IsPinned"); } catch { }
            if (pinned is bool b ? b : !sure) return it;
        }
        return null;
    }
}
