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

    static CleanEngine Engine() => new()
    {
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

    /// <summary>The real cleanup (sign out / sign in / panic). The engine itself checks that Amnesia is on and not paused.</summary>
    public static CleanResult Run(string mode)
    {
        var r = Engine().Run(mode, dryRun: false);
        if (r.Blocked > 0) Settings.Set("LAST_BLOCKED", $"{DateTime.Now:yyyy-MM-dd HH:mm} {r.Blocked}");
        return r;
    }
}
