// v0.10: vault profiles (same idea as the Mac). Named groups of vault apps, so a restore can bring back only what you
// need right now ("Work", "Personal"), or everything. profiles.json next to settings.conf holds names and app names only,
// never a password or anything from the snapshots. Snapshots stay one per app, as before.
//
// File: {"version":1,"last":"all","profiles":[{"id":"work","name":"Work","apps":["Claude","Chrome"]}]}
// - No file, or a file without "profiles": the built-in suggestions are shown (in the current language). Nothing is
//   written until the first save; from then on the file is the whole list, so deleting a built-in sticks.
// - "Everything" (id "all") is never stored and always comes first.
using System.Text.Json.Nodes;

namespace Amnesia.Core;

public sealed record VaultProfile(string Id, string Name, List<string> Apps, bool BuiltIn);

public static class VaultProfiles
{
    public const string AllId = "all";
    public const int MaxName = 40, MaxProfiles = 20;
    static readonly object Lock = new();

    public static string File => Path.Combine(Home.Dir, "profiles.json");

    /// <summary>Indonesian names for the built-ins? Amnesia.exe sets this (AppInfo.Id); otherwise LANG or the Windows language.</summary>
    public static Func<bool>? Indonesian { get; set; }
    static bool Id => Indonesian?.Invoke() ?? Conf.Get("LANG") switch
    {
        "id" => true,
        "en" => false,
        _ => System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "id",
    };

    // Built-in suggestions. Only apps that are on this PC are used; a built-in with no app here is not shown.
    static readonly string[] WorkApps =
        { "Claude", "Claude Code", "OpenCode", "Gemini CLI", "GitHub CLI", "Git", "Antigravity", "VS Code", "Cursor", "Windsurf", "Slack", "Chrome" };
    static readonly string[] PersonalApps = { "WhatsApp", "Telegram", "Signal", "Discord", "Session", "Element", "Spotify" };
    // A second browser for personal use (streaming, social): every one of these that is on this PC
    static readonly string[] PersonalBrowsers = { "Firefox", "Brave", "Vivaldi", "Opera", "Microsoft Edge" };

    static readonly string[] Reserved = { "all", "everything", "semua" };

    /// <summary>Vault item names (apps and added folders), as Vault.All() names them.</summary>
    public static List<string> Known() => Vault.All().Select(a => a.Name).ToList();

    static string? Canonical(string name) =>
        Vault.All().Select(a => a.Name).FirstOrDefault(n => n.Equals(name.Trim(), StringComparison.OrdinalIgnoreCase));

    static bool Here(string name) => Vault.All().FirstOrDefault(a => a.Name == name) is VaultApp a && Vault.Present(a).Length > 0;

    static List<VaultProfile> BuiltIns()
    {
        var list = new List<VaultProfile>();
        var work = WorkApps.Where(Here).ToList();
        if (work.Count > 0) list.Add(new VaultProfile("work", Id ? "Kerja" : "Work", work, true));
        var personal = PersonalApps.Concat(PersonalBrowsers).Where(Here).ToList();
        if (personal.Count > 0) list.Add(new VaultProfile("personal", Id ? "Santai" : "Personal", personal, true));
        return list;
    }

    // ---------- file ----------
    static JsonObject? ReadFile()
    {
        try { return System.IO.File.Exists(File) ? JsonNode.Parse(System.IO.File.ReadAllText(File)) as JsonObject : null; }
        catch { return null; }
    }

    /// <summary>The stored profiles, or null when there are none stored yet (no file, no "profiles", or a damaged file).</summary>
    static List<VaultProfile>? Stored(JsonObject? f)
    {
        if (f?["profiles"] is not JsonArray arr) return null;
        var list = new List<VaultProfile>();
        var ids = new HashSet<string>();
        foreach (var n in arr)
        {
            try
            {
                var id = n?["id"]?.GetValue<string>() ?? "";
                var name = n?["name"]?.GetValue<string>() ?? "";
                if (!ValidId(id) || id == AllId || !ids.Add(id) || !ValidName(name)) continue;
                var apps = (n?["apps"] as JsonArray ?? new JsonArray()).Select(x => { try { return x?.GetValue<string>(); } catch { return null; } })
                    .Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x!).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                list.Add(new VaultProfile(id, name.Trim(), apps, false));
            }
            catch { }
        }
        return list;
    }

    static void Write(List<VaultProfile>? profiles, string last)
    {
        Directory.CreateDirectory(Home.Dir);
        var o = new JsonObject { ["version"] = 1, ["last"] = last };
        if (profiles != null)
            o["profiles"] = new JsonArray(profiles.Select(p => (JsonNode)new JsonObject
            {
                ["id"] = p.Id,
                ["name"] = p.Name,
                ["apps"] = new JsonArray(p.Apps.Select(a => (JsonNode)a!).ToArray()),
            }).ToArray());
        // a damaged file is kept next to it once, so nothing the user wrote is lost without a trace
        if (System.IO.File.Exists(File) && ReadFile() == null)
            try { System.IO.File.Copy(File, File + ".bad", true); } catch { }
        var tmp = File + ".tmp";
        System.IO.File.WriteAllText(tmp, o.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true }));
        System.IO.File.Move(tmp, File, true); // a rename, so a half written file never takes its place
    }

    static bool ValidId(string id) => id.Length is >= 1 and <= 32 && id.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '-');
    static bool ValidName(string name)
    {
        var t = name.Trim();
        return t.Length is >= 1 and <= MaxName && !t.Any(char.IsControl);
    }

    static string Slug(string name, IEnumerable<string> taken)
    {
        var chars = name.Trim().ToLowerInvariant().Select(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' ? c : '-').ToArray();
        var s = string.Join('-', new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
        if (s.Length > 28) s = s[..28].TrimEnd('-');
        if (s.Length == 0) s = "profile";
        var used = new HashSet<string>(taken) { AllId };
        if (!used.Contains(s)) return s;
        for (int i = 2; ; i++) if (!used.Contains(s + "-" + i)) return s + "-" + i;
    }

    // ---------- reading ----------
    /// <summary>"Everything" first, then the stored profiles (or the built-ins when nothing is stored yet).</summary>
    public static List<VaultProfile> All()
    {
        lock (Lock)
        {
            var list = new List<VaultProfile> { new(AllId, Id ? "Semua" : "Everything", Known(), true) };
            list.AddRange(Stored(ReadFile()) ?? BuiltIns());
            return list;
        }
    }

    static List<VaultProfile> Own() => All().Where(p => p.Id != AllId).ToList();

    /// <summary>Apps that are in 2 or more profiles: app -> profile ids. One browser holds one set of logins, so it can't
    /// be split between Work and Personal.</summary>
    public static Dictionary<string, List<string>> Shared()
    {
        var map = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in Own())
            foreach (var a in p.Apps)
            {
                if (!map.TryGetValue(a, out var ids)) map[a] = ids = new List<string>();
                if (!ids.Contains(p.Id)) ids.Add(p.Id);
            }
        return map.Where(kv => kv.Value.Count >= 2).ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>The profile picked for the last restore ("all" when it is gone).</summary>
    public static string Last
    {
        get
        {
            var l = ReadFile()?["last"] is JsonValue v && v.TryGetValue<string>(out var s) ? s : AllId;
            return l == AllId || Own().Any(p => p.Id == l) ? l : AllId;
        }
        set
        {
            lock (Lock)
            {
                var id = string.IsNullOrEmpty(value) ? AllId : value;
                var f = ReadFile();
                var stored = Stored(f);
                if (id == LastRaw() && f != null) return; // v0.10 (item 189): nothing changed, nothing written
                if (stored == null && id == AllId)
                {
                    // v0.10 (item 189): "Everything" is the default, so no file is needed for it
                    try { if (System.IO.File.Exists(File)) System.IO.File.Delete(File); } catch { }
                    return;
                }
                Write(stored, id); // no profiles stored yet: only "last" is written, the built-ins still follow the language
            }
        }
    }

    /// <summary>The apps to restore for a profile. null = everything ("all" or empty). An unknown profile gives an empty
    /// list, so a deleted profile never turns into "restore everything" by surprise.</summary>
    public static List<string>? AppsFor(string id)
    {
        if (string.IsNullOrEmpty(id) || id == AllId) return null;
        return Own().FirstOrDefault(p => p.Id == id)?.Apps.ToList() ?? new List<string>();
    }

    /// <summary>Names that are not vault items (they are ignored by a restore or a save).</summary>
    public static List<string> Ignored(IEnumerable<string> names) =>
        names.Where(n => Canonical(n) == null).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    // ---------- changing ----------
    /// <summary>Creates (id empty or unknown) or changes a profile. Apps that are not vault items are dropped.
    /// Errors: profile-name, profile-name-reserved, profile-name-taken, profile-too-many.</summary>
    public static VaultProfile Save(string? id, string name, IEnumerable<string> apps)
    {
        lock (Lock)
        {
            name = (name ?? "").Trim();
            if (!ValidName(name)) throw new InvalidOperationException("profile-name");
            if (Reserved.Contains(name, StringComparer.OrdinalIgnoreCase)) throw new InvalidOperationException("profile-name-reserved");
            var list = Own().Select(p => p with { BuiltIn = false }).ToList();
            var at = string.IsNullOrEmpty(id) ? -1 : list.FindIndex(p => p.Id == id);
            if (list.Where((p, i) => i != at).Any(p => p.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("profile-name-taken");
            var clean = new List<string>();
            foreach (var a in apps ?? Array.Empty<string>())
                if (a != null && Canonical(a) is string c && !clean.Contains(c, StringComparer.OrdinalIgnoreCase)) clean.Add(c);
            VaultProfile saved;
            if (at >= 0) list[at] = saved = list[at] with { Name = name, Apps = clean };
            else
            {
                if (list.Count >= MaxProfiles) throw new InvalidOperationException("profile-too-many");
                saved = new VaultProfile(Slug(name, list.Select(p => p.Id)), name, clean, false);
                list.Add(saved);
            }
            Write(list, LastRaw());
            return saved;
        }
    }

    /// <summary>Deletes a profile (a built-in too: it stays deleted). "all" can't be deleted.</summary>
    public static bool Delete(string id)
    {
        lock (Lock)
        {
            if (string.IsNullOrEmpty(id) || id == AllId) return false;
            var list = Own().Select(p => p with { BuiltIn = false }).ToList();
            if (list.RemoveAll(p => p.Id == id) == 0) return false;
            var last = LastRaw();
            Write(list, last == id ? AllId : last);
            return true;
        }
    }

    static string LastRaw() => ReadFile()?["last"] is JsonValue v && v.TryGetValue<string>(out var s) && s.Length > 0 ? s : AllId;
}
