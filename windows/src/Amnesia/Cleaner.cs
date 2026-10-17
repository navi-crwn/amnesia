// Runs the cleanup (Amnesia.Core\CleanEngine.cs) inside Amnesia.exe and adds the parts only Windows has: registry
// history, Recycle Bin, clipboard. v0.4: no PowerShell any more, so nothing hidden is started at sign out (antivirus
// programs dislike that, and Windows refuses to start new programs while signing out anyway).
using System.Runtime.InteropServices;
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

static class Cleaner
{
    // Only "most recently used" lists and usage counters. Never settings.
    static readonly string[] RegKeys =
    {
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",                 // Win+R box
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths",             // Explorer address bar
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery",         // Explorer search box
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU", // open / save dialogs
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\CIDSizeMRU",    // v0.4
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",             // v0.4: which programs you ran, how often
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage",           // v0.4: taskbar usage counters
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\Map Network Drive MRU",  // v0.4
        @"Software\Microsoft\Windows\CurrentVersion\Search\JumplistData",             // v0.4: when each app was last opened
        @"Software\Microsoft\Windows\Shell\BagMRU",                                   // v0.4: "shellbags", folders you opened
        @"Software\Microsoft\Windows\Shell\Bags",
        @"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
        @"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
        @"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache", // v0.4: names of programs you ran
        @"Software\Microsoft\Terminal Server Client\Default",                         // v0.4: Remote Desktop history
        // v0.5, from BleachBit, privacy.sexy, Winapp2 and Bulk Crap Uninstaller:
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRULegacy",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSaveMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\SearchHistory",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\Doc Find Spec MRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\FindComputerMRU",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\PrnPortsMRU",
        @"Software\Microsoft\Search Assistant\ACMru",
        @"Software\Microsoft\Windows\CurrentVersion\Search\RecentApps",           // "recently opened" in Start
        @"Software\Microsoft\Windows\CurrentVersion\Applets\Regedit|LastKey",      // last place opened in Registry Editor
        @"Software\Microsoft\Windows\CurrentVersion\Applets\Paint\Recent File List",
        @"Software\Microsoft\Windows\CurrentVersion\Applets\Wordpad\Recent File List",
        @"Software\Microsoft\MediaPlayer\Player\RecentFileList",
        @"Software\Microsoft\MediaPlayer\Player\RecentURLList",
        @"Software\Gabest\Media Player Classic\Recent File List",
        @"Software\Microsoft\Direct3D\MostRecentApplication",                       // last game / 3D app you started
        @"Software\Adobe\MediaBrowser\MRU",                                          // Photoshop / Illustrator recent files
        @"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store", // every program you ran
        @"Software\Microsoft\Windows\ShellNoRoam\BagMRU",
        @"Software\Microsoft\Windows\ShellNoRoam\Bags",
        @"Software\Classes\Wow6432Node\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
        @"Software\Classes\Wow6432Node\Local Settings\Software\Microsoft\Windows\Shell\Bags",
    };

    /// <summary>Office recent files: HKCU\Software\Microsoft\Office\16.0\Word\File MRU and friends (any version, any app).</summary>
    static IEnumerable<string> OfficeMru()
    {
        using var office = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Office");
        if (office == null) yield break;
        foreach (var ver in office.GetSubKeyNames().Where(v => v.Length > 0 && char.IsDigit(v[0])))
        {
            using var vk = office.OpenSubKey(ver);
            foreach (var app in vk?.GetSubKeyNames() ?? Array.Empty<string>())
                foreach (var mru in new[] { "File MRU", "Place MRU", "User MRU", "Recent Templates", "RecentNotebooks" })
                {
                    var path = $@"Software\Microsoft\Office\{ver}\{app}\{mru}";
                    using var k = Registry.CurrentUser.OpenSubKey(path);
                    if (k != null) yield return path;
                }
        }
    }

    static IEnumerable<SystemTrace> SystemTraces()
    {
        foreach (var k in RegKeys.Concat(OfficeMru()))
        {
            var parts = k.Split('|'); // "key|value" = only that one value
            var path = parts[0];
            using var key = Registry.CurrentUser.OpenSubKey(path);
            if (key == null || parts.Length > 1 && key.GetValue(parts[1]) == null) continue;
            var label = "Registry: " + path.Replace(@"Software\Microsoft\Windows\CurrentVersion\", "").Replace(@"Software\Classes\Local Settings\Software\Microsoft\Windows\", "").Replace(@"Software\Microsoft\", "")
                        + (parts.Length > 1 ? " (" + parts[1] + ")" : "");
            if (parts.Length > 1)
            {
                var value = parts[1];
                yield return new SystemTrace(label, () => { using var w = Registry.CurrentUser.OpenSubKey(path, writable: true); w?.DeleteValue(value, false); });
            }
            else yield return new SystemTrace(label, () => Registry.CurrentUser.DeleteSubKeyTree(path, false));
        }
        // v0.5 Extra cleaning list (Winapp2): its registry lines
        var w2 = Extra.Plan();
        if (w2 != null && w2.Reg.Count > 0)
            yield return new SystemTrace($"Extra cleaning list: {w2.Reg.Count} registry entries", () => Extra.ClearRegistry(w2));
        // v0.5 (BleachBit): the DNS cache remembers which websites were opened
        yield return new SystemTrace("DNS cache", () => DnsFlushResolverCache());
        yield return new SystemTrace("Recycle Bin", () =>
        {
            int hr = SHEmptyRecycleBin(IntPtr.Zero, null, 0x1 | 0x2 | 0x4); // no confirmation, no progress, no sound
            if (hr != 0) throw new InvalidOperationException("empty");
        });
        // v0.8 opt-in: saved app passwords in Credential Manager (not your Microsoft account, OneDrive or Office)
        if (Creds.On)
        {
            int n = 0;
            try { n = Creds.List().Count; } catch { }
            if (n > 0) yield return new SystemTrace($"Credential Manager: {n} saved app password(s)", () => Creds.Wipe());
        }
        yield return new SystemTrace("Clipboard history", () =>
        {
            // pinned items stay in Windows' own list; everything else in Win+V and the current clipboard goes
            try { Windows.ApplicationModel.DataTransfer.Clipboard.ClearHistory(); } catch { }
            Sta(() => System.Windows.Forms.Clipboard.Clear());
        });
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHEmptyRecycleBin(IntPtr hwnd, string? root, uint flags);
    [DllImport("dnsapi.dll")] static extern bool DnsFlushResolverCache();
    [DllImport("shell32.dll")] static extern void SHChangeNotify(int eventId, uint flags, IntPtr a, IntPtr b);

    static void Sta(Action a)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA) { try { a(); } catch { } return; }
        var t = new Thread(() => { try { a(); } catch { } });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join(3000);
    }

    /// <summary>v0.8 (CRIT-WIN-02): cloud folders Windows knows about. Cloud apps (OneDrive, Dropbox, Google Drive, iCloud,
    /// Box...) register their folder as a "sync root"; Dropbox also writes it in info.json. Only read, never changed.</summary>
    public static IEnumerable<string> CloudRoots()
    {
        var list = new List<string>();
        try
        {
            var me = System.Security.Principal.WindowsIdentity.GetCurrent().User?.Value;
            using var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager");
            foreach (var sub in k?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                using var u = k!.OpenSubKey(sub + @"\UserSyncRoots");
                foreach (var v in u?.GetValueNames() ?? Array.Empty<string>())
                    if ((me == null || v.Equals(me, StringComparison.OrdinalIgnoreCase)) && u!.GetValue(v) is string p && p.Length > 3) list.Add(p);
            }
        }
        catch { }
        foreach (var root in new[] { Environment.SpecialFolder.LocalApplicationData, Environment.SpecialFolder.ApplicationData })
            try
            {
                var info = Path.Combine(Environment.GetFolderPath(root), "Dropbox", "info.json");
                if (!File.Exists(info)) continue;
                var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(info)) as System.Text.Json.Nodes.JsonObject;
                foreach (var kv in json ?? new System.Text.Json.Nodes.JsonObject())
                    if (kv.Value?["path"]?.GetValue<string>() is { Length: > 3 } p) list.Add(p);
            }
            catch { }
        return list;
    }

    /// <summary>v0.8: the rules of what is protected (Keep, Keep List, cloud, virtual machines), for "Remove new apps".</summary>
    public static CleanEngine Rules() => new() { CloudRoots = CloudRoots };

    /// <summary>v0.8: an open Safe box is packed and locked again (sign out, quick exit, and at sign in after a crash).</summary>
    public static void CloseSafe(string why)
    {
        try
        {
            if (!Safe.IsOpen) return;
            var t = System.Diagnostics.Stopwatch.StartNew();
            int n = KeepLock.With(() => Safe.Close(why));
            AppInfo.Trace($"safe box closed at {why}: {n} file(s) in {t.Elapsed.TotalSeconds:0.0} s");
        }
        catch (Exception e) { AppInfo.Trace($"safe box could not be closed ({why}): {e.GetType().Name}. The open copy stays in Keep\\Safe."); }
    }

    static CleanEngine Engine(bool explorerLiveOk = false, bool fast = false) => new()
    {
        Fast = fast,
        CloudRoots = CloudRoots,
        // v0.7.1: Explorer's icon cache, thumbnails and shellbags only go when Explorer is not running or the session
        // really ends (it made Explorer flicker and spin when they went under it, e.g. at a panic sign out)
        ExplorerLiveOk = explorerLiveOk,
        SystemTraces = SystemTraces,
        // Edge (and its "startup boost" helper) keeps its profile open: close it first, or the files can't be moved
        BeforeMove = items =>
        {
            if (!items.Any(i => i.Path.StartsWith(@"AppData\Local\Microsoft\Edge", StringComparison.OrdinalIgnoreCase))) return;
            var edge = System.Diagnostics.Process.GetProcessesByName("msedge");
            if (edge.Length == 0) return;
            AppInfo.Trace($"closing Edge ({edge.Length} processes)");
            foreach (var p in edge) try { p.Kill(); } catch { }
            Thread.Sleep(800);
        },
        // v0.4: programs installed in this session go too (Settings → Advanced → "Remove new apps")
        AfterClean = mode =>
        {
            Apps.RemoveNew(mode);
            // v0.5 (BleachBit): tell Explorer things changed, so it does not show deleted files or old history.
            // v0.5.2: only "this folder changed" for the folders you see, not "all icons changed" (that made Explorer
            // rebuild every icon over and over). At sign out there is nothing to tell.
            if (mode != "logout")
                foreach (var f in new[] { Environment.SpecialFolder.DesktopDirectory, Environment.SpecialFolder.MyDocuments, Environment.SpecialFolder.UserProfile })
                    { var path = Marshal.StringToHGlobalUni(Environment.GetFolderPath(f)); try { SHChangeNotify(0x00001000, 0x0005, path, IntPtr.Zero); } catch { } finally { Marshal.FreeHGlobal(path); } }
        },
        // v0.5 Extra cleaning list (Winapp2): its files in the folders that stay
        ExtraTraces = ok => Extra.Plan(ok)?.Files ?? new List<string>(),
    };

    /// <summary>"Show preview": what WOULD be deleted. Touches nothing.</summary>
    public static Task<CleanResult> PreviewAsync() => Task.Run(() => Engine().Run("now", dryRun: true));

    // v0.8: the sign out list, made while Windows asks "may I end the session?"
    static Task<CleanEngine>? ready;

    /// <summary>v0.8 (sign out did not always clean): makes the list in the background at WM_QUERYENDSESSION, so in
    /// WM_ENDSESSION (the few seconds Windows really waits) only the moving is left. Touches nothing.</summary>
    public static void PrepareLogout()
    {
        if (!Settings.Enabled || Settings.Paused || ready is { IsCompleted: false }) return;
        ready = Task.Run(() =>
        {
            var t = System.Diagnostics.Stopwatch.StartNew();
            var e = Engine(explorerLiveOk: true, fast: true);
            e.Prepare("logout");
            AppInfo.Trace($"sign out list ready: {e.Planned} item(s) in {t.Elapsed.TotalSeconds:0.0} s");
            return e;
        });
    }

    /// <summary>The real cleanup (sign out / sign in / panic). The engine itself checks that Amnesia is on and not paused.
    /// endSession: Windows is really ending the session (WM_ENDSESSION), so Explorer is closing too.
    /// v0.8: sign out and panic don't count sizes (fast), and sign out uses the list made a moment before.</summary>
    public static CleanResult Run(string mode, bool endSession = false)
    {
        if (mode is "logout" or "login") CloseSafe(mode);
        bool liveOk = mode == "logout" && (endSession || !ExplorerRunning());
        if (mode == "logout" && !liveOk) AppInfo.Trace("Explorer still runs: its caches wait for the next sign out");
        CleanEngine? e = null;
        if (mode == "logout" && endSession && ready != null)
        {
            try { if (ready.Wait(1500)) e = ready.Result; else AppInfo.Trace("sign out list not ready yet: looking again"); }
            catch (Exception x) { AppInfo.Trace($"sign out list failed: {x.GetType().Name}"); }
            ready = null;
        }
        e ??= Engine(liveOk, fast: mode == "logout");
        var r = e.Run(mode, dryRun: false);
        if (r.Blocked > 0) Settings.Set("LAST_BLOCKED", $"{DateTime.Now:yyyy-MM-dd HH:mm} {r.Blocked}");
        return r;
    }

    /// <summary>v0.8 panic (MED-WIN-04, thumbnails were never wiped): Explorer is closed for a moment (the screen is
    /// already locked, so nothing flickers in front of you) and its thumbnail and icon caches are deleted while it is
    /// gone. Windows starts Explorer again by itself, with empty caches. Returns how many files went.</summary>
    public static int StopExplorerAndWipeCaches()
    {
        if (Core.Home.Test) return 0;
        var me = System.Diagnostics.Process.GetCurrentProcess().SessionId;
        foreach (var p in System.Diagnostics.Process.GetProcessesByName("explorer"))
            try { if (p.SessionId == me) p.Kill(); } catch { }
        for (int i = 0; i < 10 && ExplorerRunning(); i++) Thread.Sleep(50);
        return CleanEngine.DeleteExplorerCaches();
    }

    /// <summary>Is Explorer (Desktop, taskbar) running in this Windows session?</summary>
    static bool ExplorerRunning()
    {
        var me = System.Diagnostics.Process.GetCurrentProcess().SessionId;
        return System.Diagnostics.Process.GetProcessesByName("explorer").Any(p => { try { return p.SessionId == me; } catch { return false; } });
    }

    /// <summary>v0.7.1: after the sign in check took Desktop or Start items away while Explorer was already running,
    /// Explorer kept looking for their icons (flicker, high CPU, fixed by restarting Explorer). One "file types and
    /// icons changed" makes it drop what it remembers and read again. Only once, and never with the caches deleted
    /// under it (that was the loop in v0.5.2).</summary>
    public static void NotifyShell()
    {
        try { SHChangeNotify(0x08000000 /* ASSOCCHANGED */, 0x0000 /* IDLIST */, IntPtr.Zero, IntPtr.Zero); AppInfo.Trace("told Explorer the icons changed"); }
        catch { }
    }
}
