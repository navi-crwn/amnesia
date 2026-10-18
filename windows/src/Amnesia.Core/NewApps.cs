// v0.8.1 "Remove new apps" list, the parts that need no registry (so they can be tested):
//   - one app showed as 3 rows (Start menu shortcut, uninstall entry "Antigravity 2.24.0", and a registry key named
//     only by a GUID). Rows of the same app are grouped (same program folder, or the same name without the version).
//   - a registry key named by a GUID gets a name from its own values (ShortcutName, DisplayName, InstallLocation).
//   - an app that was only updated ("Surfshark 6.13.0999" in the list, "Surfshark 6.20.0999" now) is not new.
//   - "Keep" on a new app also puts its program folder and its data folders on the Keep List, so it keeps working.
using System.Text.RegularExpressions;

namespace Amnesia.Core;

/// <summary>One row of the new apps list: id is "kind:key" ("user:...", "machine:...", "start:...", "reg:...").</summary>
public sealed record AppRow(string Id, string Kind, string Name, string? Location);

public static class NewApps
{
    static readonly Regex Guid_ = new(@"^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?(_is1)?$", RegexOptions.IgnoreCase);
    // "2.24.0", "v6.20", "6.20.0999", "1.0.0-beta"; also "(x64)", "x64", "64-bit", "(User)"
    static readonly Regex Version = new(@"^[vV]?\d+([._]\d+)+[a-z0-9\-]*$|^\d{3,}$", RegexOptions.IgnoreCase);
    static readonly HashSet<string> Noise = new(StringComparer.OrdinalIgnoreCase) { "x64", "x86", "arm64", "64-bit", "32-bit", "(x64)", "(x86)", "(arm64)", "(64-bit)", "(32-bit)", "(user)", "(machine)", "-", "–" };

    public static bool IsGuid(string name) => Guid_.IsMatch(name.Trim());

    /// <summary>The name without its version: "Surfshark 6.20.0999" → "Surfshark", "Antigravity 2.24.0" → "Antigravity".</summary>
    public static string BaseName(string name)
    {
        var words = name.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();
        while (words.Count > 1 && (Version.IsMatch(words[^1].Trim('(', ')')) || Noise.Contains(words[^1]))) words.RemoveAt(words.Count - 1);
        return string.Join(' ', words);
    }

    /// <summary>The kind and the key without its version: "machine:Surfshark 6.13.0999" → "machine:surfshark".</summary>
    public static string Stem(string id)
    {
        int c = id.IndexOf(':');
        if (c < 0) return Leftovers.Norm(BaseName(id));
        var kind = id[..c];
        var key = id[(c + 1)..];
        // a Start menu shortcut is "Name 1.2.lnk"
        if (kind == "start" && key.EndsWith(".lnk", StringComparison.OrdinalIgnoreCase)) key = key[..^4];
        return kind.ToLowerInvariant() + ":" + Leftovers.Norm(BaseName(key));
    }

    /// <summary>Is this id new compared to the list made at Turn On? Not when it is on the list, nor when only its
    /// version changed (the same kind with the same name without version is on the list).</summary>
    public static bool IsNew(string id, ICollection<string> baseline, ILookup<string, string>? stems = null)
    {
        if (baseline.Contains(id)) return false;
        var st = Stem(id);
        if (st.Length <= id.IndexOf(':') + 3) return true; // too short to compare by name
        stems ??= Stems(baseline);
        return !stems.Contains(st);
    }

    /// <summary>The baseline by stem, made once for many IsNew calls.</summary>
    public static ILookup<string, string> Stems(IEnumerable<string> baseline) => baseline.Where(b => b.Contains(':') && !b.EndsWith("*listed")).ToLookup(Stem);

    /// <summary>A name for a registry key that is only a GUID: from its ShortcutName, DisplayName or the last part of
    /// its InstallLocation. Other keys keep their own name.</summary>
    public static string RegName(string key, string? shortcut, string? display, string? location)
    {
        if (!IsGuid(key)) return key;
        if (!string.IsNullOrWhiteSpace(shortcut)) return shortcut.Trim();
        if (!string.IsNullOrWhiteSpace(display)) return display.Trim();
        var leaf = string.IsNullOrWhiteSpace(location) ? "" : Path.GetFileName(location.Trim().TrimEnd('\\', '/').Replace('\\', '/'));
        return leaf.Length > 0 ? leaf : key;
    }

    /// <summary>Groups rows that belong to the same app: the same program folder, or the same name without version, or one
    /// name that starts with the whole other one (at least 4 letters: "Discord" and "Discord PTB"). Never by a first word
    /// alone ("Microsoft Teams" and "Microsoft Edge" are two apps).</summary>
    public static List<List<AppRow>> Group(IEnumerable<AppRow> rows)
    {
        var list = rows.ToList();
        var parent = Enumerable.Range(0, list.Count).ToArray();
        int Find(int i) { while (parent[i] != i) i = parent[i] = parent[parent[i]]; return i; }
        string Loc(AppRow r) => string.IsNullOrWhiteSpace(r.Location) ? "" : r.Location.Trim().TrimEnd('\\', '/').Replace('/', '\\').ToLowerInvariant();
        var norm = list.Select(r => Leftovers.Norm(BaseName(r.Name))).ToList();
        for (int i = 0; i < list.Count; i++)
            for (int j = i + 1; j < list.Count; j++)
            {
                bool same = Loc(list[i]).Length > 3 && Loc(list[i]) == Loc(list[j])
                            || norm[i].Length >= 3 && norm[i] == norm[j]
                            || norm[i].Length >= 4 && norm[j].StartsWith(norm[i])
                            || norm[j].Length >= 4 && norm[i].StartsWith(norm[j]);
                // two programs for everyone are two programs (an "Office" suite has many uninstall entries of its own)
                if (same && list[i].Kind == "machine" && list[j].Kind == "machine" && norm[i] != norm[j]) same = false;
                if (same) parent[Find(i)] = Find(j);
            }
        return list.Select((r, i) => (r, g: Find(i))).GroupBy(x => x.g).Select(g => g.Select(x => x.r).ToList()).ToList();
    }

    /// <summary>The name a group is shown with: its uninstall entry (or Store app) first, then a name that is not a GUID.</summary>
    public static string GroupName(IReadOnlyList<AppRow> g)
    {
        var main = g.FirstOrDefault(r => r.Kind is "user" or "machine" or "appx") ?? g.FirstOrDefault(r => !IsGuid(r.Name)) ?? g[0];
        return main.Name;
    }

    /// <summary>What "Keep" on a new app puts on the Keep List (home relative, "/" separated): its program folder when it
    /// is inside the user folder, and the AppData folders that look like its data (AppMatch). Never a whole AppData
    /// folder, a shared folder (AppData\Local\Programs) or Amnesia itself.</summary>
    public static List<string> KeepPaths(string name, string? publisher, IEnumerable<string?> locations, IEnumerable<string> candidates, string home)
    {
        var list = new List<string>();
        var h = home.Replace('\\', '/').TrimEnd('/');
        string? inst = null;
        foreach (var l in locations)
        {
            if (string.IsNullOrWhiteSpace(l)) continue;
            var p = l.Trim().Trim('"').Replace('\\', '/').TrimEnd('/');
            inst ??= p;
            if (!p.StartsWith(h + "/", StringComparison.OrdinalIgnoreCase)) continue;
            var rel = p[(h.Length + 1)..];
            var parts = rel.Split('/');
            if (rel.Contains("..") || parts.Length < 3 || !parts[0].Equals("AppData", StringComparison.OrdinalIgnoreCase)) continue;
            if (parts.Length == 3 && AppMatch.Skip.Contains(parts[2], StringComparer.OrdinalIgnoreCase)) continue;
            if (rel.Contains("/Amnesia", StringComparison.OrdinalIgnoreCase)) continue;
            if (!list.Contains(rel, StringComparer.OrdinalIgnoreCase)) list.Add(rel);
        }
        foreach (var f in AppMatch.Folders(BaseName(name), publisher, inst, candidates))
            if (!list.Any(x => x.Equals(f, StringComparison.OrdinalIgnoreCase) || f.StartsWith(x + "/", StringComparison.OrdinalIgnoreCase)))
                list.Add(f);
        return list;
    }
}
