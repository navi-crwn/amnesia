// v0.5 "Extra cleaning list" (Settings → Advanced, off unless you switch it on). Winapp2.ini is a big community list of
// where ~4,000 Windows apps leave traces (https://github.com/MoscaDotTo/Winapp2, CC BY-SA 4.0; BleachBit uses it too).
// Amnesia does NOT ship the list: the button downloads it to .amnesia\winapp2.ini, so the list keeps its own license.
//
// Amnesia already wipes almost your whole user folder, so only two kinds of lines matter here:
//   - files in the folders that stay on purpose (AppData\Local\Microsoft, AppData\Roaming\Microsoft, AppData\Local\Packages)
//   - registry lines under HKCU\Software (your part of the registry stays, so app history there would stay too)
// Everything else (Program Files, ProgramData, Windows, other users) is skipped. Entries with a Warning= are skipped.
namespace Amnesia.Core;

public sealed class W2Entry
{
    public string Name = "";
    public bool Warning;
    public List<string> Detect = new(), DetectFile = new(), FileKeys = new(), RegKeys = new(), Excludes = new();
}

/// <summary>What the list would clean on this PC: files/folders (full paths) and registry keys or values.</summary>
public sealed record W2Plan(List<string> Files, List<(string Key, string? Value)> Reg, int Entries);

public static class Winapp2
{
    public static string FilePath => Path.Combine(Home.Dir, "winapp2.ini");
    public const string Url = "https://raw.githubusercontent.com/MoscaDotTo/Winapp2/master/Winapp2.ini";

    public static bool On => Conf.On("EXTRA_LIST");
    public static bool Exists => File.Exists(FilePath);

    /// <summary>"; Version: 260915" from the top of the file, or null.</summary>
    public static string? Version(string? text = null)
    {
        try
        {
            foreach (var l in (text ?? File.ReadAllText(FilePath)).Split('\n').Take(5))
                if (l.StartsWith("; Version:", StringComparison.OrdinalIgnoreCase)) return l[10..].Trim();
        }
        catch { }
        return null;
    }

    /// <summary>A real Winapp2.ini? (checked before a download replaces the old one)</summary>
    public static bool LooksValid(string text) => text.Length > 100_000 && Version(text) != null && Parse(text).Count > 500;

    public static List<W2Entry> Parse(string text)
    {
        var list = new List<W2Entry>();
        W2Entry? cur = null;
        foreach (var raw in text.Split('\n'))
        {
            var l = raw.Trim();
            if (l.Length == 0 || l[0] == ';') continue;
            if (l[0] == '[' && l[^1] == ']') { cur = new W2Entry { Name = l[1..^1].TrimEnd(' ', '*').Trim() }; list.Add(cur); continue; }
            if (cur == null) continue;
            int eq = l.IndexOf('=');
            if (eq <= 0) continue;
            var key = l[..eq].TrimEnd('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
            var val = l[(eq + 1)..].Trim();
            switch (key.ToLowerInvariant())
            {
                case "detect": cur.Detect.Add(val); break;
                case "detectfile": cur.DetectFile.Add(val); break;
                case "filekey": cur.FileKeys.Add(val); break;
                case "regkey": cur.RegKeys.Add(val); break;
                case "excludekey": cur.Excludes.Add(val); break;
                case "warning": cur.Warning = true; break;
            }
        }
        return list;
    }

    // registry parts that are never touched, whatever a list says
    static readonly string[] RegNever =
    {
        @"HKCU\Software\Classes", @"HKCU\Software\Policies", @"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
        @"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders", @"HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders",
        @"HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon", @"HKCU\Software\Microsoft\SystemCertificates",
        @"HKCU\Software\Microsoft\Cryptography", @"HKCU\Software\Microsoft\Protected Storage System Provider", @"HKCU\Software\Amnesia",
    };

    public static bool RegAllowed(string key)
    {
        key = key.TrimEnd('\\');
        if (!key.StartsWith(@"HKCU\Software\", StringComparison.OrdinalIgnoreCase)) return false;
        if (key.Count(c => c == '\\') < 2) return false; // never all of HKCU\Software
        return !RegNever.Any(n => key.Equals(n, StringComparison.OrdinalIgnoreCase) || key.StartsWith(n + "\\", StringComparison.OrdinalIgnoreCase)
                                  || n.StartsWith(key + "\\", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    /// Works out what the list would clean. env turns "%LocalAppData%" into a folder (null = unknown, skipped),
    /// regExists answers Detect= lines, allowFile decides which files may go (the cleanup's own safety rules).
    /// Stops after about 3 seconds or maxItems, so a sign out is never held up by it.
    /// </summary>
    public static W2Plan Plan(IEnumerable<W2Entry> entries, Func<string, string?> env, Func<string, bool> regExists, Func<string, bool> allowFile, int maxItems = 20_000)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var files = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var reg = new List<(string, string?)>();
        int used = 0;
        foreach (var e in entries)
        {
            if (watch.Elapsed.TotalSeconds > 3 || files.Count + reg.Count > maxItems) break;
            if (e.Warning) continue;
            bool hasRegWork = e.RegKeys.Any(r => RegAllowed(r.Split('|')[0]));
            bool hasFileWork = e.FileKeys.Any(f => ZoneLike(f, env));
            if (!hasRegWork && !hasFileWork) continue; // nothing here for Amnesia
            if (e.Detect.Count + e.DetectFile.Count > 0 &&
                !e.Detect.Any(d => Safe(() => regExists(d))) && !e.DetectFile.Any(d => Dirs(d, env).Any() || FileExists(d, env))) continue;
            int before = files.Count + reg.Count;
            var excl = e.Excludes.Select(x => ParseExclude(x, env)).Where(x => x != null).Select(x => x!).ToList();
            foreach (var fk in e.FileKeys)
            {
                var parts = fk.Split('|');
                if (parts.Length < 2) continue;
                var flag = parts.Length > 2 ? parts[2].Trim().ToUpperInvariant() : "";
                var pats = parts[1].Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                foreach (var dir in Dirs(parts[0], env))
                {
                    if (flag == "REMOVESELF" && pats.All(p => p == "*" || p == "*.*"))
                    {
                        if (allowFile(dir) && !Excluded(dir, excl, true) && seen.Add(dir)) files.Add(dir);
                        continue;
                    }
                    var opt = new EnumerationOptions { RecurseSubdirectories = flag is "RECURSE" or "REMOVESELF", AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = true, MatchCasing = MatchCasing.CaseInsensitive };
                    foreach (var pat in pats)
                    {
                        IEnumerable<string> found;
                        try { found = Directory.EnumerateFiles(dir, pat, opt).Take(5000).ToList(); } catch { continue; }
                        foreach (var f in found)
                            if (allowFile(f) && !Excluded(f, excl, false) && seen.Add(f)) files.Add(f);
                    }
                }
            }
            foreach (var rk in e.RegKeys)
            {
                var parts = rk.Split('|');
                var key = parts[0].TrimEnd('\\');
                if (!RegAllowed(key)) continue;
                reg.Add((key, parts.Length > 1 && parts[1].Length > 0 ? parts[1] : null));
            }
            if (files.Count + reg.Count > before) used++;
        }
        return new W2Plan(files, reg, used);
    }

    static bool Safe(Func<bool> f) { try { return f(); } catch { return false; } }

    // only lines that start in the user folder can matter (a quick look before the slower checks)
    static bool ZoneLike(string fileKey, Func<string, string?> env)
    {
        var p = fileKey.Split('|')[0];
        return p.StartsWith("%LocalAppData%", StringComparison.OrdinalIgnoreCase) || p.StartsWith("%AppData%", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("%UserProfile%\\AppData", StringComparison.OrdinalIgnoreCase);
    }

    static string? Expand(string path, Func<string, string?> env)
    {
        path = path.Trim();
        if (!path.StartsWith('%')) return null; // only %Folder%\... lines
        int end = path.IndexOf('%', 1);
        if (end < 0) return null;
        var root = env(path[1..end]);
        if (string.IsNullOrEmpty(root)) return null;
        var rest = path[(end + 1)..].TrimStart('\\', '/');
        return rest.Length == 0 ? root : Path.Combine(root, rest.Replace('\\', Path.DirectorySeparatorChar));
    }

    static bool FileExists(string path, Func<string, string?> env)
    {
        var p = Expand(path, env);
        return p != null && !p.Contains('*') && File.Exists(p);
    }

    /// <summary>Folders that match a path with %Folder% and * in it. Links/junctions are never followed.</summary>
    static IEnumerable<string> Dirs(string path, Func<string, string?> env)
    {
        var full = Expand(path, env);
        if (full == null) return Array.Empty<string>();
        var sep = Path.DirectorySeparatorChar;
        var parts = full.Split(sep);
        int firstWild = Array.FindIndex(parts, p => p.Contains('*') || p.Contains('?'));
        if (firstWild < 0) return Directory.Exists(full) && !IsLink(full) ? new[] { full } : Array.Empty<string>();
        IEnumerable<string> found = new[] { string.Join(sep, parts[..firstWild]) };
        if (found.First().Length == 0) found = new[] { sep.ToString() };
        foreach (var part in parts[firstWild..])
        {
            found = found.SelectMany(f =>
            {
                if (!part.Contains('*') && !part.Contains('?')) { var p = Path.Combine(f, part); return Directory.Exists(p) && !IsLink(p) ? new[] { p } : Array.Empty<string>(); }
                try { return new DirectoryInfo(f).EnumerateDirectories(part).Where(d => !d.Attributes.HasFlag(FileAttributes.ReparsePoint)).Select(d => d.FullName).Take(200).ToArray(); }
                catch { return Array.Empty<string>(); }
            }).ToList();
        }
        return found;
    }

    static bool IsLink(string p) { try { return new DirectoryInfo(p).Attributes.HasFlag(FileAttributes.ReparsePoint); } catch { return true; } }

    // ExcludeKey1=FILE|%AppData%\App\|keep.ini   or   PATH|%AppData%\App\Saves\|*
    sealed record Excl(bool IsPath, string Dir, string[] Pats);
    static Excl? ParseExclude(string x, Func<string, string?> env)
    {
        var p = x.Split('|');
        if (p.Length < 2) return null;
        var dir = Expand(p[1], env);
        if (dir == null) return null;
        var pats = p.Length > 2 ? p[2].Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries) : new[] { "*" };
        return new Excl(p[0].Equals("PATH", StringComparison.OrdinalIgnoreCase), dir.TrimEnd(Path.DirectorySeparatorChar), pats);
    }

    static bool Excluded(string path, List<Excl> ex, bool isDir)
    {
        foreach (var e in ex)
        {
            var parent = Path.GetDirectoryName(path) ?? "";
            if (e.IsPath)
            {
                // anything below that folder; a folder that holds an excluded place is not removed whole
                if (Wild.Like(path, e.Dir + Path.DirectorySeparatorChar + "*") || Wild.Like(e.Dir, path + Path.DirectorySeparatorChar + "*") || Wild.Like(path, e.Dir)) return true;
            }
            else if (Wild.Like(parent, e.Dir) && e.Pats.Any(p => Wild.Like(Path.GetFileName(path), p))) return true;
            else if (isDir && Wild.Like(e.Dir, path + Path.DirectorySeparatorChar + "*")) return true;
        }
        return false;
    }
}
