// v0.4 "Remove new apps" (Settings → Advanced, off unless you switch it on). Same idea as the Mac:
// at Turn On Amnesia writes down the programs that are installed (apps-baseline.txt). At sign out, programs installed
// "just for you" after that are removed, unless you pressed Keep (then they join the list).
//   - just for you (AppData\Local\Programs, Discord, VS Code user setup...): their files already go with the cleanup;
//     Amnesia also removes their entry in Apps & features, their Start menu shortcut and their "start with Windows" entry.
//   - Microsoft Store apps you installed: removed at the next sign in check (Windows' own app manager, no admin).
//   - for everyone (Program Files): need admin, so they are only listed, with an Uninstall button (Windows asks first).
//   - v0.5: settings new programs wrote in your part of the registry (HKCU\Software\<name>) go too (idea from Pearcleaner
//     and Bulk Crap Uninstaller). "Find leftovers" lists folders that uninstallers left behind.
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

sealed record NewApp(string Id, string Kind, string Name, bool Auto, string? Uninstall);

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
                all[$"{kind}:{sub}"] = new NewApp($"{kind}:{sub}", kind, name, kind == "user", s.GetValue("QuietUninstallString") as string ?? s.GetValue("UninstallString") as string);
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
                if (!RegNew.Skip(n)) all[$"reg:{n}"] = new NewApp($"reg:{n}", "reg", n, true, null);
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

    /// <summary>Writes down what is installed now (Turn On, switching the feature on, "Keep all").</summary>
    public static void TakeBaseline()
    {
        Directory.CreateDirectory(Core.Home.Dir);
        System.IO.File.WriteAllLines(File, Current(withStore: true).Keys.Append(RegMark).OrderBy(k => k));
        AppInfo.Trace("app list written down");
    }

    /// <summary>Programs that are not on the list (the Advanced page and the preview show these).</summary>
    public static List<NewApp> New()
    {
        if (!HasBaseline) return new List<NewApp>();
        var base_ = Baseline();
        return Current(withStore: true).Values.Where(a => !base_.Contains(a.Id)).OrderBy(a => a.Kind).ThenBy(a => a.Name).ToList();
    }

    /// <summary>"Keep" next to a new program: it joins the list and is never removed.</summary>
    public static void Keep(string id)
    {
        var b = Baseline();
        b.Add(id);
        // keeping a program keeps its Start menu shortcut and autostart entry too
        var app = Current(withStore: false).GetValueOrDefault(id);
        if (app != null)
            foreach (var other in Current(withStore: false).Values.Where(o => o.Kind is "start" or "run" or "reg" && !b.Contains(o.Id) && (Similar(o.Name, app.Name) || Similar(app.Name, o.Name))))
                b.Add(other.Id);
        System.IO.File.WriteAllLines(File, b.OrderBy(k => k));
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
        var base_ = Baseline();
        int n = 0;
        foreach (var a in Current(withStore: mode != "logout").Values.Where(a => a.Auto && !base_.Contains(a.Id)))
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
                            // files inside your user folder only (the cleanup already moved most of them)
                            if (!string.IsNullOrEmpty(loc) && loc.StartsWith(home + "\\", StringComparison.OrdinalIgnoreCase) && Directory.Exists(loc)
                                && !loc.Contains(@"\Programs\Amnesia", StringComparison.OrdinalIgnoreCase))
                                CleanEngine.Delete(loc);
                        }
                        Registry.CurrentUser.DeleteSubKeyTree($@"{Uninstall}\{id}", false);
                        break;
                    case "start":
                        CleanEngine.Delete(Path.Combine(StartMenu, id));
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
    public static void RunUninstaller(string id)
    {
        var app = Current(withStore: false).GetValueOrDefault(id) ?? throw new InvalidOperationException("not found");
        var cmd = app.Uninstall?.Trim() ?? throw new InvalidOperationException("no uninstaller");
        // v0.5 (from Bulk Crap Uninstaller): MSI installs are removed (/X) instead of "repaired" (/I)
        var (exe, args) = UninstallCmd.Parse(cmd, quiet: false);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe, args) { UseShellExecute = true });
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
