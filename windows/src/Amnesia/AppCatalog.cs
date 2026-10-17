// v0.8: the programs on this PC with their name, icon and the AppData folders they keep their data in. Used by the
// Keep List (rows show "Discord" with its icon, not only a path) and by "Keep an app...". Only reads; nothing changes.
using System.Drawing;
using System.Drawing.Imaging;
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

sealed record CatalogApp(string Name, string? Icon, List<string> Paths, bool Store);

static class AppCatalog
{
    static List<CatalogApp>? cache;
    static DateTime cachedAt;
    static readonly Dictionary<string, string?> icons = new(StringComparer.OrdinalIgnoreCase);

    public static List<CatalogApp> Get()
    {
        lock (icons)
        {
            if (cache != null && DateTime.UtcNow - cachedAt < TimeSpan.FromMinutes(2)) return cache;
            var cands = Candidates();
            var list = new List<CatalogApp>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var (name, pub, dir, icon) in Programs())
            {
                if (!seen.Add(name) || name.Contains("Amnesia", StringComparison.OrdinalIgnoreCase)) continue;
                var paths = AppMatch.Folders(name, pub, dir, cands);
                if (paths.Count > 0) list.Add(new CatalogApp(name, Icon(icon), paths, false));
            }
            foreach (var s in StoreApps())
                if (seen.Add(s.Name)) list.Add(s);
            cache = list.OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase).ToList();
            cachedAt = DateTime.UtcNow;
            return cache;
        }
    }

    /// <summary>The app a Keep List line belongs to (or null: then the page shows a folder).</summary>
    public static CatalogApp? For(string path)
    {
        var p = KeepList.Norm(path);
        return Get().FirstOrDefault(a => a.Paths.Any(x => x.Equals(p, StringComparison.OrdinalIgnoreCase) || p.StartsWith(x + "/", StringComparison.OrdinalIgnoreCase)));
    }

    static List<string> Candidates()
    {
        var list = new List<string>();
        foreach (var root in new[] { "AppData/Roaming", "AppData/Local", "AppData/LocalLow" })
        {
            var dir = Core.Home.Full(root);
            if (!Directory.Exists(dir)) continue;
            foreach (var d in Safe(() => new DirectoryInfo(dir).EnumerateDirectories().ToList()))
            {
                if (d.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                list.Add($"{root}/{d.Name}");
                foreach (var s in Safe(() => d.EnumerateDirectories().Take(40).ToList()))
                    if (!s.Attributes.HasFlag(FileAttributes.ReparsePoint)) list.Add($"{root}/{d.Name}/{s.Name}");
            }
        }
        return list;
    }

    static List<T> Safe<T>(Func<List<T>> f) { try { return f(); } catch { return new List<T>(); } }

    const string Uninstall = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";

    static IEnumerable<(string name, string? pub, string? dir, string? icon)> Programs()
    {
        var all = new List<(string, string?, string?, string?)>();
        void Read(RegistryKey root, string path)
        {
            try
            {
                using var k = root.OpenSubKey(path);
                foreach (var sub in k?.GetSubKeyNames() ?? Array.Empty<string>())
                {
                    using var s = k!.OpenSubKey(sub);
                    if (s?.GetValue("DisplayName") is not string n || n.Length < 2) continue;
                    if (s.GetValue("SystemComponent") is int sc && sc == 1 || s.GetValue("ParentKeyName") != null) continue;
                    var icon = s.GetValue("DisplayIcon") as string;
                    var dir = s.GetValue("InstallLocation") as string;
                    if (string.IsNullOrEmpty(dir) && icon is { Length: > 3 }) dir = Path.GetDirectoryName(icon.Split(',')[0].Trim('"'));
                    all.Add((n, s.GetValue("Publisher") as string, dir, icon));
                }
            }
            catch { }
        }
        Read(Registry.CurrentUser, Uninstall);
        Read(Registry.LocalMachine, Uninstall);
        Read(Registry.LocalMachine, @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall");
        return all;
    }

    static IEnumerable<CatalogApp> StoreApps()
    {
        var list = new List<CatalogApp>();
        try
        {
            var pk = Core.Home.Full("AppData/Local/Packages");
            foreach (var p in new Windows.Management.Deployment.PackageManager().FindPackagesForUser(string.Empty))
            {
                if (p.IsFramework || p.IsResourcePackage || p.SignatureKind == Windows.ApplicationModel.PackageSignatureKind.System) continue;
                var fam = p.Id.FamilyName;
                if (CleanEngine.StoreSystem(fam) || !Directory.Exists(Path.Combine(pk, fam))) continue;
                string name; try { name = p.DisplayName; } catch { name = p.Id.Name; }
                if (string.IsNullOrWhiteSpace(name) || name.StartsWith("ms-resource:")) name = p.Id.Name;
                string? logo = null; try { logo = p.Logo?.LocalPath; } catch { }
                list.Add(new CatalogApp(name, Icon(logo, store: true), new List<string> { $"AppData/Local/Packages/{fam}" }, true));
            }
        }
        catch (Exception e) { AppInfo.Trace($"store app icons failed: {e.GetType().Name}"); }
        return list;
    }

    /// <summary>A small PNG (as a data: link the page can show) from a program's icon or a Store app's logo.</summary>
    static string? Icon(string? spec, bool store = false)
    {
        if (string.IsNullOrWhiteSpace(spec)) return null;
        if (icons.TryGetValue(spec, out var have)) return have;
        string? url = null;
        try
        {
            var file = spec.Split(',')[0].Trim().Trim('"');
            file = Environment.ExpandEnvironmentVariables(file);
            if (store && !File.Exists(file)) file = StoreLogo(file) ?? file;
            if (File.Exists(file))
            {
                using Image src = store || file.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? Image.FromFile(file)
                    : file.EndsWith(".ico", StringComparison.OrdinalIgnoreCase) ? new Icon(file, 32, 32).ToBitmap()
                    : (System.Drawing.Icon.ExtractAssociatedIcon(file) ?? throw new FileNotFoundException()).ToBitmap();
                using var bmp = new Bitmap(32, 32);
                using (var g = Graphics.FromImage(bmp))
                {
                    g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    g.DrawImage(src, 0, 0, 32, 32);
                }
                using var ms = new MemoryStream();
                bmp.Save(ms, ImageFormat.Png);
                url = "data:image/png;base64," + Convert.ToBase64String(ms.ToArray());
            }
        }
        catch { }
        icons[spec] = url;
        return url;
    }

    // Store logos are saved as StoreLogo.scale-100.png, StoreLogo.targetsize-32.png... next to the name in the manifest
    static string? StoreLogo(string file)
    {
        var dir = Path.GetDirectoryName(file);
        if (dir == null || !Directory.Exists(dir)) return null;
        var stem = Path.GetFileNameWithoutExtension(file);
        return Directory.EnumerateFiles(dir, stem + ".*" + Path.GetExtension(file))
            .OrderBy(f => f.Contains("targetsize-32") ? 0 : f.Contains("scale-100") ? 1 : 2).FirstOrDefault();
    }
}
