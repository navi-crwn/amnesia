// The cleanup (v0.4: moved from scripts\clean.ps1 into Amnesia.exe, so no hidden PowerShell runs at sign out any more).
//
//   logout  moves everything to %USERPROFILE%\.amnesia-trash (instant, same disk). Windows gives little time at sign out.
//   login   empties .amnesia-trash, then checks again (catches what a crash or power cut left behind)
//   now     moves and empties right away
//   dry run only lists what WOULD be deleted, touches nothing ("Show preview")
//
// Real cleanup only runs when ALL of these are true (otherwise it stops and touches nothing):
//   - Amnesia is turned on (ENABLED=1 in settings.conf)
//   - Amnesia.exe still exists (APP_PATH in settings.conf); deleting the app stops the cleanup
//   - no pause: pause_once skips the next sign out AND the next sign in, then it is removed
//
// Protected (never touched): the Keep folder, .amnesia, every line of keep.conf, what Windows needs to sign you in,
// OneDrive, Microsoft Store app data. Links/junctions are never followed. Standard folders stay, only their content goes.
// v0.8: also cloud folders (Dropbox, Google Drive, iCloud...: their app deletes from the cloud too when the local copy
// goes), files that are only in the cloud, and virtual machines (VirtualBox, VMware, WSL, Docker, disk images).
namespace Amnesia.Core;

public sealed record CleanItem(string Path, string Kind);

/// <summary>Something outside the user folder (registry history, Recycle Bin, clipboard). Given by the app, never in tests.</summary>
public sealed record SystemTrace(string Label, Action Clear);

public sealed class CleanResult
{
    public string Mode { get; set; } = "now";
    public bool DryRun { get; set; }
    public string Home { get; set; } = "";
    public string? Skipped { get; set; }
    public int Count { get; set; }
    public int Failed { get; set; }
    /// <summary>Items Windows refused with "access denied": usually Controlled folder access or an antivirus.</summary>
    public int Blocked { get; set; }
    /// <summary>v0.8: -1 when the sizes were not counted (sign out and panic are kept fast).</summary>
    public long Bytes { get; set; }
    public double Seconds { get; set; }
    public List<CleanItem> Items { get; set; } = new();
    public List<string> Kept { get; set; } = new();
}

public sealed class CleanEngine
{
    // Windows needs these to log you in, keep saved passwords (Credential Manager, DPAPI keys) and run Store apps.
    static readonly string[] BuiltInKeep =
    {
        "NTUSER*",
        ".amnesia", ".amnesia-trash",
        "AppData/Local/Microsoft",
        "AppData/Roaming/Microsoft",
        "AppData/Local/Packages",
        "AppData/Local/Amnesia",
        "AppData/Local/Programs/Amnesia",
        "AppData/Local/Temp/.net/Amnesia",   // Amnesia.exe unpacks its window part (WebView2Loader.dll) here (v0.2.3)
        "OneDrive", "OneDrive - *",           // your files are safe in the cloud; wiping only makes OneDrive download everything again
        "AppData/Local/OneDrive",
        "Links", "Searches",                  // Windows' own shortcuts (Explorer side bar, saved searches)
        "Favorites/Bing.url", "Favorites/Links",
    };
    static readonly string[] KeepByName = { "desktop.ini" };
    // v0.8 (CRIT-WIN-02): cloud folders. Moving them away looks like "deleted" to their sync app, which then deletes the
    // files in the cloud too. Folders that Windows knows as sync roots are added by Amnesia.exe (CloudRoots).
    static readonly string[] CloudNames =
    {
        "Dropbox", "Dropbox (*)", "Google Drive", "My Drive", "iCloudDrive", "iCloud Drive", "iCloudPhotos", "iCloud Photos",
        "Nextcloud", "ownCloud", "MEGA", "MEGAsync", "MEGA Downloads", "Box", "Box Sync", "pCloud Drive", "pCloudDrive",
        "Proton Drive", "Tresorit", "Sync", "SynologyDrive", "Seafile", "Creative Cloud Files*",
    };
    // v0.8 (HIGH-WIN-06, like the Mac in v5.21): virtual machines are big and slow to make again. On unless KEEP_VM=0.
    static readonly string[] VmDirs =
    {
        "VirtualBox VMs", ".VirtualBox", "Virtual Machines", "Documents/Virtual Machines", ".android/avd", ".vagrant.d",
        "AppData/Local/wsl", "AppData/Local/Docker/wsl",
    };
    static readonly string[] VmFiles = { "*.vhdx", "*.vhd", "*.avhdx", "*.vmdk", "*.vdi", "*.qcow2", "*.vmx", "*.vbox" };
    /// <summary>A disc image (.iso) this big stays too: a Windows or Linux image takes ages to download again.</summary>
    public const long BigIso = 1L << 30;
    // a file that is only (or partly) in the cloud: OneDrive, Dropbox, iCloud... "Files On-Demand"
    const FileAttributes CloudBits = FileAttributes.Offline | (FileAttributes)0x40000 /* recall on open */
        | (FileAttributes)0x400000 /* recall on data access */ | (FileAttributes)0x80000 /* pinned */ | (FileAttributes)0x100000 /* unpinned */;
    // folders right in AppData that hold many programs: "Remove new apps" never takes one of these whole
    static readonly string[] SharedAppFolders = { "Programs", "Temp", "Packages", "Microsoft", "Google", "Mozilla", "Apps", "Publishers", "Comms", "Package Cache", "PackageManagement", "Amnesia" };
    // Folders that stay; only what is inside them is wiped. Windows makes these itself.
    static readonly string[] Containers =
    {
        "AppData", "AppData/Roaming", "AppData/Local", "AppData/LocalLow",
        "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos",
        "Favorites", "Contacts", "Saved Games", "3D Objects",
        "Pictures/Screenshots", "Pictures/Camera Roll", "Pictures/Saved Pictures", "Videos/Captures",
    };
    // Windows traces inside folders that otherwise stay (they live under AppData\...\Microsoft). Only the content goes.
    static readonly string[] TraceDirs =
    {
        "AppData/Roaming/Microsoft/Windows/Recent",                  // recent files + jump lists
        "AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine",    // PowerShell history
        "AppData/Local/Microsoft/Windows/INetCache",                  // v0.4: old Internet Explorer / Explorer web cache
        "AppData/Local/Microsoft/Windows/INetCookies",
        "AppData/Local/Microsoft/Windows/History",
        "AppData/Local/Microsoft/Windows/WebCache",                   // often in use: then next sign in
        "AppData/Local/Packages/Microsoft.Windows.Search_*/LocalState/DeviceSearchCache", // v0.4: Start menu search history
        "AppData/Local/Microsoft/Windows/Clipboard",                  // v0.4: clipboard history files (Win+V)
        // v0.5, ideas from BleachBit, privacy.sexy and Winapp2:
        "AppData/Local/Microsoft/Windows/WER",                        // crash reports: they name the programs you ran
        "AppData/Local/Microsoft/Windows/ConnectedSearch/History",    // Windows search history
        "AppData/Roaming/Microsoft/Office/Recent",                    // Office recent files
        "AppData/Local/Microsoft/Terminal Server Client/Cache",       // Remote Desktop keeps pieces of the remote screen
        "AppData/Local/Packages/Microsoft.WindowsNotepad_*/LocalState/TabState",    // Notepad keeps unsaved tabs here
        "AppData/Local/Packages/Microsoft.WindowsNotepad_*/LocalState/WindowState",
        "AppData/Local/Packages/Microsoft.ScreenSketch_*/TempState",  // Snipping Tool: recent screenshots
    };
    // v0.5 "Extra cleaning list": the only places outside traces it may touch (they stay on purpose, so app history
    // there would stay too). Never the parts Windows needs for saved passwords and sign in.
    static readonly string[] ExtraZones = { "AppData/Local/Microsoft/", "AppData/Roaming/Microsoft/", "AppData/Local/Packages/" };
    static readonly string[] ExtraNever =
    {
        "AppData/Roaming/Microsoft/Protect", "AppData/Roaming/Microsoft/Credentials", "AppData/Local/Microsoft/Credentials",
        "AppData/Roaming/Microsoft/Crypto", "AppData/Roaming/Microsoft/SystemCertificates", "AppData/Roaming/Microsoft/Vault",
        "AppData/Local/Microsoft/Vault", "AppData/Roaming/Microsoft/Windows/Start Menu", "AppData/Roaming/Microsoft/Windows/Themes",
        "AppData/Local/Microsoft/WindowsApps", "AppData/Local/Microsoft/OneDrive", "AppData/Local/Microsoft/Windows/CloudStore",
        "AppData/Local/Microsoft/Edge", "AppData/Roaming/Microsoft/Spelling", "AppData/Roaming/Microsoft/Signatures",
        "AppData/Roaming/Microsoft/Templates", "AppData/Roaming/Microsoft/UProof", "AppData/Local/Microsoft/IdentityCache",
        "AppData/Local/Microsoft/TokenBroker", "AppData/Local/Packages/Microsoft.AAD.BrokerPlugin_*", "AppData/Local/Packages/*/Settings",
    };
    static readonly string[] TraceFiles =
    {
        "AppData/Local/Microsoft/Windows/Explorer/thumbcache_*.db",   // thumbnails stay even after the file is gone
        "AppData/Local/Microsoft/Windows/Explorer/iconcache_*.db",
        "AppData/Local/Microsoft/Windows/Notifications/wpndatabase.db*", // v0.4: notification history (in use while signed in)
    };
    // v0.5.2: what Explorer (Desktop, taskbar, Start, search) has open while you are signed in. Deleting it under a running
    // Explorer made the Desktop flicker, ate CPU and stopped new files from showing until a refresh. So it is only
    // wiped at sign out (Explorer is gone then), never at the sign in check or "Clean now".
    static readonly string[] ExplorerLive =
    {
        "AppData/Local/Microsoft/Windows/Explorer", "AppData/Local/Microsoft/Windows/Caches", "AppData/Local/IconCache.db",
        "AppData/Local/Packages/Microsoft.Windows.StartMenuExperienceHost_*", "AppData/Local/Packages/Microsoft.Windows.ShellExperienceHost_*",
    };
    /// <summary>Registry traces Explorer keeps in memory and writes back (shellbags: folder views, also the Desktop's).</summary>
    public static bool ExplorerLiveKey(string label) => label.Contains(@"Shell\Bag", StringComparison.OrdinalIgnoreCase);

    public static bool IsExplorerLive(string rel)
    {
        rel = rel.Replace('\\', '/');
        return ExplorerLive.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*"));
    }

    /// <summary>v0.7.1: did the cleanup take things Explorer shows (Desktop, recent items, Start menu)? After the sign in
    /// check Amnesia then tells Explorer once, so it does not keep looking for icons that are gone.</summary>
    public static bool TouchesShell(IEnumerable<CleanItem> items) => items.Any(i =>
        i.Path.StartsWith("Desktop\\", StringComparison.OrdinalIgnoreCase)
        || i.Path.StartsWith(@"AppData\Roaming\Microsoft\Windows\Recent\", StringComparison.OrdinalIgnoreCase)
        || i.Path.StartsWith(@"AppData\Roaming\Microsoft\Windows\Start Menu\", StringComparison.OrdinalIgnoreCase));

    // Edge lives inside AppData\Local\Microsoft (which stays), so it is wiped on its own. On the Keep List? Then it stays.
    static readonly string[] BrowserDirs =
    {
        "AppData/Local/Microsoft/Edge", "AppData/Local/Microsoft/Edge Beta", "AppData/Local/Microsoft/Edge Dev", "AppData/Local/Microsoft/Edge SxS",
    };

    readonly string H = Home.User;
    readonly List<string> patterns = new();
    List<string> userKeep = new();
    readonly List<CleanItem> items = new();
    readonly List<string> kept = new();
    readonly Dictionary<string, int> busyAreas = new(StringComparer.OrdinalIgnoreCase);
    void Busy(string rel)
    {
        var parts = rel.Split('\\', '/');
        var n = parts[0].Equals("AppData", StringComparison.OrdinalIgnoreCase) ? 3 : 1;
        // never the last part (that could be a file name); a file right in the user folder counts as "user folder"
        var area = parts.Length == 1 ? "user folder" : string.Join('\\', parts.Take(Math.Min(n, parts.Length - 1)));
        busyAreas[area] = busyAreas.TryGetValue(area, out var c) ? c + 1 : 1;
    }
    char Sep => Path.DirectorySeparatorChar;

    /// <summary>Registry history, Recycle Bin, clipboard... (given by Amnesia.exe; empty in tests).</summary>
    public Func<IEnumerable<SystemTrace>>? SystemTraces { get; set; }
    /// <summary>Runs right before files are moved (closes Edge so its profile can move).</summary>
    public Action<IReadOnlyList<CleanItem>>? BeforeMove { get; set; }
    /// <summary>v0.5: more traces (the Extra cleaning list). Gets the safety check, returns full paths.</summary>
    public Func<Func<string, bool>, IEnumerable<string>>? ExtraTraces { get; set; }
    /// <summary>Runs after the user folder is done (removes apps installed in this session).</summary>
    public Action<string>? AfterClean { get; set; }
    /// <summary>v0.8: cloud folders Windows knows about (full paths, from Amnesia.exe: sync roots, Dropbox, Google Drive).</summary>
    public Func<IEnumerable<string>>? CloudRoots { get; set; }
    /// <summary>v0.8: sign out and panic don't count file sizes (that took seconds with many files, and Windows waits only
    /// a few seconds at sign out).</summary>
    public bool Fast { get; set; }

    // v0.8: the list can be made a moment before the real cleanup (Prepare), so at sign out only the moving is left
    bool scanned;
    string scannedMode = "";
    DateTime scannedAt;
    List<SystemTrace> system = new();
    /// <summary>How many items the last look found.</summary>
    public int Planned => items.Count;

    /// <summary>v0.8: looks everything up without touching anything. Windows asks "may I end the session?" a moment
    /// before it ends it: that moment is used for this. A real Run with the same mode in the next 2 minutes uses this list.</summary>
    public void Prepare(string mode) => Scan(mode, _ => { });

    /// <summary>v0.7.1: may Explorer's own caches (icon cache, thumbnails, shellbags) go? Only when Explorer is not
    /// running or the session is really ending. Not set: only at sign out (as before).</summary>
    public bool? ExplorerLiveOk { get; set; }

    public CleanResult Run(string mode, bool dryRun)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var r = new CleanResult { Mode = mode, DryRun = dryRun, Home = H };
        void T(string s) { if (!dryRun) Home.Trace("clean " + mode, s); }

        // ---------- safety checks before anything real happens ----------
        if (!dryRun)
        {
            if (!Conf.Enabled) { r.Skipped = "off"; return r; }
            var app = Conf.Get("APP_PATH");
            if (string.IsNullOrEmpty(app) || !File.Exists(app)) { T("stop: Amnesia.exe is gone"); r.Skipped = "app-missing"; return r; }
            if (Conf.Paused && mode != "now")
            {
                if (mode == "login") try { File.Delete(Conf.PauseFile); } catch { }
                Home.History("paused", mode);
                T("paused");
                r.Skipped = "paused";
                return r;
            }
            T("start");
        }

        if (scanned && scannedMode == mode && DateTime.UtcNow - scannedAt < TimeSpan.FromMinutes(2)) T($"using the list made {(DateTime.UtcNow - scannedAt).TotalSeconds:0.0} s ago");
        else Scan(mode, T);

        r.Items = items;
        r.Kept = kept;
        r.Count = items.Count;
        if (dryRun) { r.Seconds = watch.Elapsed.TotalSeconds; return r; }
        T($"list ready ({items.Count}) after {watch.Elapsed.TotalSeconds:0.0} s");

        // ---------- the real thing ----------
        int moved = 0, failed = 0, blocked = 0;
        long bytes = Fast ? -1 : 0;
        if (mode == "login") { T("empty trash"); Purge(); }
        try { BeforeMove?.Invoke(items); } catch (Exception e) { T($"before move failed: {e.GetType().Name}"); }

        T("1 user folder");
        var batch = Path.Combine(Home.Trash, DateTime.Now.ToString("yyyyMMdd-HHmmss"));
        foreach (var i in items)
        {
            if (i.Kind != "file" && i.Kind != "folder") continue;
            var full = Path.Combine(H, i.Path.Replace('\\', Sep));
            if (!Exists(full)) continue; // already gone
            if (!Fast) bytes += SizeOf(full);
            // move = instant (same disk). The folder structure is kept in the trash so names never collide.
            var dest = Path.Combine(batch, i.Path.Replace('\\', Sep));
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                if (Directory.Exists(full)) Directory.Move(full, dest); else File.Move(full, dest);
                moved++;
            }
            catch (Exception e)
            {
                if (Delete(full)) moved++;
                else { failed++; Busy(i.Path); if (e is UnauthorizedAccessException) blocked++; } // in use: tried again at the next sign in
            }
        }

        T($"2 windows traces (after {watch.Elapsed.TotalSeconds:0.0} s)");
        int liveFailed = 0;
        foreach (var i in items)
        {
            if (i.Kind != "trace" || !i.Path.StartsWith("AppData\\", StringComparison.OrdinalIgnoreCase)) continue;
            if (Delete(Path.Combine(H, i.Path.Replace('\\', Sep)))) moved++;
            else { failed++; Busy(i.Path); if (IsExplorerLive(i.Path)) liveFailed++; } // often in use at sign out: next sign in
        }
        // v0.8: so a test can show whether Explorer still held its caches at this moment
        if (liveFailed > 0) T($"explorer caches still in use: {liveFailed}");
        foreach (var s in system)
        {
            try { s.Clear(); moved++; } catch { } // an empty Recycle Bin or a missing key is fine
        }
        T($"3 programs (after {watch.Elapsed.TotalSeconds:0.0} s)");
        try { AfterClean?.Invoke(mode); } catch (Exception e) { T($"after clean failed: {e.GetType().Name}"); }

        T("4 after");
        var keepRel = Conf.KeepRel;
        if (keepRel.Length > 0) try { Directory.CreateDirectory(Home.Full(keepRel)); } catch { }
        if (mode != "logout") { T("empty trash"); Purge(); } // at sign out time is short: emptied at the next sign in

        r.Count = moved; r.Failed = failed; r.Blocked = blocked; r.Bytes = bytes;
        r.Seconds = watch.Elapsed.TotalSeconds;
        Home.History("clean", $"{mode} {moved} {bytes}");
        if (blocked > 0) Home.History("blocked", blocked.ToString());
        T($"done ({moved}, {failed} in use, {blocked} denied) in {r.Seconds:0.0} s");
        // v0.6: WHERE the files in use are (folders only, never file names), so "8 in use" can be looked into
        if (busyAreas.Count > 0) T("in use: " + string.Join(", ", busyAreas.OrderByDescending(x => x.Value).Take(8).Select(x => $"{x.Key} ({x.Value})")));
        return r;
    }

    /// <summary>Makes the list: what goes, what stays. Touches nothing.</summary>
    void Scan(string mode, Action<string> T)
    {
        patterns.Clear(); items.Clear(); kept.Clear(); busyAreas.Clear();
        Patterns();
        Visit("");
        AddBrowsers();
        AddTraces();
        if (ExtraTraces != null)
            try
            {
                var have = items.Select(i => i.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
                foreach (var f in ExtraTraces(ExtraOk))
                {
                    var rel = Win(Path.GetRelativePath(H, f).Replace(Sep, '/'));
                    // already listed (or inside something listed): skip
                    bool inside = false;
                    for (var up = Path.GetDirectoryName(rel.Replace('\\', Sep)); !string.IsNullOrEmpty(up) && !inside; up = Path.GetDirectoryName(up))
                        inside = have.Contains(Win(up.Replace(Sep, '/')));
                    if (!inside && have.Add(rel)) items.Add(new CleanItem(rel, "trace"));
                }
            }
            catch (Exception e) { T($"extra list failed: {e.GetType().Name}"); }
        system = (Home.Test ? null : SystemTraces?.Invoke())?.ToList() ?? new List<SystemTrace>();
        if (!(ExplorerLiveOk ?? mode == "logout"))
        {
            int left = items.RemoveAll(i => i.Kind == "trace" && IsExplorerLive(i.Path)) + system.RemoveAll(x => ExplorerLiveKey(x.Label));
            if (left > 0) T($"explorer caches left for sign out: {left}");
        }
        foreach (var s in system) items.Add(new CleanItem(s.Label, "trace"));
        scanned = true; scannedMode = mode; scannedAt = DateTime.UtcNow;
    }

    // ---------- what is protected ----------
    void Patterns()
    {
        patterns.AddRange(BuiltInKeep);
        var keepRel = Conf.KeepRel;
        if (keepRel.Length > 0) patterns.Add(keepRel);
        // v0.3: the shortcut to the Keep folder that Amnesia puts on the Desktop
        if (Conf.Get("KEEP_SHORTCUT") != "0")
        {
            var leaf = keepRel.Length > 0 ? keepRel.Split('/')[^1] : (Conf.Get("KEEP_DIR") ?? "Keep").Replace('\\', '/').TrimEnd('/').Split('/')[^1];
            if (leaf.Length > 0) patterns.Add($"Desktop/{leaf}.lnk");
        }
        userKeep = KeepList.Paths();
        patterns.AddRange(userKeep);
        // v0.8: cloud folders and virtual machines
        patterns.AddRange(CloudNames);
        try
        {
            foreach (var c in CloudRoots?.Invoke() ?? Enumerable.Empty<string>())
            {
                var rel = InHome(c);
                if (rel != null && rel.Length > 0 && !rel.Contains('*')) patterns.Add(rel);
            }
        }
        catch { }
        if (KeepVm) patterns.AddRange(VmDirs);
    }

    /// <summary>v0.8: virtual machines stay (KEEP_VM=0 switches it off).</summary>
    static bool KeepVm => Conf.Get("KEEP_VM") != "0";

    /// <summary>A full path as a path inside the user folder ("AppData/Local/x"), or null when it is outside it.</summary>
    string? InHome(string full)
    {
        try
        {
            var rel = Path.GetRelativePath(H, Path.GetFullPath(full)).Replace('\\', '/').Trim('/');
            if (rel == ".") return "";
            if (rel.StartsWith("..") || Path.IsPathRooted(rel) || rel.Contains("/../")) return null;
            return rel;
        }
        catch { return null; }
    }

    /// <summary>v0.8: a file that is only (or partly) in the cloud, or a virtual machine disk / big disc image.</summary>
    static bool StaysByItself(FileSystemInfo c)
    {
        if ((c.Attributes & CloudBits) != 0) return true;
        if (c is not FileInfo f || !KeepVm) return false;
        foreach (var n in VmFiles) if (Wild.Like(f.Name, n)) return true;
        return Wild.Like(f.Name, "*.iso") && f.Length >= BigIso;
    }

    /// <summary>v0.8: a folder you made yourself (top level, Desktop, Documents, Downloads, Videos) with a virtual machine
    /// disk or a big disc image a few levels down: it is looked into, so only that file stays. Not in AppData (too slow).</summary>
    static bool HasVmInside(string rel, FileSystemInfo dir)
    {
        if (!KeepVm) return false;
        var top = rel.Split('/');
        if (top.Length > 1 && !new[] { "Desktop", "Documents", "Downloads", "Videos" }.Contains(top[0], StringComparer.OrdinalIgnoreCase)) return false;
        if (top[0].Equals("AppData", StringComparison.OrdinalIgnoreCase) || top[0].StartsWith('.')) return false;
        try
        {
            var opt = new EnumerationOptions { RecurseSubdirectories = true, MaxRecursionDepth = 3, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
            return new DirectoryInfo(dir.FullName).EnumerateFiles("*", opt).Any(f => StaysByItself(f));
        }
        catch { return false; }
    }

    /// <summary>v0.8 (CRIT-WIN-01): may "Remove new apps" take this program folder (full path)? Only a folder of its own
    /// inside AppData (Local, Roaming or LocalLow), never one that is protected (Keep, the Keep List, cloud, virtual
    /// machines, Windows' own folders), never one with something protected inside, never a link.</summary>
    public bool MayRemoveAppFolder(string full)
    {
        if (string.IsNullOrWhiteSpace(full)) return false;
        if (patterns.Count == 0) Patterns();
        var rel = InHome(full);
        if (string.IsNullOrEmpty(rel)) return false;
        var parts = rel.Split('/');
        if (parts.Length < 3 || !parts[0].Equals("AppData", StringComparison.OrdinalIgnoreCase)
            || !new[] { "Local", "Roaming", "LocalLow" }.Contains(parts[1], StringComparer.OrdinalIgnoreCase)) return false;
        if (parts.Length == 3 && SharedAppFolders.Contains(parts[2], StringComparer.OrdinalIgnoreCase)) return false;
        if (IsKept(rel) || HoldsKept(rel) || UserKept(rel)) return false;
        try
        {
            var d = new DirectoryInfo(Home.Full(rel));
            return d.Exists && !d.Attributes.HasFlag(FileAttributes.ReparsePoint);
        }
        catch { return false; }
    }

    bool IsKept(string rel)
    {
        var leaf = rel.Split('/')[^1];
        foreach (var n in KeepByName) if (Wild.Like(leaf, n)) return true;
        var rs = rel.Split('/');
        foreach (var p in patterns)
        {
            if (Wild.Like(rel, p)) return true;
            // inside a kept folder: everything below it stays too
            var ps = p.Split('/');
            if (rs.Length > ps.Length && Wild.Like(string.Join('/', rs[..ps.Length]), p)) return true;
        }
        return false;
    }

    // true when something that must stay is somewhere inside this folder: then we look inside instead of wiping it whole
    bool HoldsKept(string rel)
    {
        var rs = rel.Split('/');
        foreach (var p in patterns)
        {
            var ps = p.Split('/');
            if (ps.Length > rs.Length && Wild.Like(rel, string.Join('/', ps[..rs.Length]))) return true;
        }
        return false;
    }

    /// <summary>v0.5: may the Extra cleaning list delete this (full path)? Only inside ExtraZones, never ExtraNever,
    /// your Keep folder or anything on your Keep List.</summary>
    public bool ExtraOk(string full)
    {
        if (patterns.Count == 0) Patterns();
        var rel = Path.GetRelativePath(H, full).Replace(Sep, '/');
        if (rel.StartsWith("..") || Path.IsPathRooted(rel) || rel.Contains("/../")) return false;
        if (!ExtraZones.Any(z => rel.StartsWith(z, StringComparison.OrdinalIgnoreCase))) return false;
        if (ExtraNever.Any(n => Wild.Like(rel, n) || Wild.Like(rel, n + "/*") || Wild.Like(n, rel + "/*"))) return false;
        if (UserKept(rel)) return false;
        var keepRel = Conf.KeepRel;
        if (keepRel.Length > 0 && (Wild.Like(rel, keepRel + "/*") || rel.Equals(keepRel, StringComparison.OrdinalIgnoreCase))) return false;
        return true;
    }

    bool UserKept(string rel) => userKeep.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*") || Wild.Like(p, rel + "/*"));

    static string Win(string rel) => rel.Replace('/', '\\');

    void Visit(string rel)
    {
        var dir = rel.Length > 0 ? Path.Combine(H, rel.Replace('/', Sep)) : H;
        IEnumerable<FileSystemInfo> list;
        try { list = new DirectoryInfo(dir).EnumerateFileSystemInfos().ToList(); } catch { return; }
        foreach (var c in list.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
        {
            var r = rel.Length > 0 ? $"{rel}/{c.Name}" : c.Name;
            if (c.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue; // junctions/links: never followed, never deleted
            if (IsKept(r) || StaysByItself(c)) { kept.Add(Win(r)); continue; }
            bool isDir = c is DirectoryInfo;
            if (isDir && (Containers.Contains(r, StringComparer.OrdinalIgnoreCase) || HoldsKept(r) || HasVmInside(r, c))) { Visit(r); continue; }
            items.Add(new CleanItem(Win(r), isDir ? "folder" : "file"));
        }
    }

    void AddBrowsers()
    {
        foreach (var d in BrowserDirs)
        {
            if (!Directory.Exists(Home.Full(d))) continue;
            if (UserKept(d)) { kept.Add(Win(d)); continue; }
            items.Add(new CleanItem(Win(d), "folder"));
        }
    }

    /// <summary>Folders that match a path with * in it (only the last parts may have *).</summary>
    IEnumerable<string> Expand(string pattern)
    {
        var parts = pattern.Split('/');
        IEnumerable<string> found = new[] { "" };
        foreach (var part in parts)
        {
            found = found.SelectMany(f =>
            {
                var dir = f.Length > 0 ? Home.Full(f) : H;
                if (!part.Contains('*')) return Directory.Exists(Path.Combine(dir, part)) ? new[] { f.Length > 0 ? $"{f}/{part}" : part } : Array.Empty<string>();
                try { return new DirectoryInfo(dir).EnumerateDirectories(part).Where(x => !x.Attributes.HasFlag(FileAttributes.ReparsePoint)).Select(x => f.Length > 0 ? $"{f}/{x.Name}" : x.Name).ToArray(); }
                catch { return Array.Empty<string>(); }
            }).ToList();
        }
        return found;
    }

    void AddTraces()
    {
        foreach (var pattern in TraceDirs)
            foreach (var d in Expand(pattern))
            {
                if (UserKept(d)) continue;
                IEnumerable<FileSystemInfo> list;
                try { list = new DirectoryInfo(Home.Full(d)).EnumerateFileSystemInfos().ToList(); } catch { continue; }
                foreach (var c in list.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                {
                    if (c.Attributes.HasFlag(FileAttributes.ReparsePoint) || c.Name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                    items.Add(new CleanItem(Win($"{d}/{c.Name}"), "trace"));
                }
            }
        // v0.8 opt-in (WIPE_STORE=1): what Store apps saved (their own state, cache, cookies). Never Windows' own
        // packages, never their Settings folder, never one on the Keep List.
        if (Conf.Get("WIPE_STORE") == "1" && Directory.Exists(Home.Full("AppData/Local/Packages")))
            foreach (var pkg in new DirectoryInfo(Home.Full("AppData/Local/Packages")).EnumerateDirectories().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
            {
                if (pkg.Attributes.HasFlag(FileAttributes.ReparsePoint) || !pkg.Name.Contains('_') || StoreSystem(pkg.Name)) continue;
                foreach (var sub in StoreData)
                {
                    var d = $"AppData/Local/Packages/{pkg.Name}/{sub}";
                    if (UserKept(d) || !Directory.Exists(Home.Full(d))) continue;
                    IEnumerable<FileSystemInfo> list;
                    try { list = new DirectoryInfo(Home.Full(d)).EnumerateFileSystemInfos().ToList(); } catch { continue; }
                    foreach (var c in list.OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                        if (!c.Attributes.HasFlag(FileAttributes.ReparsePoint) && !UserKept($"{d}/{c.Name}"))
                            items.Add(new CleanItem(Win($"{d}/{c.Name}"), "trace"));
                }
            }
        foreach (var f in TraceFiles)
        {
            var parent = f[..f.LastIndexOf('/')];
            var dir = Home.Full(parent);
            if (!Directory.Exists(dir)) continue;
            foreach (var c in new DirectoryInfo(dir).EnumerateFiles(f[(f.LastIndexOf('/') + 1)..]).OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                items.Add(new CleanItem(Win($"{parent}/{c.Name}"), "trace"));
        }
    }

    static readonly string[] StoreData = { "LocalState", "RoamingState", "TempState", "LocalCache", "AC/INetCache", "AC/INetCookies", "AC/INetHistory" };
    static readonly string[] StoreSystemStart =
    {
        "Microsoft.Windows", "MicrosoftWindows.", "Windows.", "Microsoft.AAD", "Microsoft.UI.", "Microsoft.VCLibs", "Microsoft.NET",
        "Microsoft.LockApp", "Microsoft.Win32WebViewHost", "Microsoft.ECApp", "Microsoft.CredDialogHost", "Microsoft.AccountsControl",
        "Microsoft.BioEnrollment", "Microsoft.DesktopAppInstaller", "Microsoft.StorePurchaseApp", "Microsoft.WindowsStore",
        "Microsoft.Services.Store", "Microsoft.XboxGameCallableUI", "Microsoft.XboxIdentityProvider", "Microsoft.MicrosoftEdge",
        "Microsoft.OneDriveSync", "Microsoft.SecHealthUI", "Microsoft.AsyncTextService", "Microsoft.Advertising", "Microsoft.WindowsAppRuntime",
        "Microsoft.WinAppRuntime", "NcsiUwpApp", "1527c705-", "c5e2524a-", "E2A4F912-", "F46D4000-", "Microsoft.Office.OneNote", "Microsoft.MicrosoftOfficeHub",
    };
    /// <summary>v0.8: a Store package Windows itself needs (Start, sign in, Store, runtimes)?</summary>
    public static bool StoreSystem(string name) => StoreSystemStart.Any(s => name.StartsWith(s, StringComparison.OrdinalIgnoreCase));

    // ---------- deleting ----------
    static bool Exists(string p) => File.Exists(p) || Directory.Exists(p);

    public static long SizeOf(string p)
    {
        try
        {
            if (File.Exists(p)) return new FileInfo(p).Length;
            long n = 0;
            var opt = new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = true };
            foreach (var f in new DirectoryInfo(p).EnumerateFiles("*", opt)) n += f.Length;
            return n;
        }
        catch { return 0; }
    }

    /// <summary>Deletes a file or folder for good (read-only files too). Links inside are removed, never followed.</summary>
    public static bool Delete(string p)
    {
        try
        {
            if (Directory.Exists(p))
            {
                var d = new DirectoryInfo(p);
                if (d.Attributes.HasFlag(FileAttributes.ReparsePoint)) { d.Delete(false); return true; }
                foreach (var c in d.EnumerateFileSystemInfos())
                {
                    if (c is DirectoryInfo) Delete(c.FullName);
                    else { try { c.Attributes = FileAttributes.Normal; } catch { } c.Delete(); }
                }
                d.Attributes = FileAttributes.Directory;
                d.Delete(false);
                return true;
            }
            if (File.Exists(p)) { try { File.SetAttributes(p, FileAttributes.Normal); } catch { } File.Delete(p); }
            return true;
        }
        catch { return false; }
    }

    /// <summary>v0.8: thumbnail and icon caches, deleted right away (only while Explorer is not running: panic).</summary>
    public static int DeleteExplorerCaches()
    {
        int n = 0;
        foreach (var f in TraceFiles.Where(t => t.Contains("/Explorer/")).Append("AppData/Local/IconCache.db"))
        {
            var slash = f.LastIndexOf('/');
            var dir = Home.Full(f[..slash]);
            if (!Directory.Exists(dir)) continue;
            foreach (var c in new DirectoryInfo(dir).EnumerateFiles(f[(slash + 1)..]))
                if (Delete(c.FullName)) n++;
        }
        return n;
    }

    /// <summary>v0.8: a program folder "Remove new apps" took is kept this long in .amnesia-trash, in case it was a mistake.</summary>
    public static readonly TimeSpan AppsKeptFor = TimeSpan.FromDays(3);

    /// <summary>v0.8: moves a file or folder into .amnesia-trash instead of deleting it (folder "…-apps" for program
    /// folders, kept 3 days). False when it can't be moved (in use); then nothing is deleted.</summary>
    public static bool ToTrash(string full, string tag = "apps")
    {
        try
        {
            var rel = Path.GetRelativePath(Home.User, full);
            if (rel.StartsWith("..") || Path.IsPathRooted(rel)) return false;
            var dest = Path.Combine(Home.Trash, $"{DateTime.Now:yyyyMMdd-HHmmss}-{tag}", rel);
            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            if (Directory.Exists(full)) Directory.Move(full, dest); else File.Move(full, dest);
            return true;
        }
        catch { return false; }
    }

    /// <summary>Empties .amnesia-trash. Anything Windows still holds open is tried again next time.
    /// v0.8: program folders ("…-apps") stay for 3 days first.</summary>
    static void Purge()
    {
        if (!Directory.Exists(Home.Trash)) return;
        foreach (var c in new DirectoryInfo(Home.Trash).EnumerateFileSystemInfos().ToList())
        {
            if (c.Name.EndsWith("-apps", StringComparison.OrdinalIgnoreCase) && DateTime.Now - c.CreationTime < AppsKeptFor) continue;
            Delete(c.FullName);
        }
        try { if (!Directory.EnumerateFileSystemEntries(Home.Trash).Any()) Directory.Delete(Home.Trash); } catch { }
    }
}
