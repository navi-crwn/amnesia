// settings.conf in %USERPROFILE%\.amnesia: one KEY=value per line, same file format as the Mac.
namespace Amnesia.Core;

public static class Conf
{
    static readonly object Lock = new();
    static string File => Path.Combine(Home.Dir, "settings.conf");

    /// <summary>A setting. While the lab lock is on, the locked settings come from the administrator's copy (Lab.cs).</summary>
    public static string? Get(string key)
    {
        if (Array.IndexOf(Lab.PolicyKeys, key) >= 0 && Lab.Active) return Lab.Get(key);
        return GetOwn(key);
    }

    /// <summary>This user's own settings.conf, never the lab copy.</summary>
    public static string? GetOwn(string key)
    {
        lock (Lock)
        {
            if (!System.IO.File.Exists(File)) return null;
            string? v = null;
            foreach (var l in System.IO.File.ReadAllLines(File))
                if (l.StartsWith(key + "=", StringComparison.Ordinal)) v = l[(key.Length + 1)..];
            return v;
        }
    }

    public static void Set(string key, string? value)
    {
        lock (Lock)
        {
            Directory.CreateDirectory(Home.Dir);
            var lines = System.IO.File.Exists(File) ? System.IO.File.ReadAllLines(File).ToList() : new List<string>();
            lines.RemoveAll(l => l.StartsWith(key + "=", StringComparison.Ordinal));
            if (value != null) lines.Add($"{key}={value}");
            System.IO.File.WriteAllLines(File, lines);
        }
    }

    public static bool On(string key, bool fallback = false) => Get(key) switch { "1" => true, "0" => false, _ => fallback };
    public static int Int(string key, int fallback = 0) => int.TryParse(Get(key), out var i) ? i : fallback;

    public static bool Enabled => Lab.Active || Get("ENABLED") == "1";
    public static string PauseFile => Path.Combine(Home.Dir, "pause_once");
    public static bool Paused => !Lab.Active && System.IO.File.Exists(PauseFile);

    /// <summary>The Keep folder as a path inside the user folder ("Keep", "Documents/Safe"), or "" when it is outside it
    /// (then it is never touched anyway). KEEP_DIR: "~/Something" or a full path. Same rules as the Mac.</summary>
    public static string KeepRel
    {
        get
        {
            var kd = Get("KEEP_DIR")?.Trim().Replace('\\', '/');
            if (string.IsNullOrEmpty(kd)) return "Keep";
            string rel;
            var home = Home.User.Replace('\\', '/');
            if (kd.StartsWith("~/")) rel = kd[2..].TrimEnd('/');
            else if (kd.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase)) rel = kd[(home.Length + 1)..].TrimEnd('/');
            else return "";
            if (rel.Length == 0 || Wild.Like(rel, ".amnesia*") || Wild.Like(rel, "AppData*")) rel = "Keep";
            return rel;
        }
    }

    /// <summary>The Keep folder as a full path.</summary>
    public static string KeepDir
    {
        get
        {
            var rel = KeepRel;
            if (rel.Length > 0) return Home.Full(rel);
            return Get("KEEP_DIR")!.Trim().TrimEnd('\\', '/');
        }
    }
}

/// <summary>Wildcards like Windows / PowerShell -like: * and ?, never case-sensitive.</summary>
public static class Wild
{
    public static bool Like(string text, string pattern)
    {
        int t = 0, p = 0, star = -1, mark = 0;
        while (t < text.Length)
        {
            if (p < pattern.Length && (pattern[p] == '?' || char.ToUpperInvariant(pattern[p]) == char.ToUpperInvariant(text[t]))) { t++; p++; }
            else if (p < pattern.Length && pattern[p] == '*') { star = p++; mark = t; }
            else if (star >= 0) { p = star + 1; t = ++mark; }
            else return false;
        }
        while (p < pattern.Length && pattern[p] == '*') p++;
        return p == pattern.Length;
    }
}
