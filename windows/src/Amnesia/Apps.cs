// v0.4 "Remove new apps" (Settings → Advanced, off unless you switch it on). Same idea as the Mac:
// at Turn On Amnesia writes down the programs that are installed (apps-baseline.txt). At sign out, programs installed
// "just for you" after that are removed, unless you pressed Keep (then they join the list).
//   - just for you (AppData\Local\Programs, Discord, VS Code user setup...): their files already go with the cleanup;
//     Amnesia also removes their entry in Apps & features, their Start menu shortcut and their "start with Windows" entry.
//   - Microsoft Store apps you installed: removed at the next sign in check (Windows' own app manager, no admin).
//   - for everyone (Program Files): need admin, so they are only listed, with an Uninstall button (Windows asks first).
//   - v0.5: settings new programs wrote in your part of the registry (HKCU\Software\<name>) go too (idea from Pearcleaner
//     and Bulk Crap Uninstaller). "Find leftovers" lists folders that uninstallers left behind.
// v0.8.1: "Keep" also puts the app's program folder and data folders on the Keep List (Keep only wrote the app down,
//   and the normal cleanup still wiped AppData\Local\Programs\<app>, leaving a broken app). Rows of one app are shown as
//   one (Core\NewApps.cs), a registry key named by a GUID gets a real name, and an app that was only updated is not new.
//   A new app's program folder now waits 3 days in the trash also when the normal cleanup takes it (NewFolders).
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

sealed record NewApp(string Id, string Kind, string Name, bool Auto, string? Uninstall, string? Location = null, string? Publisher = null);

/// <summary>v0.8.1: the rows of one app, shown as one line.</summary>
sealed record NewAppGroup(string Name, List<NewApp> Items)
{
    public string Id => Items[0].Id;
    public NewApp? Uninstaller => Items.FirstOrDefault(a => a.Kind == "machine" && a.Uninstall != null);
}

static class Apps
{
    const string Uninstall = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    static string File => Path.Combine(Core.Home.Dir, "apps-baseline.txt");
    static string StartMenu => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"Microsoft\Windows\Start Menu\Programs");
    // Windows' own apps (and Microsoft apps Windows installs by itself) are never removed automatically
    static readonly string[] SystemPrefixes = { "Microsoft.", "MicrosoftWindows.", "Windows.", "MicrosoftCorporationII.", "Clipchamp.", "MSTeams" };

    public static bool On => Conf.On("REMOVE_NEW_APPS");
    public static bool HasBaseline => System.IO.File.Exists(File);

    /// <summary>Everything installed right now: id → (kind, name, auto-removable, uninstall command).</summary>
    static Dictionary<string, NewApp> Current(bool withStore)
    {
        var all = new Dictionary<string, NewApp>(StringComparer.OrdinalIgnoreCase);
        void FromUninstall(RegistryKey root, string path, string kind)
        {
            using var k = root.OpenSubKey(path);
            if (k == null) return;
            foreach (var sub in k.GetSubKeyNames())
            {
                using var s = k.OpenSubKey(sub);
                var name = s?.GetValue("DisplayName") as string;
                if (string.IsNullOrWhiteSpace(name) || s!.GetValue("SystemComponent") is int sc && sc == 1) continue;
                var loc = s.GetValue("InstallLocation") as string;
                if (string.IsNullOrWhiteSpace(loc) && s.GetValue("DisplayIcon") is string icon && icon.Length > 3)
                    try { loc = Path.GetDirectoryName(Environment.ExpandEnvironmentVariables(icon.Split(',')[0].Trim().Trim('"'))); } catch { }
                all[$"{kind}:{sub}"] = new NewApp($"{kind}:{sub}", kind, name, kind == "user", s.GetValue("QuietUninstallString") as string ?? s.GetValue("UninstallString") as string,
                    loc, s.GetValue("Publisher") as string);
            }
        }
        FromUninstall(Registry.CurrentUser, Uninstall, "user");
        FromUninstall(Registry.LocalMachine, Uninstall, "machine");
        FromUninstall(Registry.LocalMachine, @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "machine");
        if (Directory.Exists(StartMenu))
            foreach (var e in Directory.EnumerateFileSystemEntries(StartMenu))
            {
                var n = Path.GetFileName(e);
                if (n.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) || n is "Startup" or "Windows PowerShell" or "System Tools" or "Accessibility" or "Administrative Tools" or "Maintenance") continue;
                all[$"start:{n}"] = new NewApp($"start:{n}", "start", Path.GetFileNameWithoutExtension(n), true, null);
            }
        // v0.5: top-level keys under HKCU\Software (where programs keep their settings and recent files)
        using (var sw = Registry.CurrentUser.OpenSubKey("Software"))
            foreach (var n in sw?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                if (RegNew.Skip(n)) continue;
                string name = n; string? loc = null;
                // v0.8.1: a key named only by a GUID: its name and program folder come from its own values
                if (NewApps.IsGuid(n))
                    try
                    {
                        using var g = sw!.OpenSubKey(n);
                        loc = g?.GetValue("InstallLocation") as string;
                        name = NewApps.RegName(n, g?.GetValue("ShortcutName") as string, g?.GetValue("DisplayName") as string, loc);
                    }
                    catch { }
                all[$"reg:{n}"] = new NewApp($"reg:{n}", "reg", name, true, null, loc);
            }
        using (var run = Registry.CurrentUser.OpenSubKey(RunKey))
            foreach (var v in run?.GetValueNames() ?? Array.Empty<string>())
                all[$"run:{v}"] = new NewApp($"run:{v}", "run", v, true, null);
        if (withStore)
            try
            {
                var pm = new Windows.Management.Deployment.PackageManager();
                foreach (var p in pm.FindPackagesForUser(string.Empty))
                {
                    if (p.IsFramework || p.IsResourcePackage) continue;
                    var fam = p.Id.FamilyName;
                    string name; try { name = p.DisplayName; } catch { name = p.Id.Name; }
                    bool auto = p.SignatureKind is Windows.ApplicationModel.PackageSignatureKind.Store or Windows.ApplicationModel.PackageSignatureKind.Developer
                                && !SystemPrefixes.Any(x => fam.StartsWith(x, StringComparison.OrdinalIgnoreCase));
                    all[$"appx:{fam}"] = new NewApp($"appx:{fam}", "appx", string.IsNullOrWhiteSpace(name) ? p.Id.Name : name, auto, p.Id.FullName);
                }
            }
            catch (Exception e) { AppInfo.Trace($"store app list failed: {e.GetType().Name}"); }
        // Amnesia itself is always kept
        foreach (var k in all.Where(a => a.Value.Name.Contains("Amnesia", StringComparison.OrdinalIgnoreCase) || a.Key.Equals("run:Amnesia", StringComparison.OrdinalIgnoreCase)).Select(a => a.Key).ToList())
            all.Remove(k);
        return all;
    }

    static HashSet<string> Baseline()
    {
        if (!HasBaseline) return new(StringComparer.OrdinalIgnoreCase);
        var b = System.IO.File.ReadAllLines(File).Where(l => l.Length > 0).ToHashSet(StringComparer.OrdinalIgnoreCase);
        // a list from v0.4 has no registry lines yet: write down today's keys first, so nothing old looks "new"
        if (!b.Contains(RegMark))
        {
            b.Add(RegMark);
            foreach (var k in Current(withStore: false).Keys.Where(k => k.StartsWith("reg:"))) b.Add(k);
            try { System.IO.File.WriteAllLines(File, b.OrderBy(k => k)); } catch { }
        }
        return b;
    }
    const string RegMark = "reg:*listed"; // "registry keys are on this list" (v0.5)

    /// <summary>Writes down what is installed now (Turn On, switching the feature on).</summary>
    public static void TakeBaseline()
    {
        Directory.CreateDirectory(Core.Home.Dir);
        System.IO.File.WriteAllLines(File, Current(withStore: true).Keys.Append(RegMark).OrderBy(k => k));
        AppInfo.Trace("app list written down");
    }

    /// <summary>Programs that are not on the list (the Advanced page and the preview show these). v0.8.1: an app that
    /// was only updated (same name, other version) is not new.</summary>
    public static List<NewApp> New() => NewIn(Current(withStore: true));

    static List<NewApp> NewIn(Dictionary<string, NewApp> current)
    {
        if (!HasBaseline) return new List<NewApp>();
        var base_ = Baseline();
        var stems = NewApps.Stems(base_);
        return current.Values.Where(a => NewApps.IsNew(a.Id, base_, stems)).OrderBy(a => a.Kind).ThenBy(a => a.Name).ToList();
    }

    /// <summary>v0.8.1: the new programs, one line per app (Start menu shortcut, uninstall entry and registry key together).</summary>
    public static List<NewAppGroup> NewGroups()
    {
        var list = New();
        var byId = list.ToDictionary(a => a.Id, StringComparer.OrdinalIgnoreCase);
        return NewApps.Group(list.Select(a => new AppRow(a.Id, a.Kind, a.Name, a.Location)))
            .Select(g => new NewAppGroup(NewApps.GroupName(g), g.Select(r => byId[r.Id]).OrderBy(a => KindOrder(a.Kind)).ToList()))
            .OrderBy(g => g.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    static int KindOrder(string kind) => kind switch { "user" => 0, "machine" => 1, "appx" => 2, "start" => 3, "run" => 4, _ => 5 };

    /// <summary>"Keep" next to a new program: it joins the list and is never removed. v0.8.1: ids = every row of the app
    /// (one line on the page), and its program folder and data folders go on the Keep List so the cleanup leaves them.</summary>
    public static void Keep(IEnumerable<string> ids) => KeepMany(ids, "keep");

    /// <summary>"Keep all of these": every new program, with its folders (v0.8.1: before, only the list was written again).</summary>
    public static void KeepAll() => KeepMany(null, "keep all");

    static void KeepMany(IEnumerable<string>? ids, string why)
    {
        var b = Baseline();
        var current = Current(withStore: true);
        var news = NewIn(current);
        var chosen = ids == null ? news : ids.Select(i => current.GetValueOrDefault(i)).Where(a => a != null).Select(a => a!).ToList();
        // the rest of the app's rows (same group) and, as before, its Start menu shortcut, autostart entry and settings
        var groups = NewApps.Group(news.Select(a => new AppRow(a.Id, a.Kind, a.Name, a.Location)));
        var all = new List<NewApp>(chosen);
        foreach (var app in chosen)
        {
            foreach (var g in groups.Where(g => g.Any(r => r.Id.Equals(app.Id, StringComparison.OrdinalIgnoreCase))))
                foreach (var r in g) if (current.TryGetValue(r.Id, out var o) && !all.Contains(o)) all.Add(o);
            foreach (var other in current.Values.Where(o => o.Kind is "start" or "run" or "reg" && !b.Contains(o.Id) && !all.Contains(o) && (Similar(o.Name, app.Name) || Similar(app.Name, o.Name))))
                all.Add(other);
        }
        foreach (var a in all) b.Add(a.Id);
        if (ids == null) foreach (var k in current.Keys) b.Add(k);
        System.IO.File.WriteAllLines(File, b.OrderBy(k => k));
        // the folders, so the next cleanup does not break the app
        int folders = 0, apps = 0;
        try
        {
            var cands = AppCatalog.Candidates();
            foreach (var g in NewApps.Group(all.Select(a => new AppRow(a.Id, a.Kind, a.Name, a.Location))))
            {
                var rows = g.Select(r => all.First(a => a.Id == r.Id)).ToList();
                var name = NewApps.GroupName(g);
                var pub = rows.Select(a => a.Publisher).FirstOrDefault(p => !string.IsNullOrEmpty(p));
                foreach (var p in NewApps.KeepPaths(name, pub, rows.Select(a => a.Location), cands, Core.Home.User))
                    if (KeepList.Add(p) != null) folders++;
                apps++;
            }
        }
        catch (Exception e) { AppInfo.Trace($"keep new app: folders not added ({e.GetType().Name})"); }
        AppInfo.Trace(why == "keep all" ? $"keep all: {apps} new app(s) kept, {folders} folder(s) added to the Keep List" : $"kept new app: {folders} folder(s) added to the Keep List");
        Core.Home.History("appkeep", $"{apps} {folders}");
    }

    /// <summary>v0.8.1: program folders of the new apps (just for you, inside the user folder). The cleanup moves them to
    /// the trash for 3 days instead of the normal trash (it took them before "Remove new apps" could). Registry only.</summary>
    public static List<string> NewFolders()
    {
        if (!On || !HasBaseline) return new List<string>();
        var home = Core.Home.User + "\\";
        return NewIn(Current(withStore: false)).Where(a => a.Kind is "user" or "reg" && a.Location is { Length: > 3 })
            .Select(a => a.Location!.Trim().Trim('"').TrimEnd('\\'))
            .Where(l => l.StartsWith(home, StringComparison.OrdinalIgnoreCase) && !l.Contains(@"\Programs\Amnesia", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    static bool Similar(string a, string b)
    {
        var w = a.Split(' ', '-', '_', '.')[0];
        return w.Length >= 3 && b.Contains(w, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Called by the cleanup after the user folder is done. Fast registry/file work at sign out; Store apps at sign in.</summary>
    public static void RemoveNew(string mode)
    {
        if (!On || !HasBaseline || Core.Home.Test) return;
        var rules = Cleaner.Rules();
        int n = 0;
        foreach (var a in NewIn(Current(withStore: mode != "logout")).Where(a => a.Auto))
        {
            try
            {
                var id = a.Id[(a.Kind.Length + 1)..];
                switch (a.Kind)
                {
                    case "user":
                        using (var k = Registry.CurrentUser.OpenSubKey($@"{Uninstall}\{id}"))
                        {
                            var loc = k?.GetValue("InstallLocation") as string;
                            var home = Core.Home.User;
                            // v0.8: only an app's own folder in AppData that is not on the Keep List and holds nothing kept,
                            // and it goes to the Amnesia trash for 3 days instead of being deleted (T7: a Keep folder was lost)
                            if (!string.IsNullOrEmpty(loc) && loc.StartsWith(home + "\\", StringComparison.OrdinalIgnoreCase) && Directory.Exists(loc)
                                && !loc.Contains(@"\Programs\Amnesia", StringComparison.OrdinalIgnoreCase))
                            {
                                // v0.8.1: no app names in trace.log
                                if (rules.MayRemoveAppFolder(loc.TrimEnd('\\')))
                                    AppInfo.Trace(CleanEngine.ToTrash(loc.TrimEnd('\\')) ? "remove new app: folder moved to the trash (3 days)" : "remove new app: folder could not be moved, left alone");
                                else AppInfo.Trace("remove new app: folder left alone (kept or shared)");
                            }
                        }
                        Registry.CurrentUser.DeleteSubKeyTree($@"{Uninstall}\{id}", false);
                        break;
                    case "start":
                        CleanEngine.ToTrash(Path.Combine(StartMenu, id));
                        break;
                    case "run":
                        using (var r = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)) r?.DeleteValue(id, false);
                        break;
                    case "reg":
                        if (!RegNew.Skip(id)) Registry.CurrentUser.DeleteSubKeyTree($@"Software\{id}", false);
                        break;
                    case "appx":
                        var op = new Windows.Management.Deployment.PackageManager().RemovePackageAsync(a.Uninstall!);
                        var t = System.WindowsRuntimeSystemExtensions.AsTask(op);
                        if (!t.Wait(TimeSpan.FromSeconds(60))) throw new TimeoutException();
                        break;
                }
                n++;
            }
            catch (Exception e) { AppInfo.Trace($"remove new app ({a.Kind}) failed: {e.GetType().Name}"); }
        }
        if (n > 0) { Core.Home.History("apps", $"{mode} {n}"); AppInfo.Trace($"removed {n} new app item(s)"); }
    }

    /// <summary>Uninstall button for a program installed for everyone: runs its own uninstaller (Windows asks for admin).</summary>
    /// <summary>Starts the program's own uninstaller and waits until it is done (v0.7.1: so the list can be loaded again).
    /// Many uninstallers start a copy of themselves in Temp and quit at once, so after that Amnesia also waits (at most
    /// 3 minutes) until the program is gone from the list. Written to trace.log (steps only, no program names).</summary>
    public static void RunUninstaller(string id)
    {
        var app = Current(withStore: false).GetValueOrDefault(id) ?? throw new InvalidOperationException("not found");
        var cmd = app.Uninstall?.Trim() ?? throw new InvalidOperationException("no uninstaller");
        // v0.5 (from Bulk Crap Uninstaller): MSI installs are removed (/X) instead of "repaired" (/I)
        var (exe, args) = UninstallCmd.Parse(cmd, quiet: false);
        var t = System.Diagnostics.Stopwatch.StartNew();
        AppInfo.Trace($"uninstaller started ({app.Kind})");
        using var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe, args) { UseShellExecute = true });
        try { p?.WaitForExit((int)TimeSpan.FromMinutes(30).TotalMilliseconds); } catch { }
        bool gone = false;
        for (var until = DateTime.Now.AddMinutes(3); DateTime.Now < until; Thread.Sleep(2000))
            if (gone = !Current(withStore: false).ContainsKey(id)) break;
        int? code = null; try { if (p is { HasExited: true }) code = p.ExitCode; } catch { }
        AppInfo.Trace($"uninstaller finished in {t.Elapsed.TotalSeconds:0} s (exit code {code?.ToString() ?? "?"}, {(gone ? "program gone" : "program still listed")})");
    }

    // ---------- v0.5 Find leftovers ----------
    /// <summary>Folders below these are checked. Program Files and ProgramData need admin to delete.</summary>
    public static string[] LeftoverRoots()
    {
        var list = new List<string>
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        };
        return list.Where(r => r.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    /// <summary>Names, publishers and folders of everything installed (what counts as "still used").</summary>
    static (List<string> names, List<string> locations) InstalledInfo()
    {
        var names = new List<string>(); var locs = new List<string>();
        void Read(RegistryKey root, string path)
        {
            using var k = root.OpenSubKey(path);
            foreach (var sub in k?.GetSubKeyNames() ?? Array.Empty<string>())
            {
                using var s = k!.OpenSubKey(sub);
                if (s == null) continue;
                foreach (var v in new[] { "DisplayName", "Publisher" }) if (s.GetValue(v) is string t) names.Add(t);
                if (s.GetValue("InstallLocation") is string l && l.Length > 3) locs.Add(l);
                if (s.GetValue("DisplayIcon") is string ic && ic.Length > 3) { var d = Path.GetDirectoryName(ic.Split(',')[0].Trim('"')); if (!string.IsNullOrEmpty(d)) locs.Add(d); }
                names.Add(sub);
            }
        }
        Read(Registry.CurrentUser, Uninstall);
        Read(Registry.LocalMachine, Uninstall);
        Read(Registry.LocalMachine, @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall");
        try
        {
            foreach (var p in new Windows.Management.Deployment.PackageManager().FindPackagesForUser(string.Empty))
            {
                names.Add(p.Id.Name);
                try { names.Add(p.PublisherDisplayName); } catch { }
            }
        }
        catch { }
        // services and drivers also live in Program Files / ProgramData
        using (var svc = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services"))
            foreach (var n in svc?.GetSubKeyNames() ?? Array.Empty<string>()) names.Add(n);
        return (names, locs);
    }

    /// <summary>Folders and HKCU\Software keys that no installed program uses. Nothing is deleted here.</summary>
    public static (List<Leftover> folders, List<string> keys) FindLeftovers()
    {
        var (names, locs) = InstalledInfo();
        var folders = Leftovers.Folders(LeftoverRoots(), names, locs);
        var norm = names.Select(Leftovers.Norm).Where(n => n.Length >= 3).Distinct().ToList();
        var keys = new List<string>();
        using (var sw = Registry.CurrentUser.OpenSubKey("Software"))
            foreach (var n in sw?.GetSubKeyNames() ?? Array.Empty<string>())
                if (!RegNew.Skip(n) && !Leftovers.Used(n, norm)) keys.Add(n);
        return (folders, keys);
    }

    /// <summary>Deletes chosen leftovers: registry keys right away, folders with admin rights (Windows asks once).</summary>
    public static bool DeleteLeftovers(IEnumerable<string> folders, IEnumerable<string> keys)
    {
        foreach (var k in keys.Where(k => !RegNew.Skip(k) && !k.Contains('\\')))
            try { Registry.CurrentUser.DeleteSubKeyTree($@"Software\{k}", false); } catch { }
        var roots = LeftoverRoots();
        var list = folders.Where(f => Leftovers.Allowed(f, roots)).ToList();
        if (list.Count == 0) return true;
        var file = Path.Combine(Core.Home.Dir, "leftovers-delete.txt");
        System.IO.File.WriteAllLines(file, list);
        try { return AdminTasks.Run($"leftovers={file}"); }
        finally { try { System.IO.File.Delete(file); } catch { } }
    }
}
