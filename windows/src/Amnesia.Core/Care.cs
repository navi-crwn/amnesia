// v0.9 Care ("Perawatan"): free up space when you ask for it, always with a list to check first.
// Amnesia already wipes most of the user folder at sign out, so Care mostly matters for the Keep folder, the apps you
// kept and big files made in this session. Every feature works the same way:
//   scan (in the background, at most 30 s and 300 000 entries, can be cancelled) -> list with sizes and checkboxes
//   -> the page asks once more -> act -> a result per category and one History line ("care <feature> <items> <KB> <failed>").
// Rules for everything Care deletes (same as the Mac):
//   - never .amnesia (vault, settings), the Keep folder itself, the open Safe box, Windows' own folders, anything
//     outside the user folder, cloud folders; never anything that needs admin rights
//   - never follows links or junctions, and skips anything that sits below one
//   - the Keep List wins (only caches on it may still be ticked by hand)
//   - when a check can't tell (error, timeout, unreadable), the item is protected
//   - right before acting each item is looked at again: gone, changed or now protected = skipped, counted as failed
//   - apps leftovers, installers and build folders go to the Recycle Bin (given by Amnesia.exe); caches, Temp and the
//     Amnesia trash are deleted through CleanEngine.Delete; emptying the Recycle Bin is never ticked for you
// This file has no Windows-only code: the Recycle Bin, the registry and Explorer live in Amnesia.exe (CareWin.cs) and
// come in as delegates, so the tests run on any computer with a fake Recycle Bin.
using System.Diagnostics;

namespace Amnesia.Core;

/// <summary>One line in a Care list. The page only ever sends back the Id; the path stays here.</summary>
public sealed class CareItem
{
    public string Id { get; set; } = "";
    public string Feature { get; set; } = "";
    /// <summary>temp, crash, cache, atrash, bin, leftover, build, installer</summary>
    public string Cat { get; set; } = "";
    public string Full { get; set; } = "";
    /// <summary>Inside the user folder, with "/".</summary>
    public string Rel { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Group { get; set; }
    public long Bytes { get; set; }
    /// <summary>The size count was cut short (scan limit): "at least".</summary>
    public bool SizeCut { get; set; }
    /// <summary>A code the page turns into words (old-temp, cache, keeplist, git, recent, unchecked...).</summary>
    public string Reason { get; set; } = "";
    public bool Selected { get; set; }
    public bool Disabled { get; set; }
    /// <summary>delete (for good), recycle (Recycle Bin) or bin (empties the Recycle Bin).</summary>
    public string Where { get; set; } = "delete";
    public DateTime Newest { get; set; }
    // what the item looked like at scan time (checked again right before acting)
    internal bool IsDir;
    internal long Length;
    internal DateTime Stamp;
    internal DateTime Born;
}

public sealed record CareEntry(string Rel, long Bytes, bool Cut);

public sealed class CareOverview
{
    public long DiskTotal { get; set; } = -1;
    public long DiskFree { get; set; } = -1;
    /// <summary>keep, vault, atrash, bin, temp, downloads (-1 = not known).</summary>
    public Dictionary<string, CareEntry> Sizes { get; } = new();
    public List<CareEntry> Folders { get; } = new();
    public List<CareEntry> Files { get; } = new();
    public int OldDownloads { get; set; }
    public long OldDownloadsBytes { get; set; }
    public bool Cut { get; set; }
}

public sealed class CareCat
{
    public string Cat { get; set; } = "";
    public int Done { get; set; }
    public int Failed { get; set; }
    public long Bytes { get; set; }
}

public sealed class CareResult
{
    public string Feature { get; set; } = "";
    public List<CareCat> Cats { get; } = new();
    public int Done { get; set; }
    public int Failed { get; set; }
    /// <summary>Skipped because they changed (or became protected) since the scan.</summary>
    public int Changed { get; set; }
    public long Bytes { get; set; }
}

/// <summary>How far a scan may go: 30 s, 300 000 entries, or until Cancel.</summary>
public sealed class CareBudget
{
    public const int MaxEntries = 300_000;
    public static readonly TimeSpan MaxTime = TimeSpan.FromSeconds(30);
    readonly Stopwatch watch = Stopwatch.StartNew();
    readonly CancellationToken token;
    readonly int max;
    readonly TimeSpan time;
    public int Entries { get; private set; }
    public bool Cut { get; private set; }

    public CareBudget(CancellationToken token = default, int maxEntries = MaxEntries, TimeSpan? maxTime = null)
    {
        this.token = token;
        max = maxEntries;
        time = maxTime ?? MaxTime;
    }

    /// <summary>Counts one entry. False once the limit is reached (the scan then stops where it is). Cancel throws.</summary>
    public bool Step()
    {
        token.ThrowIfCancellationRequested();
        if (Cut) return false;
        Entries++;
        if (Entries > max || watch.Elapsed > time) { Cut = true; return false; }
        return true;
    }

    public bool Left
    {
        get
        {
            token.ThrowIfCancellationRequested();
            if (!Cut && watch.Elapsed > time) Cut = true;
            return !Cut;
        }
    }
}

public sealed class Care
{
    // ---------- given by Amnesia.exe (fakes in the tests) ----------
    /// <summary>Moves a file or folder (full path) to the Recycle Bin. True when it went. Not set: nothing is recycled.</summary>
    public Func<string, bool>? Recycle { get; set; }
    /// <summary>Empties the Recycle Bin for good.</summary>
    public Func<bool>? EmptyBin { get; set; }
    /// <summary>Bytes in the Recycle Bin (-1 = not known).</summary>
    public Func<long>? BinSize { get; set; }
    /// <summary>Cloud folders Windows knows about (full paths).</summary>
    public Func<IEnumerable<string>>? CloudRoots { get; set; }
    /// <summary>Is anything below rel tracked in this git repo? true / false, null = could not tell. Default: runs git.</summary>
    public Func<string, string, bool?> GitTracked { get; set; } = GitLsFiles;
    /// <summary>Now (the tests move it).</summary>
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public static readonly string[] Features = { "quick", "apps", "projects", "installers", "tune" };

    // ---------- what Care never touches ----------
    // Windows needs these, or they are Amnesia's own (same idea as the cleanup's built-in keep list)
    static readonly string[] Protected =
    {
        "NTUSER*", ".amnesia", "AppData/Local/Microsoft", "AppData/Roaming/Microsoft", "AppData/Local/Packages",
        "AppData/Local/Amnesia", "AppData/Local/Programs/Amnesia", "AppData/Local/Temp/.net", "AppData/Local/OneDrive",
        "Links", "Searches",
    };
    // folders Windows makes: their content may go, the folder itself never
    static readonly string[] Containers =
    {
        "AppData", "AppData/Roaming", "AppData/Local", "AppData/LocalLow", "AppData/Local/Temp", "AppData/Local/CrashDumps",
        "AppData/Local/Programs", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos", "Favorites", "Contacts",
        "Saved Games", "3D Objects", "source", "source/repos",
    };
    static readonly string[] CloudNames =
    {
        "OneDrive", "OneDrive - *", "Dropbox", "Dropbox (*)", "Google Drive", "My Drive", "iCloudDrive", "iCloud Drive", "iCloudPhotos",
        "iCloud Photos", "Nextcloud", "ownCloud", "MEGA", "MEGAsync", "Box", "Box Sync", "pCloud Drive", "Proton Drive", "Tresorit",
        "SynologyDrive", "Seafile", "Creative Cloud Files*",
    };
    const FileAttributes CloudBits = FileAttributes.Offline | (FileAttributes)0x40000 | (FileAttributes)0x400000;

    static string H => Home.User;
    static char Sep => Path.DirectorySeparatorChar;

    /// <summary>A full path as "a/b" inside the user folder; null outside it, "" for the user folder itself.</summary>
    public static string? RelOf(string full)
    {
        try
        {
            var rel = Path.GetRelativePath(H, Path.GetFullPath(full)).Replace('\\', '/').Trim('/');
            if (rel == ".") return "";
            if (rel == ".." || rel.StartsWith("../") || Path.IsPathRooted(rel) || rel.Contains("/../")) return null;
            return rel;
        }
        catch { return null; }
    }

    static bool Under(string rel, string p) => rel.Equals(p, StringComparison.OrdinalIgnoreCase) || Wild.Like(rel, p) || Wild.Like(rel, p + "/*");

    /// <summary>The Keep List lines that cover this item: the item is on it, inside one, or holds one.</summary>
    public static bool OnKeepList(string rel, IReadOnlyCollection<string> keep) =>
        keep.Any(p => p.Length > 0 && (Wild.Like(rel, p) || Wild.Like(rel, p + "/*") || Wild.Like(p, rel + "/*")));

    /// <summary>Is a link or junction (or the item itself) on the way from the user folder to this path? Errors count as yes.</summary>
    public static bool LinkOnPath(string full)
    {
        try
        {
            var rel = RelOf(full);
            if (string.IsNullOrEmpty(rel)) return true;
            var p = H;
            foreach (var part in rel.Split('/'))
            {
                p = Path.Combine(p, part);
                var info = new FileInfo(p);
                if (!info.Exists && !Directory.Exists(p)) return false; // gone: nothing to follow
                if (info.Attributes.HasFlag(FileAttributes.ReparsePoint) || info.LinkTarget != null) return true;
            }
            return false;
        }
        catch { return true; }
    }

    bool InCloud(string rel)
    {
        var top = rel.Split('/')[0];
        if (CloudNames.Any(n => Wild.Like(top, n))) return true;
        try
        {
            foreach (var c in CloudRoots?.Invoke() ?? Enumerable.Empty<string>())
            {
                var cr = RelOf(c);
                if (cr == null) continue;          // outside the user folder: not ours anyway
                if (cr.Length == 0) continue;      // never the whole user folder
                if (Under(rel, cr)) return true;
            }
        }
        catch { return true; }
        return false;
    }

    /// <summary>The one check every Care delete passes (R1): null = may go, else why not (outside, amnesia, keep-root,
    /// system, cloud, link, gone).</summary>
    public string? Refuse(string full, string cat)
    {
        try { return RefuseOrThrow(full, cat); }
        catch { return "unchecked"; }
    }

    string? RefuseOrThrow(string full, string cat)
    {
        var rel = RelOf(full);
        if (rel == null || rel.Length == 0) return "outside";
        if (Under(rel, ".amnesia")) return "amnesia";
        if (Under(rel, ".amnesia-trash"))
        {
            // only the Amnesia trash feature, and only one batch at a time (never the trash folder itself)
            if (cat != "atrash" || rel.Split('/').Length != 2) return "amnesia";
        }
        var keepRel = Conf.KeepRel;
        if (keepRel.Length > 0)
        {
            if (rel.Equals(keepRel, StringComparison.OrdinalIgnoreCase) || Wild.Like(keepRel, rel + "/*")) return "keep-root";
            if (Under(rel, keepRel + "/Safe")) return "keep-root"; // the open Safe box
        }
        else
        {
            // Keep outside the user folder: nothing inside the user folder can be it, but never the Keep folder's path
            var kd = Conf.KeepDir;
            if (kd.Length > 0 && (Path.GetFullPath(full).TrimEnd(Sep).Equals(Path.GetFullPath(kd).TrimEnd(Sep), StringComparison.OrdinalIgnoreCase))) return "keep-root";
        }
        if (Containers.Any(c => rel.Equals(c, StringComparison.OrdinalIgnoreCase))) return "system";
        if (Protected.Any(p => Under(rel, p))) return "system";
        // a folder that holds something protected (never AppData\Local whole etc.)
        if (Protected.Any(p => Wild.Like(p, rel + "/*"))) return "system";
        if (InCloud(rel)) return "cloud";
        if (!Exists(full)) return "gone";
        if (LinkOnPath(full)) return "link";
        try { if ((File.GetAttributes(full) & CloudBits) != 0) return "cloud"; } catch { return "gone"; }
        return null;
    }

    // ---------- walking a folder (never follows links) ----------
    sealed class Walked
    {
        public long Bytes;
        public bool Cut;
        public bool Unreadable;
        public bool Git;
        public bool Secret;
        public bool Cloud;
        public DateTime Newest;
        public int Sampled;
    }

    static readonly string[] SecretFiles = { "*.pem", "*.p12", "*.pfx", "*.key", "id_rsa*", "id_ed25519*", "id_ecdsa*", "*.keystore", "*.jks" };
    const int Sample = 5000;

    static bool IsLink(FileSystemInfo i) => i.Attributes.HasFlag(FileAttributes.ReparsePoint);

    /// <summary>Size, newest change (first 5000 entries), and what is inside. Links are counted as nothing, never entered.</summary>
    static Walked Walk(string dir, CareBudget b, bool look = false)
    {
        var w = new Walked();
        var root = new DirectoryInfo(dir);
        try { w.Newest = root.LastWriteTimeUtc; } catch { }
        var stack = new Stack<DirectoryInfo>();
        stack.Push(root);
        var opt = new EnumerationOptions { RecurseSubdirectories = false, IgnoreInaccessible = false, AttributesToSkip = 0, ReturnSpecialDirectories = false };
        while (stack.Count > 0)
        {
            var d = stack.Pop();
            IEnumerable<FileSystemInfo> kids;
            try { kids = d.EnumerateFileSystemInfos("*", opt).ToList(); }
            catch { w.Unreadable = true; continue; }
            foreach (var c in kids)
            {
                if (!b.Step()) { w.Cut = true; return w; }
                FileAttributes a;
                try { a = c.Attributes; } catch { w.Unreadable = true; continue; }
                if (w.Sampled < Sample)
                {
                    w.Sampled++;
                    try { var t = c.LastWriteTimeUtc; if (t > w.Newest) w.Newest = t; } catch { }
                }
                if (look)
                {
                    if (c.Name.Equals(".git", StringComparison.OrdinalIgnoreCase)) w.Git = true;
                    if (c is FileInfo && SecretFiles.Any(s => Wild.Like(c.Name, s))) w.Secret = true;
                    if ((a & CloudBits) != 0) w.Cloud = true;
                }
                if (a.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (c is DirectoryInfo sub) stack.Push(sub);
                else if (c is FileInfo f) { try { w.Bytes += f.Length; } catch { } }
            }
        }
        return w;
    }

    static (bool dir, long len, DateTime stamp, DateTime born)? Look(string full)
    {
        try
        {
            FileSystemInfo i = Directory.Exists(full) ? new DirectoryInfo(full) : new FileInfo(full);
            if (!i.Exists) return null;
            i.Refresh();
            return (i is DirectoryInfo, i is FileInfo f ? f.Length : 0, i.LastWriteTimeUtc, i.CreationTimeUtc);
        }
        catch { return null; }
    }

    int nextId;
    CareItem Item(string feature, string cat, string full, string where, string reason, bool selected, long bytes = 0)
    {
        var rel = RelOf(full) ?? "";
        var it = new CareItem
        {
            Id = $"{feature}-{++nextId}", Feature = feature, Cat = cat, Full = full, Rel = rel, Name = Path.GetFileName(full.TrimEnd(Sep)),
            Where = where, Reason = reason, Selected = selected, Bytes = bytes,
        };
        if (Look(full) is { } l) { it.IsDir = l.dir; it.Length = l.len; it.Stamp = l.stamp; it.Born = l.born; it.Newest = l.stamp; }
        return it;
    }

    static List<FileSystemInfo> Kids(string dir)
    {
        try { return new DirectoryInfo(dir).EnumerateFileSystemInfos().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase).ToList(); }
        catch { return new List<FileSystemInfo>(); }
    }

    /// <summary>v0.9: the Keep List, only when it can be trusted. Missing (it was there before) or unreadable: Care stops
    /// with "keeplist-missing" / "keeplist-unreadable" and deletes nothing, like the cleanup (could not tell = protected).</summary>
    static IReadOnlyCollection<string> KeepPaths()
    {
        var ks = KeepList.Check(out _);
        if (ks != null) throw new InvalidOperationException("keeplist-" + ks);
        return KeepList.Paths();
    }

    /// <summary>Marks an item protected when the rules or the Keep List say so. Caches on the Keep List stay selectable.</summary>
    void Guard(CareItem it, IReadOnlyCollection<string> keep)
    {
        var why = Refuse(it.Full, it.Cat);
        if (why != null) { it.Disabled = true; it.Selected = false; it.Reason = why; return; }
        if (OnKeepList(it.Rel, keep))
        {
            it.Selected = false;
            it.Reason = "keeplist";
            if (it.Cat is not ("cache" or "temp" or "crash")) it.Disabled = true;
        }
    }

    // =====================================================================================================
    // 1. Disk overview (read only)
    // =====================================================================================================
    public CareOverview Overview(CareBudget b)
    {
        var o = new CareOverview();
        try
        {
            var root = Path.GetPathRoot(H);
            if (!string.IsNullOrEmpty(root))
            {
                var d = new DriveInfo(root);
                o.DiskTotal = d.TotalSize;
                o.DiskFree = d.AvailableFreeSpace;
            }
        }
        catch { }
        CareEntry Size(string rel)
        {
            var full = Home.Full(rel);
            if (!Directory.Exists(full) || LinkOnPath(full)) return new CareEntry(rel, Directory.Exists(full) ? -1 : 0, false);
            var w = Walk(full, b);
            return new CareEntry(rel, w.Bytes, w.Cut || w.Unreadable);
        }
        var keepRel = Conf.KeepRel;
        long bin = -1;
        try { bin = BinSize?.Invoke() ?? -1; } catch { }
        o.Sizes["bin"] = new CareEntry("", bin, false);
        if (keepRel.Length > 0) o.Sizes["keep"] = Size(keepRel);
        o.Sizes["vault"] = Size(".amnesia/vault");
        o.Sizes["atrash"] = Size(".amnesia-trash");
        o.Sizes["temp"] = Size("AppData/Local/Temp");
        o.Sizes["downloads"] = Size("Downloads");

        // big files (200 MB and more) in Keep, Downloads and Desktop, 4 levels deep
        const long Big = 200L << 20;
        var big = new List<CareEntry>();
        void Find(string rel, int depth)
        {
            if (depth > 4 || !b.Left) return;
            foreach (var c in Kids(Home.Full(rel)))
            {
                if (!b.Step()) return;
                if (IsLink(c)) continue;
                var r = $"{rel}/{c.Name}";
                if (c is DirectoryInfo) Find(r, depth + 1);
                else if (c is FileInfo f && f.Length >= Big) big.Add(new CareEntry(r, f.Length, false));
            }
        }
        foreach (var r in new[] { keepRel, "Downloads", "Desktop" }.Where(r => r.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase))
            if (Directory.Exists(Home.Full(r)) && !LinkOnPath(Home.Full(r))) Find(r, 1);
        o.Files.AddRange(big.OrderByDescending(x => x.Bytes).Take(10));

        // old downloads: not changed for 30 days (wiped at the next sign out anyway, unless kept)
        var old = Now() - TimeSpan.FromDays(30);
        void Old(string rel, int depth)
        {
            if (depth > 4 || !b.Left) return;
            foreach (var c in Kids(Home.Full(rel)))
            {
                if (!b.Step()) return;
                if (IsLink(c) || c.Name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                if (c is DirectoryInfo) Old($"{rel}/{c.Name}", depth + 1);
                else if (c is FileInfo f && f.LastWriteTimeUtc < old) { o.OldDownloads++; o.OldDownloadsBytes += f.Length; }
            }
        }
        if (Directory.Exists(Home.Full("Downloads")) && !LinkOnPath(Home.Full("Downloads"))) Old("Downloads", 1);

        // the biggest folders: one level of the user folder and of Keep (last: AppData is slow, may be cut)
        var folders = new List<CareEntry>();
        if (keepRel.Length > 0 && Directory.Exists(Home.Full(keepRel)))
            foreach (var c in Kids(Home.Full(keepRel)).OfType<DirectoryInfo>().Where(c => !IsLink(c)))
                folders.Add(Size($"{keepRel}/{c.Name}"));
        foreach (var c in Kids(H).OfType<DirectoryInfo>().Where(c => !IsLink(c)))
        {
            if (keepRel.Length > 0 && c.Name.Equals(keepRel, StringComparison.OrdinalIgnoreCase) && o.Sizes.TryGetValue("keep", out var k)) { folders.Add(k); continue; }
            if (c.Name.Equals("Downloads", StringComparison.OrdinalIgnoreCase)) { folders.Add(o.Sizes["downloads"]); continue; }
            if (!b.Left) { folders.Add(new CareEntry(c.Name, -1, true)); continue; }
            folders.Add(Size(c.Name));
        }
        o.Folders.AddRange(folders.Where(f => f.Bytes > 0).OrderByDescending(f => f.Bytes).Take(10));
        o.Cut = b.Cut;
        Home.Trace("care", $"overview: {b.Entries} entries{(b.Cut ? ", cut short" : "")}");
        return o;
    }

    // =====================================================================================================
    // 2. Clean now: Temp, crash dumps, app caches, the Amnesia trash, the Recycle Bin
    // =====================================================================================================
    public static readonly string[] CacheNames = { "Cache", "Code Cache", "GPUCache", "DawnCache", "ShaderCache", "GrShaderCache" };

    public List<CareItem> ScanQuick(CareBudget b)
    {
        var list = new List<CareItem>();
        var keep = KeepPaths();
        var now = Now();
        // Temp: what was not changed for a day (newest inside counts). Never .net (running programs unpack there).
        var temp = Home.Full("AppData/Local/Temp");
        if (Directory.Exists(temp) && !LinkOnPath(temp))
            foreach (var c in Kids(temp))
            {
                if (!b.Left) break;
                if (IsLink(c) || c.Name.Equals(".net", StringComparison.OrdinalIgnoreCase)) continue;
                var it = Item("quick", "temp", c.FullName, "delete", "old-temp", true);
                if (c is DirectoryInfo)
                {
                    var w = Walk(c.FullName, b);
                    it.Bytes = w.Bytes; it.SizeCut = w.Cut; it.Newest = w.Newest;
                    if (w.Cut) continue; // could not look at all of it: may be in use, left alone
                }
                else it.Bytes = ((FileInfo)c).Length;
                if (now - it.Newest < TimeSpan.FromHours(24)) continue; // in use today
                Guard(it, keep);
                list.Add(it);
            }
        // crash dumps
        var dumps = Home.Full("AppData/Local/CrashDumps");
        if (Directory.Exists(dumps) && !LinkOnPath(dumps))
            foreach (var c in Kids(dumps))
            {
                if (!b.Left) break;
                if (IsLink(c)) continue;
                var it = Item("quick", "crash", c.FullName, "delete", "crash", true);
                if (c is DirectoryInfo) { var w = Walk(c.FullName, b); it.Bytes = w.Bytes; it.SizeCut = w.Cut; }
                else it.Bytes = ((FileInfo)c).Length;
                Guard(it, keep);
                list.Add(it);
            }
        // app caches: folders named exactly Cache, Code Cache, GPUCache... in an app's own folder (5 levels at most)
        foreach (var top in new[] { "AppData/Local", "AppData/Roaming" })
        {
            var full = Home.Full(top);
            if (!Directory.Exists(full) || LinkOnPath(full)) continue;
            foreach (var app in Kids(full).OfType<DirectoryInfo>())
            {
                if (!b.Left) break;
                if (IsLink(app) || AppMatch.Skip.Contains(app.Name, StringComparer.OrdinalIgnoreCase)) continue;
                FindCaches(app, 1, b, list, keep);
            }
        }
        // the Amnesia trash: each batch (program folders of "Remove new apps" wait 3 days first)
        if (Directory.Exists(Home.Trash) && !LinkOnPath(Home.Trash))
            foreach (var c in Kids(Home.Trash))
            {
                if (!b.Left) break;
                if (IsLink(c)) continue;
                if (c.Name.EndsWith("-apps", StringComparison.OrdinalIgnoreCase) && DateTime.Now - c.CreationTime < CleanEngine.AppsKeptFor) continue;
                if (now - c.LastWriteTimeUtc < TimeSpan.FromSeconds(60) || now - c.CreationTimeUtc < TimeSpan.FromSeconds(60)) continue; // a cleanup is filling it
                var it = Item("quick", "atrash", c.FullName, "delete", "atrash", true);
                if (c is DirectoryInfo) { var w = Walk(c.FullName, b); it.Bytes = w.Bytes; it.SizeCut = w.Cut; }
                else it.Bytes = ((FileInfo)c).Length;
                var why = Refuse(it.Full, "atrash");
                if (why != null) { it.Disabled = true; it.Selected = false; it.Reason = why; }
                list.Add(it);
            }
        // the Recycle Bin: for good, never ticked for you
        if (EmptyBin != null)
        {
            long n = -1;
            try { n = BinSize?.Invoke() ?? -1; } catch { }
            if (n != 0)
                list.Add(new CareItem { Id = $"quick-{++nextId}", Feature = "quick", Cat = "bin", Name = "Recycle Bin", Where = "bin", Reason = "bin", Bytes = Math.Max(0, n), SizeCut = n < 0 });
        }
        Home.Trace("care", $"scan quick: {list.Count} items, {b.Entries} entries{(b.Cut ? ", cut short" : "")}");
        return list;
    }

    void FindCaches(DirectoryInfo dir, int depth, CareBudget b, List<CareItem> list, IReadOnlyCollection<string> keep)
    {
        if (depth > 5) return;
        foreach (var c in Kids(dir.FullName).OfType<DirectoryInfo>())
        {
            if (!b.Step()) return;
            if (IsLink(c)) continue;
            if (CacheNames.Contains(c.Name, StringComparer.OrdinalIgnoreCase))
            {
                var it = Item("quick", "cache", c.FullName, "delete", "cache", true);
                var w = Walk(c.FullName, b);
                it.Bytes = w.Bytes; it.SizeCut = w.Cut; it.Newest = w.Newest;
                var rel = it.Rel.Split('/');
                it.Group = rel.Length > 2 ? rel[2] : null; // the app's folder name
                Guard(it, keep);
                if (it.Bytes > 0 || it.Disabled) list.Add(it);
                continue; // never inside a cache
            }
            FindCaches(c, depth + 1, b, list, keep);
        }
    }

    // =====================================================================================================
    // 3. Leftovers of an app that was just uninstalled (the uninstall itself runs in Amnesia.exe)
    // =====================================================================================================
    static readonly string[] LeftCacheNames = { "Cache", "Code Cache", "GPUCache", "DawnCache", "ShaderCache", "GrShaderCache", "Temp", "tmp", "CrashDumps", "Crashpad", "logs", "Logs" };

    /// <summary>AppData\Local|Roaming|LocalLow\&lt;name&gt; or \&lt;publisher&gt;\&lt;name&gt;, matched by the exact name
    /// (letters and digits, without version). Cache and Temp folders inside are ticked, the rest (your data) is not.</summary>
    public List<CareItem> ScanLeftovers(string name, string? publisher, CareBudget b)
    {
        var list = new List<CareItem>();
        var keep = KeepPaths();
        var n = Leftovers.Norm(name);
        var pub = string.IsNullOrWhiteSpace(publisher) ? "" : Leftovers.Norm(publisher);
        if (n.Length < 3) return list;
        bool Fits(string folder) { var f = Leftovers.Norm(folder); return f.Length >= 3 && f == n && !AppMatch.Technical(folder); }
        var found = new List<string>();
        foreach (var top in new[] { "AppData/Local", "AppData/Roaming", "AppData/LocalLow" })
        {
            var full = Home.Full(top);
            if (!Directory.Exists(full) || LinkOnPath(full)) continue;
            foreach (var d in Kids(full).OfType<DirectoryInfo>())
            {
                if (IsLink(d) || AppMatch.Skip.Contains(d.Name, StringComparer.OrdinalIgnoreCase) || Leftovers.SystemNames.Contains(d.Name, StringComparer.OrdinalIgnoreCase)) continue;
                if (Fits(d.Name)) { found.Add(d.FullName); continue; }
                if (pub.Length >= 3 && Leftovers.Norm(d.Name) == pub)
                    foreach (var s in Kids(d.FullName).OfType<DirectoryInfo>())
                        if (!IsLink(s) && Fits(s.Name)) found.Add(s.FullName);
            }
        }
        foreach (var f in found)
        {
            if (!b.Left) break;
            var w = Walk(f, b, look: true);
            var it = Item("apps", "leftover", f, "recycle", "leftover-data", false, w.Bytes);
            it.SizeCut = w.Cut; it.Newest = w.Newest; it.Group = name;
            Guard(it, keep);
            list.Add(it);
            if (it.Disabled) continue;
            // cache and temp folders inside (3 levels): ticked
            void Inner(string dir, int depth)
            {
                if (depth > 3) return;
                foreach (var c in Kids(dir).OfType<DirectoryInfo>())
                {
                    if (!b.Step()) return;
                    if (IsLink(c)) continue;
                    if (LeftCacheNames.Contains(c.Name, StringComparer.OrdinalIgnoreCase))
                    {
                        var cw = Walk(c.FullName, b);
                        var ci = Item("apps", "leftover", c.FullName, "recycle", "leftover-cache", true, cw.Bytes);
                        ci.SizeCut = cw.Cut; ci.Group = name;
                        Guard(ci, keep);
                        list.Add(ci);
                        continue;
                    }
                    Inner(c.FullName, depth + 1);
                }
            }
            Inner(f, 1);
        }
        Home.Trace("care", $"scan leftovers: {list.Count} items");
        return list;
    }

    // =====================================================================================================
    // 4. Project build folders (node_modules, target, build, dist, bin/obj...)
    // =====================================================================================================
    public static readonly string[] ProjectRoots = { "Developer", "Projects", "Code", "dev", "src", "work", "GitHub", "Documents", "Desktop", "source/repos" };
    static readonly string[] VmExts = { ".utm", ".vmwarevm", ".pvm", ".vbox", ".vdi", ".vmdk", ".qcow2", ".vhd", ".vhdx", ".vmx" };

    /// <summary>The marker files a build folder needs next to it, or null when this name is not a build folder.</summary>
    static string[]? Markers(string name) => name switch
    {
        "node_modules" or ".next" or ".nuxt" or ".turbo" => new[] { "package.json" },
        "dist" => new[] { "package.json", "pyproject.toml", "setup.py" },
        "build" => new[] { "package.json", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "pyproject.toml", "setup.py" },
        "target" => new[] { "Cargo.toml", "pom.xml" },
        ".build" => new[] { "Package.swift" },
        "DerivedData" => Array.Empty<string>(),
        ".gradle" => new[] { "build.gradle", "build.gradle.kts" },
        "bin" or "obj" => new[] { "*.csproj", "*.fsproj", "*.vbproj" },
        _ => null,
    };

    static bool Hidden(FileSystemInfo c)
    {
        if (c.Name.StartsWith('.')) return true;
        try { return c.Attributes.HasFlag(FileAttributes.Hidden) || c.Attributes.HasFlag(FileAttributes.System); } catch { return true; }
    }

    static bool NeverInto(DirectoryInfo d, List<FileSystemInfo> kids)
    {
        var n = d.Name;
        if (n.EndsWith(".app", StringComparison.OrdinalIgnoreCase) || n.EndsWith(".sparsebundle", StringComparison.OrdinalIgnoreCase)) return true;
        if (VmExts.Any(e => n.EndsWith(e, StringComparison.OrdinalIgnoreCase))) return true;
        return kids.Any(k => k is FileInfo && (k.Name.EndsWith(".vmx", StringComparison.OrdinalIgnoreCase) || k.Name.EndsWith(".vbox", StringComparison.OrdinalIgnoreCase)));
    }

    public List<CareItem> ScanProjects(CareBudget b)
    {
        var list = new List<CareItem>();
        var keep = KeepPaths();
        var roots = new List<string>();
        if (Conf.KeepRel.Length > 0) roots.Add(Conf.KeepRel);
        roots.AddRange(ProjectRoots);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var r in roots)
        {
            var full = Home.Full(r);
            if (!b.Left) break;
            if (!Directory.Exists(full) || LinkOnPath(full)) continue;
            Projects(new DirectoryInfo(full), 1, b, list, keep, seen);
        }
        Home.Trace("care", $"scan projects: {list.Count} items, {b.Entries} entries{(b.Cut ? ", cut short" : "")}");
        return list;
    }

    void Projects(DirectoryInfo dir, int depth, CareBudget b, List<CareItem> list, IReadOnlyCollection<string> keep, HashSet<string> seen)
    {
        if (depth > 6 || !seen.Add(dir.FullName)) return;
        var rel = RelOf(dir.FullName) ?? "";
        if (Under(rel, "AppData") || Under(rel, ".amnesia") || Under(rel, ".amnesia-trash") || (Conf.KeepRel.Length > 0 && Under(rel, Conf.KeepRel + "/Safe"))) return;
        var kids = Kids(dir.FullName);
        if (NeverInto(dir, kids)) return;
        var files = kids.OfType<FileInfo>().Select(f => f.Name).ToList();
        foreach (var c in kids.OfType<DirectoryInfo>())
        {
            if (!b.Step()) return;
            if (IsLink(c)) continue;
            var markers = Markers(c.Name);
            if (markers != null && (markers.Length == 0 || markers.Any(m => files.Any(f => Wild.Like(f, m)))))
            {
                list.Add(Build(c, b, keep));
                continue; // never inside a build folder
            }
            if (Hidden(c) || c.Name.Equals("node_modules", StringComparison.OrdinalIgnoreCase)) continue;
            Projects(c, depth + 1, b, list, keep, seen);
        }
    }

    CareItem Build(DirectoryInfo d, CareBudget b, IReadOnlyCollection<string> keep)
    {
        var w = Walk(d.FullName, b, look: true);
        var it = Item("projects", "build", d.FullName, "recycle", "build-old", false, w.Bytes);
        it.SizeCut = w.Cut; it.Newest = w.Newest;
        it.Group = RelOf(d.Parent!.FullName);
        string? why = null;
        if (w.Cut || w.Unreadable) why = "unchecked";
        else if (w.Git) why = "nested-git";
        else if (w.Secret) why = "secret";
        else if (w.Cloud) why = "cloud";
        else
        {
            // inside a git repo: anything in it tracked by git = protected; git missing, error or timeout = protected
            var repo = Repo(d.Parent!.FullName);
            if (repo != null)
            {
                var r = Path.GetRelativePath(repo, d.FullName).Replace('\\', '/');
                bool? tracked;
                try { tracked = GitTracked(repo, r); } catch { tracked = null; }
                if (tracked != false) why = tracked == true ? "git" : "unchecked";
            }
        }
        if (why != null) { it.Disabled = true; it.Reason = why; return it; }
        Guard(it, keep);
        if (it.Disabled || it.Reason == "keeplist") { it.Disabled = true; return it; }
        // used in the last 7 days (or no date): listed, not ticked
        var old = it.Newest != default && Now() - it.Newest > TimeSpan.FromDays(7);
        it.Selected = old;
        it.Reason = old ? "build-old" : "build-recent";
        return it;
    }

    /// <summary>The nearest folder above with a .git in it (up to the user folder), or null.</summary>
    static string? Repo(string dir)
    {
        try
        {
            for (var d = new DirectoryInfo(dir); d != null; d = d.Parent)
            {
                var rel = RelOf(d.FullName);
                if (rel == null) return null;
                var g = Path.Combine(d.FullName, ".git");
                if (Directory.Exists(g) || File.Exists(g)) return d.FullName;
                if (rel.Length == 0) return null;
            }
        }
        catch { }
        return null;
    }

    /// <summary>git -C repo ls-files -z -- rel (5 s). Output = tracked. Error, timeout or no git = null (protected).</summary>
    public static bool? GitLsFiles(string repo, string rel)
    {
        try
        {
            var psi = new ProcessStartInfo("git") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
            foreach (var a in new[] { "-C", repo, "ls-files", "-z", "--", rel }) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi);
            if (p == null) return null;
            var o = p.StandardOutput.ReadToEndAsync();
            var e = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(5000)) { try { p.Kill(true); } catch { } return null; }
            if (!o.Wait(2000)) return null;
            if (p.ExitCode != 0) return null;
            return o.Result.Length > 0;
        }
        catch { return null; }
    }

    // =====================================================================================================
    // 5. Old installers in Downloads, Desktop and Keep (2 levels)
    // =====================================================================================================
    static readonly string[] Packages = { ".msi", ".msix", ".msixbundle", ".appx" };
    static readonly string[] NeverListed = { ".sparsebundle", ".sparseimage", ".utm", ".vmwarevm", ".pvm", ".vbox", ".vdi", ".vmdk", ".qcow2", ".vhd", ".vhdx" };

    static bool SetupName(string name)
    {
        var n = Path.GetFileNameWithoutExtension(name).ToLowerInvariant();
        return n.Contains("setup") || n.Contains("install");
    }

    public List<CareItem> ScanInstallers(CareBudget b)
    {
        var list = new List<CareItem>();
        var keep = KeepPaths();
        var now = Now();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        void Look(string dir, int depth)
        {
            if (depth > 2 || !seen.Add(dir)) return;
            var kids = Kids(dir);
            if (depth > 1 && NeverInto(new DirectoryInfo(dir), kids)) return;
            foreach (var c in kids)
            {
                if (!b.Step()) return;
                if (IsLink(c)) continue;
                if (c is DirectoryInfo sub) { if (!Hidden(sub)) Look(sub.FullName, depth + 1); continue; }
                if (c is not FileInfo f) continue;
                var ext = f.Extension.ToLowerInvariant();
                if (NeverListed.Contains(ext) || f.Name.StartsWith("Brankas.", StringComparison.OrdinalIgnoreCase)) continue;
                bool oldEnough = now - f.LastWriteTimeUtc > TimeSpan.FromDays(14);
                CareItem? it = null;
                if (Packages.Contains(ext)) it = Item("installers", "installer", f.FullName, "recycle", oldEnough ? "installer-old" : "installer-new", oldEnough, f.Length);
                else if (ext == ".exe" && SetupName(f.Name)) it = Item("installers", "installer", f.FullName, "recycle", "setup-exe", false, f.Length);
                else if (ext == ".zip" && SetupName(f.Name)) it = Item("installers", "installer", f.FullName, "recycle", "setup-zip", false, f.Length);
                else if (ext == ".iso") it = Item("installers", "installer", f.FullName, "recycle", "disc-image", false, f.Length);
                if (it == null) continue;
                it.Group = RelOf(dir);
                Guard(it, keep);
                list.Add(it);
            }
        }
        foreach (var r in new[] { "Downloads", "Desktop", Conf.KeepRel }.Where(r => r.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var full = Home.Full(r);
            if (Directory.Exists(full) && !LinkOnPath(full)) Look(full, 1);
        }
        Home.Trace("care", $"scan installers: {list.Count} items");
        return list;
    }

    // =====================================================================================================
    // Acting on what was ticked
    // =====================================================================================================
    /// <summary>Did the item change since the scan (other file or folder, other size, other time)? Errors count as changed.</summary>
    static bool Changed(CareItem it)
    {
        var l = Look(it.Full);
        if (l == null) return true;
        var (dir, len, stamp, born) = l.Value;
        return dir != it.IsDir || born != it.Born || len != it.Length || stamp != it.Stamp;
    }

    static bool Exists(string p)
    {
        try { return File.Exists(p) || Directory.Exists(p) || new FileInfo(p).LinkTarget != null; }
        catch { return true; } // can't tell: treat as still there
    }

    /// <summary>Acts on the ticked items of one scan. baseItems / baseKb: what came before (the uninstall itself).
    /// Writes one History line and steps (counts only) to trace.log.</summary>
    public CareResult Act(string feature, IEnumerable<CareItem> chosen, CancellationToken token = default, int baseItems = 0, long baseKb = 0, int baseFailed = 0)
    {
        var r = new CareResult { Feature = feature };
        var keep = KeepPaths();
        CareCat Cat(string c)
        {
            var x = r.Cats.FirstOrDefault(k => k.Cat == c);
            if (x == null) { x = new CareCat { Cat = c }; r.Cats.Add(x); }
            return x;
        }
        // the deepest first: a cache inside a leftover goes before the leftover
        var todo = chosen.Where(i => !i.Disabled && i.Feature == feature).OrderByDescending(i => i.Full.Length).ToList();
        // the same as at scan time? Looked at for all of them right before acting (taking a cache out of a leftover
        // folder changes the folder's time, so this can't wait until each turn)
        var moved = todo.Where(i => i.Where != "bin" && Changed(i)).Select(i => i.Id).ToHashSet();
        var gone = new List<(string full, long bytes)>(); // v0.9: what went, so a folder around it is not counted twice
        foreach (var it in todo)
        {
            if (token.IsCancellationRequested) break;
            var cat = Cat(it.Cat);
            if (it.Where == "bin")
            {
                bool ok = false;
                try { ok = EmptyBin?.Invoke() == true; } catch { }
                if (ok) { cat.Done++; cat.Bytes += it.Bytes; } else cat.Failed++;
                continue;
            }
            // looked at again right now: still there, the same, not a link, still allowed (Care's rules, then the
            // cleanup's one check: never the user folder, the Keep folder itself, .amnesia, a link, outside the user folder)
            if (moved.Contains(it.Id) || Refuse(it.Full, it.Cat) != null || LinkOnPath(it.Full) || CleanEngine.Refuse(it.Full, insideKeep: true) != null
                || (OnKeepList(it.Rel, keep) && it.Cat is not ("cache" or "temp" or "crash")))
            { cat.Failed++; r.Changed++; continue; }
            bool done;
            long freed = it.Bytes;
            if (it.Where == "recycle")
            {
                try { done = Recycle?.Invoke(it.Full) == true; } catch { done = false; }
                done = done && !Exists(it.Full);
                if (!done) freed = 0;
            }
            else
            {
                done = CleanEngine.Delete(it.Full) && !Exists(it.Full);
                // Windows held some files open: count what did go
                if (!done) freed = Exists(it.Full) ? Math.Max(0, it.Bytes - CleanEngine.SizeOf(it.Full)) : it.Bytes;
            }
            // a folder whose ticked cache went just before: that cache was counted already
            long inner = gone.Where(g => g.full.StartsWith(it.Full.TrimEnd(Sep) + Sep, StringComparison.OrdinalIgnoreCase)).Sum(g => g.bytes);
            freed = Math.Max(0, freed - inner);
            if (done) cat.Done++; else cat.Failed++;
            cat.Bytes += freed;
            if (freed > 0) gone.Add((it.Full, freed));
        }
        r.Done = r.Cats.Sum(c => c.Done);
        r.Failed = r.Cats.Sum(c => c.Failed);
        r.Bytes = r.Cats.Sum(c => c.Bytes);
        History(feature, r.Done + baseItems, r.Bytes / 1024 + baseKb, r.Failed + baseFailed);
        Home.Trace("care", $"{feature}: {r.Done} done, {r.Failed} failed ({r.Changed} changed since the scan)");
        return r;
    }

    /// <summary>"care &lt;feature&gt; &lt;items&gt; &lt;KB&gt; &lt;failed&gt;" in history.log (KB, like the Mac).</summary>
    public static void History(string feature, int items, long kb, int failed) =>
        Home.History("care", $"{feature} {items} {Math.Max(0, kb)} {failed}");
}
