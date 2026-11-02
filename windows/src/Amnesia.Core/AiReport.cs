// v0.10 "Ask an AI": advice without Amnesia sending anything anywhere.
//   Build     a report about this PC with NO file contents and NO names of files or folders below the top level of the
//             user folder. Exceptions: folder names right inside AppData\Roaming and AppData\Local, installed program
//             names and the Keep List lines. hideNames hides even those folder names (and your own Keep List lines).
//   Markdown  the same report as text, Prompt the ready-made question; the user pastes both into the AI they choose.
//   Parse     reads the AI's answer back: the first ```amnesia-suggestion block, checked line by line. Nothing is applied
//             here: the page shows every change with a checkbox and applies the ticked ones through Modes (the same
//             preview and confirm as a mode switch) and the vault profiles.
// No network calls anywhere in this file. Same report and rules as the Mac (report.py).
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Amnesia.Core;

public static class AiReport
{
    /// <summary>Top level folders Windows makes itself: their names are never hidden.</summary>
    public static readonly string[] StandardHome =
    {
        "AppData", "Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Favorites", "Contacts", "Links",
        "Searches", "Saved Games", "OneDrive",
    };

    public const int MaxAnswer = 64 * 1024, MaxList = 200, MaxProfiles = 10, MaxNotes = 2000, MaxLine = 300;
    static readonly TimeSpan ItemTime = TimeSpan.FromSeconds(20), TotalTime = TimeSpan.FromSeconds(90);

    // ---------- given by Amnesia.exe (the tests leave them empty) ----------
    /// <summary>The disk overview (Care). Not set: Amnesia.Core's own Care without the Recycle Bin.</summary>
    public static Func<CareOverview?>? CareProvider { get; set; }
    /// <summary>How many programs "Remove new apps" would take at the next sign out.</summary>
    public static Func<int>? NewAppsCount { get; set; }
    /// <summary>Vault profiles (id, name, apps). Not set: VaultProfiles.All(), else profiles.json.</summary>
    public static Func<IEnumerable<(string Id, string Name, List<string> Apps)>>? Profiles { get; set; }

    // ---------- sizes, with a time limit ----------
    sealed class Sizer
    {
        readonly Stopwatch total = Stopwatch.StartNew();
        /// <summary>Bytes in a file or folder (links are never followed), -1 when it took too long or can't be read.</summary>
        public long Of(string full)
        {
            if (total.Elapsed > TotalTime) return -1;
            try
            {
                var fi = new FileInfo(full);
                if (fi.Exists) return fi.Length;
                var di = new DirectoryInfo(full);
                if (!di.Exists || di.Attributes.HasFlag(FileAttributes.ReparsePoint)) return di.Exists ? 0 : -1;
                var item = Stopwatch.StartNew();
                long n = 0; int i = 0;
                var opt = new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = true };
                foreach (var f in di.EnumerateFiles("*", opt))
                {
                    n += f.Length;
                    if (++i % 500 == 0 && (item.Elapsed > ItemTime || total.Elapsed > TotalTime)) return -1;
                }
                return n;
            }
            catch { return -1; }
        }
    }

    static string State() => !Conf.Enabled ? "off" : Conf.Paused ? "paused" : "on";

    static JsonArray Arr(IEnumerable<string> l) => new(l.Select(x => (JsonNode)JsonValue.Create(x)!).ToArray());

    /// <summary>The last cleanup from history.log ("time TAB clean TAB mode moved bytes").</summary>
    static JsonObject? LastCleanup()
    {
        try
        {
            var f = Path.Combine(Home.Dir, "history.log");
            if (!File.Exists(f)) return null;
            foreach (var l in File.ReadAllLines(f).Reverse())
            {
                var p = l.Split('\t');
                if (p.Length < 3 || p[1] != "clean") continue;
                var d = p[2].Split(' ');
                long.TryParse(d.ElementAtOrDefault(2), out var bytes);
                int.TryParse(d.ElementAtOrDefault(1), out var items);
                return new JsonObject { ["time"] = p[0], ["kind"] = d.ElementAtOrDefault(0) ?? "", ["items"] = items, ["kb"] = bytes >= 0 ? bytes / 1024 : -1, ["failed"] = null };
            }
        }
        catch { }
        return null;
    }

    /// <summary>The vault profiles: from VaultProfiles, or profiles.json when that fails.</summary>
    static List<(string Id, string Name, List<string> Apps)> ReadProfiles()
    {
        try { if (Profiles != null) return Profiles().ToList(); } catch { }
        var list = new List<(string, string, List<string>)>();
        try
        {
            // v0.10: VaultProfiles is in this assembly now, so it is called directly.
            foreach (var p in VaultProfiles.All())
                if (p.Id != VaultProfiles.AllId) list.Add((p.Id, p.Name, p.Apps.ToList()));
            return list;
        }
        catch { list.Clear(); }
        try
        {
            var f = Path.Combine(Home.Dir, "profiles.json");
            if (File.Exists(f) && JsonNode.Parse(File.ReadAllText(f))?["profiles"] is JsonArray a)
                foreach (var p in a.OfType<JsonObject>())
                    list.Add((p["id"]?.ToString() ?? "", p["name"]?.ToString() ?? "", p["apps"] is JsonArray x ? x.Select(v => v?.ToString() ?? "").Where(v => v.Length > 0).ToList() : new List<string>()));
        }
        catch { }
        return list;
    }

    /// <summary>App data folder names (AppData\Roaming\X, AppData\Local\X) that belong to a vault app.</summary>
    static HashSet<string> VaultFolders()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var a in Vault.All())
            foreach (var p in a.Paths)
            {
                var s = p.Split('/');
                if (s.Length >= 3 && s[0] == "AppData" && s[1] is "Roaming" or "Local" && !s[2].Contains('*')) set.Add(s[1] + "/" + s[2]);
            }
        return set;
    }

    static string LineKind(string l) => Regex.IsMatch(l, "^app:", RegexOptions.IgnoreCase) ? "app"
        : Regex.IsMatch(l, "^[a-z]+:", RegexOptions.IgnoreCase) && !(l.Length > 1 && l[1] == ':') ? "keychain" : "path";

    /// <summary>The report as JSON (schema amnesia-report/1). Reads only names and sizes, never what is inside a file.
    /// Runs a dry run of the next sign out and counts sizes (90 seconds at most), so call it off the window's thread.</summary>
    public static JsonObject Build(bool hideNames, Func<IEnumerable<string>>? installedApps = null)
    {
        var sz = new Sizer();
        var keepCheck = KeepList.Check(out _);
        var r = new JsonObject
        {
            ["schema"] = "amnesia-report/1",
            ["made"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm"),
            ["platform"] = "windows",
            ["os"] = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
            ["arch"] = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant(),
            ["hide_names"] = hideNames,
        };
        r["amnesia"] = new JsonObject
        {
            ["version"] = Home.Version, ["state"] = State(), ["mode"] = Modes.Current(), ["last_cleanup"] = LastCleanup(),
            ["keep_list"] = keepCheck == null ? "ok" : "keeplist-" + keepCheck,
        };
        var keepDir = Conf.KeepDir;
        r["keep_dir"] = new JsonObject { ["path"] = hideNames ? "(hidden)" : keepDir, ["bytes"] = Directory.Exists(keepDir) ? sz.Of(keepDir) : 0 };

        // Keep List: the mode's lines first, then your own
        var (bid, blines) = Modes.BlockLines();
        var own = Modes.Own();
        if (hideNames) own = own.Select((l, i) => $"line {i + 1} ({LineKind(l)})").ToList();
        r["keep_list"] = new JsonObject
        {
            ["mode_block"] = bid == null ? null : new JsonObject { ["mode"] = bid, ["lines"] = Arr(blines) },
            ["own"] = Arr(own),
        };

        // vault: app names and sizes. A folder you added yourself is named by its top folder only.
        var m = Vault.Manifest();
        var chosen = Vault.Chosen();
        var vapps = new JsonArray();
        int folderN = 0;
        // v0.10: the name each vault item gets in the report, so the profiles section names folders the same way
        var shownAs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string ShowItem(string real)
        {
            if (!real.StartsWith(Vault.FolderPrefix)) return real;
            if (shownAs.TryGetValue(real, out var s)) return s;
            var rel = real[Vault.FolderPrefix.Length..].Replace('\\', '/').Trim('/');
            return shownAs[real] = !hideNames && !rel.Contains('/') ? real : $"{Vault.FolderPrefix}folder {++folderN}";
        }
        foreach (var a in Vault.All())
        {
            var present = Vault.Present(a);
            if (present.Length == 0 && !m.ContainsKey(a.Name)) continue;
            long bytes = 0;
            foreach (var p in present) { var b = sz.Of(Home.Full(p)); bytes = b < 0 || bytes < 0 ? -1 : bytes + b; }
            var name = ShowItem(a.Name);
            vapps.Add(new JsonObject { ["name"] = name, ["bytes"] = bytes, ["snapshot"] = m[a.Name]?["time"]?.GetValue<string>(), ["chosen"] = chosen.Contains(a.Name) });
        }
        r["vault"] = new JsonObject { ["exists"] = Vault.Exists, ["apps"] = vapps };
        r["profiles"] = new JsonArray(ReadProfiles().Select(p => (JsonNode)new JsonObject { ["id"] = p.Id, ["name"] = p.Name, ["apps"] = Arr(p.Apps.Select(ShowItem)) }).ToArray());

        // the user folder: top level only
        var home = new JsonArray();
        int looseN = 0, hiddenN = 0; long looseB = 0;
        try
        {
            foreach (var c in new DirectoryInfo(Home.User).EnumerateFileSystemInfos().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
            {
                if (c is FileInfo f) { looseN++; looseB += f.Length; continue; }
                if (c.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                var name = c.Name;
                if (hideNames && !StandardHome.Contains(name, StringComparer.OrdinalIgnoreCase) && name != ".amnesia") name = $"folder {++hiddenN}";
                home.Add(new JsonObject { ["name"] = name, ["bytes"] = sz.Of(c.FullName) });
            }
        }
        catch { }
        r["home"] = home;
        r["home_loose_files"] = new JsonObject { ["count"] = looseN, ["bytes"] = looseB };

        // app data folders: AppData\Roaming and AppData\Local, top level only
        var appData = new JsonArray();
        var mine = VaultFolders();
        int adN = 0;
        foreach (var where in new[] { "Roaming", "Local" })
        {
            var dir = Home.Full("AppData/" + where);
            if (!Directory.Exists(dir)) continue;
            try
            {
                foreach (var d in new DirectoryInfo(dir).EnumerateDirectories().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                {
                    if (d.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                    var name = hideNames && !mine.Contains(where + "/" + d.Name) ? $"app data {++adN}" : d.Name;
                    appData.Add(new JsonObject { ["name"] = name, ["where"] = where, ["bytes"] = sz.Of(d.FullName) });
                }
            }
            catch { }
        }
        r["app_data"] = appData;

        List<string> installed;
        try { installed = (installedApps?.Invoke() ?? Enumerable.Empty<string>()).Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x, StringComparer.OrdinalIgnoreCase).Take(400).ToList(); }
        catch { installed = new(); }
        r["installed_apps"] = Arr(installed);

        // what the next sign out wipes, counted per area (names never)
        var next = new JsonObject();
        try
        {
            var dry = Modes.NewEngine().Run("logout", true);
            var areas = new Dictionary<string, int> { ["Desktop"] = 0, ["Documents"] = 0, ["Downloads"] = 0, ["AppData"] = 0, ["dot folders"] = 0, ["Windows traces"] = 0, ["other"] = 0 };
            foreach (var i in dry.Items)
            {
                var top = i.Path.Split('\\', '/')[0];
                var k = top is "Desktop" or "Documents" or "Downloads" or "AppData" ? top : i.Kind == "trace" ? "Windows traces" : top.StartsWith('.') ? "dot folders" : "other";
                areas[k]++;
            }
            next["total"] = dry.Items.Count;
            var ao = new JsonObject(); foreach (var kv in areas) ao[kv.Key] = kv.Value;
            next["areas"] = ao;
            next["keychain"] = 0;
            int apps = 0; try { apps = NewAppsCount?.Invoke() ?? 0; } catch { }
            next["apps"] = apps;
            next["stopped"] = dry.Skipped;
        }
        catch { next["total"] = -1; next["areas"] = new JsonObject(); next["keychain"] = 0; next["apps"] = 0; next["stopped"] = "error"; }
        r["next_cleanup"] = next;

        // Care overview numbers
        var care = new JsonObject();
        try
        {
            var o = CareProvider != null ? CareProvider() : new Care().Overview(new CareBudget());
            if (o != null)
            {
                long S(string k) => o.Sizes.TryGetValue(k, out var e) ? e.Bytes : -1;
                var at = S("atrash"); var bin = S("bin");
                care["disk_free"] = o.DiskFree; care["disk_total"] = o.DiskTotal; care["caches"] = S("temp");
                care["trash"] = at < 0 && bin < 0 ? -1 : Math.Max(0, at) + Math.Max(0, bin); care["vault"] = S("vault");
            }
        }
        catch { }
        r["care"] = care;
        return r;
    }

    // ---------- Markdown ----------
    public static string Size(long? b)
    {
        if (b == null || b < 0) return "unknown";
        double v = b.Value;
        // v0.10 (item 194): decimal units (1 MB = 1000 KB), the same as the app pages
        if (v < 1000) return $"{v:0} B";
        if (v < 1_000_000) return $"{v / 1000:0} KB";
        if (v < 1_000_000_000) return $"{v / 1_000_000:0.#} MB";
        return $"{v / 1_000_000_000:0.#} GB";
    }
    static long? L(JsonNode? n) { try { return n?.GetValue<long>(); } catch { try { return (long?)n?.GetValue<int>(); } catch { return null; } } }
    static string Str(JsonNode? n) => n == null ? "" : n is JsonValue v && v.TryGetValue<string>(out var s) ? s : n.ToJsonString();
    static string Cell(string s) => s.Replace("|", "\\|").Replace("\n", " ");

    public static string Markdown(JsonObject r)
    {
        var sb = new StringBuilder();
        var a = r["amnesia"] as JsonObject ?? new JsonObject();
        bool hide = r["hide_names"]?.GetValue<bool>() == true;
        sb.AppendLine("# Amnesia report");
        sb.AppendLine($"Made by Amnesia {Str(a["version"])} on {Str(r["made"])}. No file contents and no names of your files. Folder names: {(hide ? "hidden" : "shown")}.");
        sb.AppendLine();
        sb.AppendLine("## System");
        sb.AppendLine($"- OS: {Str(r["os"])} ({Str(r["arch"])})");
        sb.AppendLine($"- Amnesia: {Str(a["version"])} for Windows");
        sb.AppendLine($"- State: {Str(a["state"])}");
        sb.AppendLine($"- Mode: {Str(a["mode"])}");
        if (a["last_cleanup"] is JsonObject lc)
            sb.AppendLine($"- Last cleanup: {Str(lc["time"])}, {Str(lc["kind"])}, {Str(lc["items"])} items, {Size(L(lc["kb"]) is long kb && kb >= 0 ? kb * 1024 : -1)}");
        else sb.AppendLine("- Last cleanup: none yet");
        var ks = Str(a["keep_list"]);
        sb.AppendLine(ks == "ok" ? "- Keep List: ok" : $"- Keep List: stopped ({ks}), nothing is deleted until it is fixed");
        var kd = r["keep_dir"] as JsonObject;
        sb.AppendLine($"- Keep folder: {Str(kd?["path"])} ({Size(L(kd?["bytes"]))})");
        sb.AppendLine();

        sb.AppendLine("## Keep List");
        sb.AppendLine("```text");
        var kl = r["keep_list"] as JsonObject;
        if (kl?["mode_block"] is JsonObject mb)
        {
            var lines = (mb["lines"] as JsonArray)?.Select(Str).ToList() ?? new();
            sb.AppendLine($"# (from mode {Str(mb["mode"])}){(lines.Count == 0 ? " no lines: Windows protection is built in" : "")}");
            foreach (var l in lines) sb.AppendLine(l);
        }
        var own = (kl?["own"] as JsonArray)?.Select(Str).ToList() ?? new();
        sb.AppendLine(own.Count == 0 ? "# (no lines of your own)" : "# (your own lines)");
        foreach (var l in own) sb.AppendLine(l);
        sb.AppendLine("```");
        sb.AppendLine();

        sb.AppendLine("## Profile Vault");
        var v = r["vault"] as JsonObject;
        sb.AppendLine($"Set up: {(v?["exists"]?.GetValue<bool>() == true ? "yes" : "no")}");
        sb.AppendLine();
        sb.AppendLine("| App | Snapshot | Size | In vault |");
        sb.AppendLine("|---|---|---|---|");
        foreach (var x in (v?["apps"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
            sb.AppendLine($"| {Cell(Str(x["name"]))} | {(x["snapshot"] == null ? "none" : Cell(Str(x["snapshot"])))} | {Size(L(x["bytes"]))} | {(x["chosen"]?.GetValue<bool>() == true ? "yes" : "no")} |");
        sb.AppendLine();

        sb.AppendLine("## Vault profiles");
        var profs = (r["profiles"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().ToList();
        if (profs.Count == 0) sb.AppendLine("- none yet (restoring brings back every app)");
        foreach (var p in profs) sb.AppendLine($"- {Str(p["name"])}: {string.Join(", ", (p["apps"] as JsonArray ?? new JsonArray()).Select(Str))}");
        sb.AppendLine();

        sb.AppendLine("## Home folder");
        sb.AppendLine("| Folder | Size |");
        sb.AppendLine("|---|---|");
        foreach (var x in (r["home"] as JsonArray ?? new JsonArray()).OfType<JsonObject>()) sb.AppendLine($"| {Cell(Str(x["name"]))} | {Size(L(x["bytes"]))} |");
        var lf = r["home_loose_files"] as JsonObject;
        sb.AppendLine();
        sb.AppendLine($"Plus {Str(lf?["count"])} loose files, {Size(L(lf?["bytes"]))}.");
        sb.AppendLine();

        sb.AppendLine("## App data folders");
        sb.AppendLine("| Folder | Where | Size |");
        sb.AppendLine("|---|---|---|");
        foreach (var x in (r["app_data"] as JsonArray ?? new JsonArray()).OfType<JsonObject>()) sb.AppendLine($"| {Cell(Str(x["name"]))} | AppData\\{Str(x["where"])} | {Size(L(x["bytes"]))} |");
        sb.AppendLine();

        sb.AppendLine("## Installed apps");
        var ia = (r["installed_apps"] as JsonArray ?? new JsonArray()).Select(Str).ToList();
        sb.AppendLine(ia.Count == 0 ? "(not known)" : string.Join(", ", ia));
        sb.AppendLine();

        sb.AppendLine("## What gets deleted at the next sign out");
        var n = r["next_cleanup"] as JsonObject;
        if (n?["stopped"] is JsonNode st && Str(st).Length > 0) sb.AppendLine($"- Stopped: {Str(st)}. Nothing would be deleted until this is fixed.");
        sb.AppendLine($"- Total: {Str(n?["total"])} items");
        foreach (var kv in n?["areas"] as JsonObject ?? new JsonObject()) sb.AppendLine($"- {kv.Key}: {Str(kv.Value)}");
        sb.AppendLine($"- New programs removed: {Str(n?["apps"])}");
        sb.AppendLine();

        sb.AppendLine("## Care overview");
        var c = r["care"] as JsonObject ?? new JsonObject();
        sb.AppendLine($"- Disk: {Size(L(c["disk_free"]))} free of {Size(L(c["disk_total"]))}");
        sb.AppendLine($"- Temp files: {Size(L(c["caches"]))}");
        sb.AppendLine($"- Trash (Amnesia trash and Recycle Bin): {Size(L(c["trash"]))}");
        sb.AppendLine($"- Keep folder: {Size(L(kd?["bytes"]))}");
        sb.AppendLine($"- Vault: {Size(L(c["vault"]))}");
        return sb.ToString();
    }

    // ---------- the prompt ----------
    const string Block = "```amnesia-suggestion\n{\"mode\": \"balanced\", \"keep_add\": [], \"keep_remove\": [], \"profiles\": {\"Work\": []}, \"notes\": \"\"}\n```";

    public static string Prompt(string lang) => lang == "id"
        ? "Saya memakai Amnesia, app privasi yang menghapus folder user saya setiap sign out, kecuali folder Keep saya, baris-baris di Keep List dan app yang disimpan di Profile Vault-nya. Di bawah ini ada laporan yang dibuat Amnesia tentang komputer saya (Windows). Laporan ini tidak berisi isi file dan tidak berisi nama file saya. Tolong bantu saya memilih pengaturan terbaik. Jelaskan dengan kata-kata sederhana apa yang dihapus sekarang dan apa yang mungkin hilang, dan apa yang aman untuk tetap disimpan atau berhenti disimpan. Mode yang bisa saya pilih: full (hanya folder Keep dan Amnesia sendiri yang tetap ada), balanced (folder Keep, login app lewat vault), light (app tetap menyimpan datanya di AppData: pengaturan, login, cache, file Temp dan riwayat Edge; file saya, Desktop, Documents dan Downloads dihapus), custom (daftar saya sendiri). Profil vault mengelompokkan app di vault supaya saya hanya me-restore yang saya perlukan, misalnya Kerja dan Santai. Pakai hanya nama app dari bagian Profile Vault di laporan. Baris Keep List adalah path relatif dari folder user saya, ditulis dengan /. Jangan pernah menyarankan menghapus baris milik Amnesia sendiri. Jawab dalam Bahasa Indonesia. Di akhir, berikan saran kamu dalam tepat satu blok seperti ini:\n"
          + Block + "\nPakai null untuk mode kalau kamu tidak akan menggantinya. Amnesia menunjukkan setiap perubahan dengan kotak centang, dan tidak ada yang diterapkan sampai saya konfirmasi."
        : "I use Amnesia, a privacy app that wipes my user folder at every sign out, except my Keep folder, the lines on my Keep List and the apps saved in its Profile Vault. Below is a report Amnesia made about my computer (Windows). It has no file contents and no names of my files. Please help me choose the best settings. Explain in simple words what is wiped today and what I might lose, and what I could safely keep or stop keeping. Modes I can pick: full (only the Keep folder and Amnesia itself survive), balanced (Keep folder, app logins through the vault), light (apps keep their data in AppData: settings, logins, caches, Temp files and Edge history; my files, Desktop, Documents and Downloads are wiped), custom (my own list). Vault profiles group vault apps so I restore only what I need, for example Work and Personal. Use only app names from the report's Profile Vault section. Keep List lines are paths relative to my user folder, written with /. Never suggest removing Amnesia's own lines. At the end, give your suggestion in exactly one block like this:\n"
          + Block + "\nUse null for mode if you would not change it. Amnesia shows me every change with a checkbox, and nothing is applied until I confirm.";

    /// <summary>Prompt + report, ready to paste. The report goes in a four-backtick fence, so its own ``` blocks stay inside.</summary>
    public static string WithPrompt(string lang, string markdown) => Prompt(lang) + "\n\n````markdown\n" + markdown.TrimEnd() + "\n````\n";

    /// <summary>Saves prompt + report as "Amnesia report YYYY-MM-DD HHMM.md" in the Keep folder. Returns the full path.</summary>
    public static string Save(string text)
    {
        var dir = Conf.KeepDir;
        Directory.CreateDirectory(dir);
        var f = Path.Combine(dir, $"Amnesia report {DateTime.Now:yyyy-MM-dd HHmm}.md");
        File.WriteAllText(f, text);
        return f;
    }

    // ---------- reading the AI's answer ----------
    static readonly Regex Tag = new("^[A-Za-z][A-Za-z0-9_-]*:", RegexOptions.Compiled);

    /// <summary>One Keep List line from an AI (or a paste), checked: a path inside the user folder, written with /.
    /// Returns the clean line, or null with why: empty, control, absolute, tag, too-long, dots, amnesia, too-wide, in-keep.</summary>
    public static string? CheckLine(string raw, out string why)
    {
        why = "";
        var s = (raw ?? "").Trim();
        if (s.Any(char.IsControl)) { why = "control"; return null; }
        var home = Home.User.Replace('\\', '/');
        var t = s.Replace('\\', '/');
        if (t.StartsWith("~/")) t = t[2..];
        else if (t.StartsWith("%USERPROFILE%", StringComparison.OrdinalIgnoreCase))
        {
            t = t[13..];
            if (t.Length > 0 && t[0] != '/') { why = "absolute"; return null; }
            t = t.TrimStart('/');
        }
        else if (t.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase)) t = t[(home.Length + 1)..];
        if (t.Length == 0) { why = "empty"; return null; }
        if (t.StartsWith('/') || t.StartsWith('~') || t.Length > 1 && t[1] == ':') { why = "absolute"; return null; }
        if (Tag.IsMatch(t) || t.Contains(':')) { why = "tag"; return null; }
        t = t.TrimEnd('/');
        if (t.Length > MaxLine) { why = "too-long"; return null; }
        var parts = t.Split('/');
        if (parts.Any(p => p is ".." or "." || p.Length == 0)) { why = "dots"; return null; }
        if (parts[0].StartsWith(".amnesia", StringComparison.OrdinalIgnoreCase) || parts[0].StartsWith(".Trash", StringComparison.OrdinalIgnoreCase)) { why = "amnesia"; return null; }
        if (parts[0].All(c => c is '*' or '?')) { why = "too-wide"; return null; }
        var keep = Conf.KeepRel;
        if (keep.Length > 0 && (t.Equals(keep, StringComparison.OrdinalIgnoreCase) || t.StartsWith(keep + "/", StringComparison.OrdinalIgnoreCase) || Wild.Like(keep, t)))
        { why = "in-keep"; return null; }
        return t;
    }

    static JsonObject Fail(string e) => new() { ["ok"] = false, ["error"] = e };
    static string Show(JsonNode? n) { var s = n is JsonValue v && v.TryGetValue<string>(out var x) ? x : n?.ToJsonString() ?? "null"; return s.Length > 120 ? s[..120] + "..." : s; }

    /// <summary>The first ```amnesia-suggestion block of an answer, checked. Nothing is applied here.</summary>
    public static JsonObject Parse(string answer)
    {
        answer ??= "";
        if (Encoding.UTF8.GetByteCount(answer) > MaxAnswer) return Fail("too-big");
        string? body = null;
        var lines = answer.Replace("\r\n", "\n").Split('\n');
        for (int i = 0; i < lines.Length && body == null; i++)
        {
            var t = lines[i].Trim();
            if (!t.StartsWith("```")) continue;
            if (!t.TrimStart('`').Trim().Equals("amnesia-suggestion", StringComparison.OrdinalIgnoreCase)) continue;
            var sb = new StringBuilder();
            for (int j = i + 1; j < lines.Length && !lines[j].Trim().StartsWith("```"); j++) sb.AppendLine(lines[j]);
            body = sb.ToString();
        }
        if (body == null) return Fail("no-block");
        JsonNode? root;
        try { root = JsonNode.Parse(body, documentOptions: new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip }); }
        catch { return Fail("bad-json"); }
        if (root is not JsonObject o) return Fail("not-object");

        var rejected = new JsonArray(); var skipped = new JsonArray(); var ignored = new JsonArray();
        void Rej(JsonArray to, JsonNode? item, string why) => to.Add(new JsonObject { ["item"] = Show(item), ["why"] = why });

        string? mode = null;
        if (o["mode"] is JsonNode mn)
        {
            if (mn is JsonValue mv && mv.TryGetValue<string>(out var ms) && Modes.Ids.Contains(ms.Trim().ToLowerInvariant())) mode = ms.Trim().ToLowerInvariant();
            else Rej(rejected, mn, "unknown-mode");
        }

        string keepText;
        try { keepText = KeepList.Check(out var kt) == null ? kt ?? "" : ""; } catch { keepText = ""; }
        var onList = keepText.Replace("\r\n", "\n").Split('\n').Select(x => x.Trim()).Where(x => x.Length > 0 && !x.StartsWith('#')).Select(KeepList.Norm).ToList();
        bool On(string l) => onList.Contains(l, StringComparer.OrdinalIgnoreCase);

        IEnumerable<JsonNode?> Items(string key)
        {
            if (o[key] is JsonArray a) return a.Take(MaxList);
            if (o[key] != null) Rej(rejected, o[key], "not-a-list");
            return Enumerable.Empty<JsonNode?>();
        }

        var add = new List<string>();
        foreach (var n in Items("keep_add"))
        {
            if (n is not JsonValue v || !v.TryGetValue<string>(out var s)) { Rej(rejected, n, "not-text"); continue; }
            var line = CheckLine(s, out var why);
            if (line == null) { Rej(rejected, n, why); continue; }
            if (On(line)) { Rej(skipped, n, "already-kept"); continue; }
            if (!add.Contains(line, StringComparer.OrdinalIgnoreCase)) add.Add(line);
        }
        var remove = new List<string>();
        foreach (var n in Items("keep_remove"))
        {
            if (n is not JsonValue v || !v.TryGetValue<string>(out var s)) { Rej(rejected, n, "not-text"); continue; }
            var line = CheckLine(s, out var why);
            if (line == null) { Rej(rejected, n, why); continue; }
            var have = onList.FirstOrDefault(x => x.Equals(line, StringComparison.OrdinalIgnoreCase));
            if (have == null) { Rej(rejected, n, "not-on-list"); continue; }
            if (!remove.Contains(have, StringComparer.OrdinalIgnoreCase)) remove.Add(have);
        }

        var vaultNames = Vault.All().Select(a => a.Name).ToList();
        var profiles = new JsonObject();
        if (o["profiles"] is JsonObject po)
        {
            int count = 0;
            foreach (var kv in po)
            {
                var name = kv.Key.Trim();
                if (name.Length is 0 or > 40 || name.Any(char.IsControl)) { Rej(rejected, kv.Key, "bad-name"); continue; }
                if (name.ToLowerInvariant() is "everything" or "semua" or "all") { Rej(rejected, kv.Key, "reserved-name"); continue; }
                if (kv.Value is not JsonArray apps) { Rej(rejected, kv.Key, "not-a-list"); continue; }
                if (profiles.Any(p => p.Key.Equals(name, StringComparison.OrdinalIgnoreCase))) { Rej(skipped, kv.Key, "duplicate"); continue; }
                if (++count > MaxProfiles) { Rej(rejected, kv.Key, "too-many"); continue; }
                var list = new List<string>();
                foreach (var an in apps.Take(MaxList))
                {
                    var s = an is JsonValue av && av.TryGetValue<string>(out var x) ? x.Trim() : null;
                    var real = s == null ? null : vaultNames.FirstOrDefault(vn => vn.Equals(s, StringComparison.OrdinalIgnoreCase));
                    if (real == null) { ignored.Add(Show(an)); continue; }
                    if (!list.Contains(real)) list.Add(real);
                }
                profiles[name] = Arr(list);
            }
        }
        else if (o["profiles"] != null) Rej(rejected, o["profiles"], "not-an-object");

        var notes = o["notes"] is JsonValue nv && nv.TryGetValue<string>(out var ns) ? new string(ns.Where(ch => ch == '\n' || !char.IsControl(ch)).ToArray()) : "";
        if (notes.Length > MaxNotes) notes = notes[..MaxNotes];

        return new JsonObject
        {
            ["ok"] = true, ["mode"] = mode, ["keep_add"] = Arr(add), ["keep_remove"] = Arr(remove), ["profiles"] = profiles,
            ["notes"] = notes, ["rejected"] = rejected, ["skipped"] = skipped, ["ignored_apps"] = ignored,
        };
    }
}
