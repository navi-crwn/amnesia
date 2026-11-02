// v0.10: Amnesia modes. One choice for how much is forgotten at every sign out:
//   full      Retrograde Amnesia: only the Keep folder and what Amnesia needs survive. Vault auto snapshot is switched off.
//   balanced  Selective Amnesia (recommended, the default so far): Keep folder, app logins come back from the vault.
//   light     Partial Amnesia: apps keep their data in AppData; your files, Desktop, Downloads and Documents are wiped.
//   custom    Custom Amnesia: your own Keep List (picked by itself when you change the lines a mode wrote).
// A mode writes its lines as one marked block at the top of keep.conf:
//   # amnesia-mode: <id> begin
//   # Amnesia writes the lines between these markers when you pick a mode. Put your own lines below the end marker.
//   <preset lines>
//   # amnesia-mode end
// Lines outside the block are the user's own and are never removed, except the ones the user ticks in the preview.
// Every switch is a preview first (two dry runs: now and with the new list), then a commit that checks the Keep List
// did not change in between. A missing or broken preset, a damaged block or a Keep List that can't be read changes
// nothing. Nothing is deleted when you switch: it counts from the next sign out.
// Same rules as the Mac (Keep.applyMode / commitMode in app/Amnesia.swift).
namespace Amnesia.Core;

/// <summary>v0.10: what switching to a mode would do. Problem and Note are codes; the page turns them into text.</summary>
public sealed class ModePreview
{
    /// <summary>The mode the user asked for.</summary>
    public string Asked { get; set; } = "";
    /// <summary>The mode it ends up as ("custom" when a ticked line belongs to the preset).</summary>
    public string Mode { get; set; } = "";
    public string From { get; set; } = "";
    public string OldText { get; set; } = "";
    public string NewText { get; set; } = "";
    /// <summary>Keep List lines that are new / gone (normalized paths).</summary>
    public List<string> Added { get; set; } = new();
    public List<string> Removed { get; set; } = new();
    /// <summary>The user's own lines (outside the block), as they are now. The page shows them with a checkbox.</summary>
    public List<string> Outside { get; set; } = new();
    /// <summary>From the two dry runs: items the next sign out wipes now but did not before, and the other way round.</summary>
    public List<string> NewlyWiped { get; set; } = new();
    public List<string> NewlyKept { get; set; } = new();
    public int WipeBefore { get; set; } = -1;
    public int WipeAfter { get; set; } = -1;
    /// <summary>Settings the commit writes (AMNESIA_MODE, VAULT_AUTO, AMNESIA_MODE_AUTOSNAP).</summary>
    public Dictionary<string, string> Settings { get; set; } = new();
    public bool WipesMore { get; set; }
    /// <summary>v0.10 (item 190): removed lines where the new dry run wipes nothing (already covered by another line,
    /// or nothing there). The page lists them apart instead of under "will now be wiped".</summary>
    public List<string> RemovedIdle { get; set; } = new();
    /// <summary>null, or: mode-lab, mode-stopped, mode-broken, mode-preset, mode-unknown, mode-changed, mode-write.</summary>
    public string? Problem { get; set; }
    /// <summary>null, or "to-custom" (a ticked line is part of the preset, so the result is Custom).</summary>
    public string? Note { get; set; }
}

public static class Modes
{
    public static readonly string[] Ids = { "full", "balanced", "light", "custom" };

    public const string BeginPrefix = "# amnesia-mode:";
    public const string EndLine = "# amnesia-mode end";
    public const string Explain = "# Amnesia writes the lines between these markers when you pick a mode. Put your own lines below the end marker.";

    // ---------- presets (embedded; the Mac has presets/<id>.conf) ----------
    // balanced: today's default Windows Keep List is empty, logins come back from the vault.
    static readonly string[] Balanced = Array.Empty<string>();
    // full: empty too. It differs from balanced by the vault auto snapshot (switched off) and by the preview offering to
    // stop keeping your own lines. Windows protection (Keep, .amnesia, sign in) is built into the cleanup.
    static readonly string[] Full = Array.Empty<string>();
    // light: app data and tool settings stay where they are.
    static readonly string[] Light =
    {
        "AppData/Roaming/*",
        "AppData/Local/*",
        "AppData/LocalLow/*",
        ".ssh",
        ".gitconfig",
        ".git-credentials",
        ".config",
        ".local",
        ".claude",
        ".claude.json",
        ".gemini",
        ".codex",
        ".vscode",
        ".cursor",
        ".antigravity",
        ".windsurf",
        ".codeium",
        ".aws",
        ".kube",
        ".docker",
        ".npmrc",
    };

    /// <summary>For the tests: replaces a preset (null = the embedded one). Lets a test show that a missing preset
    /// never empties the Keep List.</summary>
    public static Func<string, IReadOnlyList<string>?>? PresetOverride { get; set; }

    /// <summary>The dry runs use this engine (Amnesia.exe gives one that knows the cloud folders).</summary>
    public static Func<CleanEngine> NewEngine { get; set; } = () => new CleanEngine();

    /// <summary>The lines of a preset, or null for "custom", an unknown id, or a preset that can't be used.</summary>
    public static IReadOnlyList<string>? PresetLines(string id)
    {
        IReadOnlyList<string>? l;
        if (PresetOverride != null) l = PresetOverride(id);
        else l = id switch { "full" => Full, "balanced" => Balanced, "light" => Light, _ => null };
        if (l == null) return null;
        // light is never empty on purpose: an empty one means it broke
        if (id == "light" && !l.Any(x => !IsComment(x))) return null;
        return l;
    }

    static bool IsComment(string l) { var t = l.Trim(); return t.Length == 0 || t.StartsWith('#'); }
    static string Key(string l) => KeepList.Norm(l).ToLowerInvariant();

    // ---------- the block ----------
    sealed class Parsed
    {
        public bool Broken;
        public bool Has;
        public string Id = "";
        /// <summary>Lines inside the block (markers left out).</summary>
        public List<string> Inside = new();
        /// <summary>Every other line, in order.</summary>
        public List<string> Outside = new();
    }

    static string[] SplitLines(string text)
    {
        if (text.Length == 0) return Array.Empty<string>();
        var l = text.Replace("\r\n", "\n").Split('\n').ToList();
        if (l.Count > 0 && l[^1].Length == 0) l.RemoveAt(l.Count - 1);
        return l.ToArray();
    }

    static bool IsBegin(string t, out string id)
    {
        id = "";
        if (!t.StartsWith(BeginPrefix, StringComparison.Ordinal) || !t.EndsWith(" begin", StringComparison.Ordinal)) return false;
        id = t[BeginPrefix.Length..^" begin".Length].Trim();
        return true;
    }

    static Parsed Parse(string text)
    {
        var p = new Parsed();
        int begins = 0, ends = 0, at = 0; // at: 0 before, 1 inside, 2 after
        foreach (var raw in SplitLines(text))
        {
            var t = raw.Trim();
            if (t.StartsWith("# amnesia-mode", StringComparison.Ordinal))
            {
                if (IsBegin(t, out var id))
                {
                    begins++;
                    if (at != 0 || !Ids.Contains(id) || id == "custom") p.Broken = true;
                    p.Id = id; at = 1;
                }
                else if (t == EndLine)
                {
                    ends++;
                    if (at != 1) p.Broken = true;
                    at = 2;
                }
                else p.Broken = true; // a marker we don't know: we can't tell where the block is
                continue;
            }
            if (at == 1) p.Inside.Add(raw); else p.Outside.Add(raw);
        }
        if (begins == 0 && ends == 0) return p; // no block (Broken stays set for an unknown marker)
        if (begins != 1 || ends != 1 || at != 2) p.Broken = true;
        p.Has = !p.Broken;
        return p;
    }

    static List<string> Lines(IEnumerable<string> l) => l.Where(x => !IsComment(x)).Select(x => x.Trim()).ToList();

    /// <summary>Is the block in keep.conf OK? (true also when there is none.)</summary>
    public static bool BlockOk()
    {
        try { return KeepList.Check(out var t) != null || !Parse(t ?? "").Broken; } catch { return false; }
    }

    /// <summary>The mode the Keep List is in now: the block's mode when its lines are exactly the preset, else custom.
    /// Without a block: custom when AMNESIA_MODE=custom, balanced when every balanced line is there, else custom.</summary>
    public static string Current()
    {
        string? text;
        try { if (KeepList.Check(out text) != null) return Conf.Get("AMNESIA_MODE") is { } m && Ids.Contains(m) ? m : "custom"; }
        catch { return "custom"; }
        return CurrentOf(text ?? "");
    }

    static string CurrentOf(string text)
    {
        var p = Parse(text);
        if (p.Broken) return "custom";
        if (p.Has)
        {
            var pl = PresetLines(p.Id);
            if (pl == null) return "custom";
            var want = Lines(pl);
            return Lines(p.Inside).SequenceEqual(want) ? p.Id : "custom";
        }
        if (Conf.Get("AMNESIA_MODE") == "custom") return "custom";
        var bal = PresetLines("balanced");
        if (bal == null) return "custom";
        var have = Lines(p.Outside).Select(Key).ToHashSet();
        return Lines(bal).All(b => have.Contains(Key(b))) ? "balanced" : "custom";
    }

    /// <summary>The user's own lines (outside the block, comments left out).</summary>
    public static List<string> Own()
    {
        try
        {
            if (KeepList.Check(out var t) != null) return new();
            var p = Parse(t ?? "");
            return p.Broken ? new() : Lines(OutsideAfterMigration(p));
        }
        catch { return new(); }
    }

    /// <summary>The lines inside the block (comments left out), or empty.</summary>
    public static (string? id, List<string> lines) BlockLines()
    {
        try
        {
            if (KeepList.Check(out var t) != null) return (null, new());
            var p = Parse(t ?? "");
            return p.Has ? (p.Id, Lines(p.Inside)) : (null, new());
        }
        catch { return (null, new()); }
    }

    // without a block yet: lines that are exactly a balanced preset line move into the new block
    static List<string> OutsideAfterMigration(Parsed p)
    {
        if (p.Has) return p.Outside;
        var bal = (PresetLines("balanced") ?? Array.Empty<string>()).Where(x => !IsComment(x)).Select(x => x.Trim()).ToHashSet(StringComparer.Ordinal);
        return p.Outside.Where(l => !bal.Contains(l.Trim())).ToList();
    }

    // ---------- preview + commit ----------
    /// <summary>What switching to this mode would do. Writes nothing. extraAdd: lines to add as your own (checked with
    /// the same rules as an AI suggestion; bad ones are dropped). extraRemove: your own lines to stop keeping. dryRun:
    /// also run the two dry runs (the page always does; some tests don't need them).</summary>
    public static ModePreview Preview(string id, IEnumerable<string>? extraAdd = null, IEnumerable<string>? extraRemove = null, bool dryRun = true)
    {
        var r = new ModePreview { Asked = id, Mode = id };
        r.From = Current();
        if (!Ids.Contains(id)) { r.Problem = "mode-unknown"; return r; }
        if (Lab.Active) { r.Problem = "mode-lab"; return r; } // the Keep List is the administrator's copy
        string? text;
        try { if (KeepList.Check(out text) != null) { r.Problem = "mode-stopped"; return r; } }
        catch { r.Problem = "mode-stopped"; return r; }
        text ??= "";
        r.OldText = text;
        var p = Parse(text);
        if (p.Broken) { r.Problem = "mode-broken"; return r; }
        IReadOnlyList<string>? preset = null;
        if (id != "custom")
        {
            preset = PresetLines(id);
            if (preset == null) { r.Problem = "mode-preset"; return r; } // never an empty list from a broken preset
        }

        var outside = OutsideAfterMigration(p);
        // the lines that were in the block (or that move into it now)
        var inside = p.Has ? p.Inside : p.Outside.Where(l => !outside.Contains(l)).ToList();
        r.Outside = Lines(outside);

        var remove = new HashSet<string>(StringComparer.Ordinal);
        var onList = Lines(SplitLines(text)).Select(Key).ToHashSet();
        foreach (var x in extraRemove ?? Enumerable.Empty<string>())
        {
            var k = Key(x ?? "");
            if (k.Length > 0 && onList.Contains(k)) remove.Add(k);
        }
        var add = new List<string>();
        foreach (var x in extraAdd ?? Enumerable.Empty<string>())
        {
            var line = AiReport.CheckLine(x ?? "", out _);
            if (line != null && !add.Any(a => Key(a) == Key(line))) add.Add(line);
        }

        // a ticked line that the preset itself has: the result can't be that preset any more
        var mode = id;
        if (preset != null && Lines(preset).Any(l => remove.Contains(Key(l)))) { mode = "custom"; r.Note = "to-custom"; }
        r.Mode = mode;

        var nl = text.Contains("\r\n") ? "\r\n" : text.Contains('\n') ? "\n" : Environment.NewLine;
        var outLines = new List<string>();
        if (mode == "custom")
        {
            // custom keeps what the block had (or the preset, when a ticked line turned it into custom), no markers
            var kept = id == "custom" ? inside : preset!.ToList();
            outLines.AddRange(kept.Where(l => l.Trim() != Explain && !(IsComment(l) == false && remove.Contains(Key(l)))));
        }
        else
        {
            outLines.Add($"{BeginPrefix} {mode} begin");
            outLines.Add(Explain);
            outLines.AddRange(preset!);
            outLines.Add(EndLine);
        }
        outLines.AddRange(outside.Where(l => IsComment(l) || !remove.Contains(Key(l))));
        var have = Lines(outLines).Select(Key).ToHashSet();
        foreach (var a in add) if (have.Add(Key(a))) outLines.Add(a);
        r.NewText = outLines.Count == 0 ? "" : string.Join(nl, outLines) + nl;

        var oldSet = Lines(SplitLines(text)).Select(KeepList.Norm).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var newSet = Lines(outLines).Select(KeepList.Norm).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        r.Added = newSet.Where(n => !oldSet.Contains(n, StringComparer.OrdinalIgnoreCase)).ToList();
        r.Removed = oldSet.Where(o => !newSet.Contains(o, StringComparer.OrdinalIgnoreCase)).ToList();

        // settings: full switches the vault auto snapshot off (and remembers it), leaving full puts it back
        r.Settings["AMNESIA_MODE"] = mode;
        if (mode == "full")
        {
            if (Conf.Get("VAULT_AUTO") != "0") { r.Settings["VAULT_AUTO"] = "0"; r.Settings["AMNESIA_MODE_AUTOSNAP"] = "1"; }
        }
        else if (Conf.Get("AMNESIA_MODE_AUTOSNAP") == "1") { r.Settings["VAULT_AUTO"] = "1"; r.Settings["AMNESIA_MODE_AUTOSNAP"] = "0"; }

        if (dryRun) DryRuns(r);
        // v0.10 (item 190): a removed line only counts as "wiped" when the new dry run really wipes something there
        if (dryRun && r.Problem == null) r.RemovedIdle = r.Removed.Where(l => !LineWipes(l, r.NewlyWiped)).ToList();
        // v0.10: anything that is wiped now but was kept before also gets the warning, even when the total stays the same
        r.WipesMore = r.Removed.Count > r.RemovedIdle.Count || r.WipeAfter > r.WipeBefore || r.NewlyWiped.Count > 0;
        return r;
    }

    /// <summary>v0.10 (item 190): does a wiped item (relative path, any slash) sit at, under or above this Keep line?</summary>
    public static bool LineWipes(string line, IEnumerable<string> wiped)
    {
        var l = KeepList.Norm(line);
        if (l.Length == 0) return false;
        var ls = l.Split('/');
        foreach (var raw in wiped)
        {
            var w = KeepList.Norm(raw);
            if (w.Length == 0) continue;
            var ws = w.Split('/');
            if (ws.Length >= ls.Length && Wild.Like(string.Join('/', ws[..ls.Length]), l)) return true;  // at or under the line
            if (ws.Length < ls.Length && Wild.Like(w, string.Join('/', ls[..ws.Length]))) return true;    // a folder above it
        }
        return false;
    }

    /// <summary>The next sign out as it is now, and as it would be with the new list (a temp copy, never keep.conf).</summary>
    static void DryRuns(ModePreview r)
    {
        var before = NewEngine().Run("logout", true);
        Directory.CreateDirectory(Home.Dir);
        var tmp = Path.Combine(Home.Dir, $"keep.conf.preview-{Guid.NewGuid():N}");
        CleanResult after;
        try
        {
            WriteFile(tmp, r.NewText);
            KeepList.PreviewFile = tmp;
            try { after = NewEngine().Run("logout", true); }
            finally { KeepList.PreviewFile = null; }
        }
        finally { try { File.Delete(tmp); } catch { } }
        // a stopped dry run lists nothing: say so instead of "0 items"
        if (before.Skipped != null || after.Skipped != null) { r.Problem ??= "mode-stopped"; return; }
        r.WipeBefore = before.Items.Count;
        r.WipeAfter = after.Items.Count;
        var b = before.Items.Select(i => i.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var a = after.Items.Select(i => i.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        r.NewlyWiped = after.Items.Select(i => i.Path).Where(x => !b.Contains(x)).ToList();
        r.NewlyKept = before.Items.Select(i => i.Path).Where(x => !a.Contains(x)).ToList();
    }

    static void WriteFile(string path, string text)
    {
        File.WriteAllText(path, text);
        if (!OperatingSystem.IsWindows()) try { File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite); } catch { }
    }

    /// <summary>Writes the previewed Keep List and settings. Refuses (Problem set, false) when anything changed since
    /// the preview, or when the Keep List can't be trusted. Temp file + rename, so a cut off write never leaves half a list.</summary>
    public static bool Commit(ModePreview p)
    {
        if (p.Problem != null) return false;
        if (Lab.Active) { p.Problem = "mode-lab"; return false; }
        string? text;
        try { if (KeepList.Check(out text) != null) { p.Problem = "mode-stopped"; return false; } }
        catch { p.Problem = "mode-stopped"; return false; }
        if ((text ?? "") != p.OldText) { p.Problem = "mode-changed"; return false; }
        var file = KeepList.File;
        var tmp = file + ".mode.tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            WriteFile(tmp, p.NewText);
            File.Move(tmp, file, overwrite: true);
        }
        catch
        {
            try { File.Delete(tmp); } catch { }
            p.Problem = "mode-write";
            return false;
        }
        foreach (var kv in p.Settings) Conf.Set(kv.Key, kv.Value);
        Home.History("mode", $"{p.From} {p.Mode} {p.Added.Count} {p.Removed.Count}");
        Home.Trace("mode", $"{p.From} -> {p.Mode} (+{p.Added.Count} -{p.Removed.Count})");
        return true;
    }

    /// <summary>The Keep List page opens: the mode the list really is (a line removed from the block makes it custom).
    /// v0.10 (item 189): only reads. settings.ini is written when you really switch mode (Commit), not when a page opens.</summary>
    public static string Sync() => Current();
}
