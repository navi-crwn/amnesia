// keep.conf: the Keep List. One path per line from your user folder (* works, / or \), # = comment.
// Lines like "credential:..." or "app:..." are for other parts of Amnesia and are skipped by the cleanup.
namespace Amnesia.Core;

public static class KeepList
{
    /// <summary>v0.7: while the lab lock is on, the administrator's locked copy is the Keep List.</summary>
    public static string File => PreviewFile ?? (Lab.Active ? Lab.KeepFile : Path.Combine(Home.Dir, "keep.conf"));

    /// <summary>v0.10: set only around a mode preview's dry run (this thread only): the cleanup then reads this copy.</summary>
    [ThreadStatic] public static string? PreviewFile;

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

    // ---------- v0.9: the last good copy (keep.conf.last) ----------

    /// <summary>v0.9: the copy of the Keep List as it was at the last cleanup that ran to the end.</summary>
    public static string Last => File + ".last";

    /// <summary>v0.9: can the cleanup trust the Keep List right now? null = yes. "missing" = keep.conf is gone but there
    /// was one before (the last good copy is there). "unreadable" = it is there but can't be read (locked, denied, or
    /// broken: zero bytes inside). A cleanup that gets an answer other than null stops and deletes nothing.
    /// text = what was read (null when there is no keep.conf).</summary>
    public static string? Check(out string? text)
    {
        text = null;
        try
        {
            var f = File;
            if (!System.IO.File.Exists(f))
            {
                // File.Exists also says false when the folder can't be read: then we can't tell, so it is "unreadable"
                var dir = Path.GetDirectoryName(f);
                if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir)) _ = Directory.EnumerateFileSystemEntries(dir).Any();
                // never had one (a new install): fine. Had one before (its copy is there): stop.
                return System.IO.File.Exists(Last) ? "missing" : null;
            }
            text = System.IO.File.ReadAllText(f);
            if (text.IndexOf('\0') >= 0) { text = null; return "unreadable"; }
            return null;
        }
        catch { text = null; return "unreadable"; }
    }

    /// <summary>v0.9: saves the last good copy (temp file + rename, so a cut off write never leaves half a copy).
    /// Only after a real cleanup ran to the end. Errors are ignored (in lab mode the folder is the admin's).</summary>
    public static void SaveLast(string text)
    {
        var tmp = Last + ".tmp";
        try
        {
            System.IO.File.WriteAllText(tmp, text);
            System.IO.File.Move(tmp, Last, overwrite: true);
        }
        catch { try { System.IO.File.Delete(tmp); } catch { } }
    }

    /// <summary>v0.9: keep.conf is gone but its last good copy is there: put the copy back. True when it did.</summary>
    public static bool RestoreLast()
    {
        try
        {
            if (System.IO.File.Exists(File) || !System.IO.File.Exists(Last)) return false;
            System.IO.File.Copy(Last, File, overwrite: false);
            return true;
        }
        catch { return false; }
    }

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
        Directory.CreateDirectory(Home.Dir);
        RestoreLast(); // v0.9: a lost keep.conf comes back first, so adding one line does not make a list of one
        if (Paths().Any(x => string.Equals(x, p, StringComparison.OrdinalIgnoreCase))) return null;
        System.IO.File.AppendAllText(File, p + Environment.NewLine);
        return p;
    }

    /// <summary>Takes a path off the list (comments and other lines stay as they are).</summary>
    public static bool Remove(string path)
    {
        RestoreLast(); // v0.9
        if (!System.IO.File.Exists(File)) return false;
        var p = Norm(path);
        var lines = System.IO.File.ReadAllLines(File).ToList();
        int n = lines.RemoveAll(l => { var t = l.Trim(); return t.Length > 0 && !t.StartsWith('#') && !IsTagged(t) && string.Equals(Norm(t), p, StringComparison.OrdinalIgnoreCase); });
        if (n > 0) System.IO.File.WriteAllLines(File, lines);
        return n > 0;
    }
}
