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
            if (Outside(l)) continue; // v0.11.1: can never match; Ignored() lists it so the app can say so
            list.Add(Norm(l));
        }
        return list;
    }

    /// <summary>v0.11.1: lines of keep.conf that can never protect anything: a path on another drive, a network path, one with
    /// "..", or just "~". They are not applied (and not guessed at); the app shows them so you can fix them.</summary>
    public static List<string> Ignored()
    {
        var list = new List<string>();
        try
        {
            if (!System.IO.File.Exists(File)) return list;
            foreach (var raw in System.IO.File.ReadAllLines(File))
            {
                var l = raw.Trim();
                if (l.Length == 0 || l.StartsWith('#') || IsTagged(l)) continue;
                if (Outside(l)) list.Add(l);
            }
        }
        catch { }
        return list;
    }

    // a line is "outside" when, after ~/ and your own user folder are taken off, it is still a full path, a network path or
    // climbs out with ".." (or is nothing at all, like "~")
    static bool Outside(string line)
    {
        var rel = Norm(line);
        if (rel.Length == 0) return true;
        var s = line.Trim().Replace('\\', '/');
        var home = Home.User.Replace('\\', '/');
        bool inHome = s.StartsWith("~/") || s.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase);
        // a leading // or \\ is not reported: it was always read as a path from the user folder (it protects more, never less)
        if (!inHome && !HasEnvPrefix(s) && s.Length > 1 && s[1] == ':') return true;
        return rel.Split('/').Contains("..");
    }

    static bool IsTagged(string l) => System.Text.RegularExpressions.Regex.IsMatch(l, "^[a-z]+:", System.Text.RegularExpressions.RegexOptions.IgnoreCase) && !(l.Length > 1 && l[1] == ':');

    // %USERPROFILE%/X, $HOME/X and $env:USERPROFILE/X (written with / after the slashes were turned) mean the user folder
    static bool HasEnvPrefix(string s) => new[] { "%userprofile%/", "$home/", "$env:userprofile/" }.Any(e => s.StartsWith(e, StringComparison.OrdinalIgnoreCase));

    /// <summary>The line as a path inside the user folder (v0.11.1: "~/X" and a full path inside your user folder lose their
    /// front part, so they match like the plain "X").</summary>
    public static string Norm(string p)
    {
        var s = p.Trim().Replace('\\', '/');
        var home = Home.User.Replace('\\', '/');
        if (s == "~") s = "";
        else if (s.StartsWith("~/")) s = s[2..];
        else if (s.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase)) s = s[(home.Length + 1)..];
        else if (HasEnvPrefix(s)) s = s[(s.IndexOf('/') + 1)..];
        return s.Trim('/');
    }

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
            // v0.11.1: a file with nothing in it at all, where the last good copy had lines: a cut off write, not a choice
            // (taking off the last line writes a comment, never zero bytes)
            if (text.Trim().Length == 0 && HasLines(System.IO.File.Exists(Last) ? System.IO.File.ReadAllText(Last) : "")) { text = null; return "unreadable"; }
            return null;
        }
        catch { text = null; return "unreadable"; }
    }

    static bool HasLines(string text) => text.Split('\n').Select(l => l.Trim()).Any(l => l.Length > 0 && !l.StartsWith('#'));

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

    /// <summary>v0.9: keep.conf is gone but its last good copy is there: put the copy back. True when it did.
    /// v0.11.1: also when keep.conf is there but has nothing in it at all (a cut off write) and the copy has lines.</summary>
    public static bool RestoreLast()
    {
        try
        {
            if (!System.IO.File.Exists(Last)) return false;
            if (System.IO.File.Exists(File))
            {
                var now = System.IO.File.ReadAllText(File);
                if (now.Trim().Length > 0 || now.IndexOf((char)0) >= 0 || !HasLines(System.IO.File.ReadAllText(Last))) return false;
                Conf.WriteAtomic(File, System.IO.File.ReadAllLines(Last));
                return true;
            }
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
        if (p.Length == 0 || p.Split('/').Contains("..")) return null;
        Directory.CreateDirectory(Home.Dir);
        RestoreLast(); // v0.9: a lost keep.conf comes back first, so adding one line does not make a list of one
        if (Paths().Any(x => string.Equals(x, p, StringComparison.OrdinalIgnoreCase))) return null;
        var all = System.IO.File.Exists(File) ? System.IO.File.ReadAllLines(File).ToList() : new List<string>();
        all.Add(p);
        Conf.WriteAtomic(File, all);
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
        if (n > 0)
        {
            // never a zero byte file: that reads as broken (a cut off write), so an empty list keeps a comment line
            if (!lines.Any(l => l.Trim().Length > 0)) lines.Add("# Keep List (empty)");
            Conf.WriteAtomic(File, lines);
        }
        return n > 0;
    }
}
