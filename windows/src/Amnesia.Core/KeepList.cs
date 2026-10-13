// keep.conf: the Keep List. One path per line from your user folder (* works, / or \), # = comment.
// Lines like "credential:..." or "app:..." are for other parts of Amnesia and are skipped by the cleanup.
namespace Amnesia.Core;

public static class KeepList
{
    /// <summary>v0.7: while the lab lock is on, the administrator's locked copy is the Keep List.</summary>
    public static string File => Lab.Active ? Lab.KeepFile : Path.Combine(Home.Dir, "keep.conf");

    /// <summary>The paths on the Keep List, cleaned up (always with /, no slash at the ends).</summary>
    public static List<string> Paths()
    {
        var list = new List<string>();
        if (!System.IO.File.Exists(File)) return list;
        foreach (var raw in System.IO.File.ReadAllLines(File))
        {
            var l = raw.Trim();
            if (l.Length == 0 || l.StartsWith('#') || IsTagged(l)) continue;
            list.Add(Norm(l));
        }
        return list;
    }

    static bool IsTagged(string l) => System.Text.RegularExpressions.Regex.IsMatch(l, "^[a-z]+:", System.Text.RegularExpressions.RegexOptions.IgnoreCase) && !(l.Length > 1 && l[1] == ':');

    public static string Norm(string p) => p.Trim().Replace('\\', '/').Trim('/');

    /// <summary>Adds a path (a full path inside the user folder is turned into a relative one). Returns the line, or null
    /// when the path is outside the user folder or already there.</summary>
    public static string? Add(string path)
    {
        var p = path.Trim().Replace('\\', '/');
        var home = Home.User.Replace('\\', '/');
        if (p.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase)) p = p[(home.Length + 1)..];
        else if (Path.IsPathFullyQualified(path) || (p.Length > 1 && p[1] == ':')) return null;
        p = Norm(p);
        if (p.Length == 0 || p.StartsWith("..")) return null;
        if (Paths().Any(x => string.Equals(x, p, StringComparison.OrdinalIgnoreCase))) return null;
        Directory.CreateDirectory(Home.Dir);
        System.IO.File.AppendAllText(File, p + Environment.NewLine);
        return p;
    }

    /// <summary>Takes a path off the list (comments and other lines stay as they are).</summary>
    public static bool Remove(string path)
    {
        if (!System.IO.File.Exists(File)) return false;
        var p = Norm(path);
        var lines = System.IO.File.ReadAllLines(File).ToList();
        int n = lines.RemoveAll(l => { var t = l.Trim(); return t.Length > 0 && !t.StartsWith('#') && !IsTagged(t) && string.Equals(Norm(t), p, StringComparison.OrdinalIgnoreCase); });
        if (n > 0) System.IO.File.WriteAllLines(File, lines);
        return n > 0;
    }
}
