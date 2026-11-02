// v0.10 Amnesia modes + Ask an AI tests. Run on their own fake user folder (modes-home, a subfolder of the test folder),
// so the rest of the tests never see them. Nothing outside the test folder is touched.
using System.Text.Json.Nodes;
using Amnesia.Core;

static class ModesTests
{
    public static void Run(string fake, Action<bool, string> Check, Action<string> Make, Func<string, bool> There)
    {
        Console.WriteLine("v0.10 Amnesia modes:");
        var before = Environment.GetEnvironmentVariable("AMNESIA_HOME");
        var home = Path.Combine(fake, "modes-home");
        Directory.CreateDirectory(home);
        Environment.SetEnvironmentVariable("AMNESIA_HOME", home);
        try
        {
            ModeTests(home, Check, rel => Make("modes-home/" + rel));
            Console.WriteLine("v0.10 Ask an AI:");
            AiTests(home, Check, rel => Make("modes-home/" + rel));
        }
        finally { Modes.PresetOverride = null; Environment.SetEnvironmentVariable("AMNESIA_HOME", before); }
    }

    static List<string> Wiped() => new CleanEngine().Run("logout", true).Items.Select(i => i.Path.Replace('\\', '/')).ToList();

    static void ModeTests(string home, Action<bool, string> Check, Action<string> Make)
    {
        var dir = Path.Combine(home, ".amnesia");
        var keep = Path.Combine(dir, "keep.conf");
        foreach (var f in new[] {
            "Desktop/a.txt", "Documents/b.txt", "Downloads/c.zip", "AppData/Roaming/SomeChat/s.db", "AppData/Local/Temp/t.tmp",
            "AppData/Local/Microsoft/Edge/User Data/Default/History", "AppData/Roaming/Microsoft/Windows/Recent/x.lnk",
            "AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt",
            "AppData/Local/Microsoft/Windows/Explorer/thumbcache_1.db", "AppData/LocalLow/Game/save.dat",
            ".ssh/id_ed25519", ".gitconfig", ".config/tool/x", ".bash_history", "Keep/k.txt", "MyProjects/site/index.html" })
            Make(f);
        Directory.CreateDirectory(dir);
        File.WriteAllLines(Path.Combine(dir, "settings.conf"), new[] { "LANG=en" });
        File.WriteAllText(keep, "# mine\nMyProjects\n");

        // presets
        Check(Modes.PresetLines("balanced") is { Count: 0 }, "balanced preset = today's default Keep List (empty on Windows)");
        Check(Modes.PresetLines("full") is { Count: 0 }, "full preset is empty (Windows protection is built in)");
        Check(Modes.PresetLines("light") is { Count: 21 } l && l.Contains("AppData/Roaming/*") && l.Contains(".ssh"), "light preset lines");
        Check(Modes.PresetLines("custom") == null && Modes.PresetLines("nope") == null, "custom and unknown have no preset");
        Check(Modes.Current() == "balanced", "no block yet: balanced");

        // ----- light -----
        var p = Modes.Preview("light");
        Check(p.Problem == null && p.Mode == "light" && p.From == "balanced", "light preview has no problem");
        Check(p.NewText.StartsWith("# amnesia-mode: light begin") && p.NewText.Contains("# amnesia-mode end"), "the block sits at the top");
        Check(p.NewText.Contains("\nMyProjects") && p.NewText.Contains("# mine"), "own lines and comments stay");
        Check(p.Outside.SequenceEqual(new[] { "MyProjects" }), "own lines listed for the preview");
        Check(p.Added.Contains("AppData/Roaming/*") && p.Removed.Count == 0, "added lines, none removed");
        Check(p.NewlyKept.Contains("AppData\\Roaming\\SomeChat") && p.WipeAfter < p.WipeBefore && !p.WipesMore, "dry runs: light keeps app data, wipes less");
        Check(File.ReadAllText(keep) == "# mine\nMyProjects\n", "a preview writes nothing");
        Check(!Directory.EnumerateFiles(Path.Combine(home, ".amnesia"), "keep.conf.preview-*").Any(), "the temp preview list is gone");
        Check(Modes.Commit(p), "light committed");
        Check(Modes.Current() == "light" && Conf.Get("AMNESIA_MODE") == "light", "mode is light");
        Check(File.ReadAllText(Path.Combine(dir, "history.log")).Contains("\tmode\tbalanced light 21 0"), "history: mode line");
        // what Light really does on Windows (the texts in app.js say exactly this)
        var w = Wiped();
        Check(w.Contains("Desktop/a.txt") && w.Contains("Documents/b.txt") && w.Contains("Downloads/c.zip"), "light: Desktop, Documents, Downloads are wiped");
        Check(w.Contains(".bash_history"), "light: other dot files are wiped");
        Check(!w.Any(x => x.StartsWith("AppData/Roaming/SomeChat") || x.StartsWith("AppData/LocalLow/Game")), "light: app data stays");
        Check(!w.Any(x => x.StartsWith("AppData/Local/Temp/")), "light: Temp stays (a Keep line can't leave one folder out)");
        Check(!w.Any(x => x.StartsWith("AppData/Local/Microsoft/Edge")), "light: Edge history and cookies stay");
        Check(!w.Any(x => x.Contains("/Recent/") || x.Contains("PSReadLine")), "light: recent files and PowerShell history stay (they are inside AppData)");
        Check(w.Contains("AppData/Local/Microsoft/Windows/Explorer/thumbcache_1.db"), "light: thumbnail cache is still wiped");
        Check(!w.Any(x => x.StartsWith(".ssh") || x == ".gitconfig" || x.StartsWith(".config")), "light: .ssh, .gitconfig, .config stay");
        Check(!w.Any(x => x.StartsWith("MyProjects")), "light: own line still kept");
        Check(!Modes.Commit(p) && p.Problem == "mode-changed", "an old preview can't be committed twice");

        // ----- editing the block = custom -----
        File.WriteAllText(keep, File.ReadAllText(keep).Replace(".npmrc\n", ""));
        Check(Modes.Current() == "custom", "a line removed from the block: custom");
        var stored = Conf.Get("AMNESIA_MODE");
        Check(Modes.Sync() == "custom" && Conf.Get("AMNESIA_MODE") == stored, "the Keep List page only reads: custom, settings unchanged (189)");

        // ----- balanced from there: wipes more -----
        p = Modes.Preview("balanced");
        Check(p.Problem == null && p.Mode == "balanced" && p.From == "custom", "balanced preview");
        Check(p.Removed.Contains("AppData/Roaming/*") && p.WipesMore && p.NewlyWiped.Contains("AppData\\Roaming\\SomeChat"), "balanced wipes more: warned");
        Check(!p.RemovedIdle.Contains("AppData/Roaming/*"), "190: a removed line that wipes something is not 'idle'");
        Check(Modes.LineWipes("AppData/Roaming/*", new[] { "AppData\\Roaming\\SomeChat" }), "190: line wipes an item under it");
        Check(Modes.LineWipes("AppData/Roaming/SomeChat/cfg", new[] { "AppData\\Roaming\\SomeChat" }), "190: line inside a wiped folder");
        Check(!Modes.LineWipes(".zshrc", new[] { "Desktop\\a.txt", ".zsh_history" }), "190: nothing wiped there = idle");
        Check(p.NewText.StartsWith("# amnesia-mode: balanced begin") && p.NewText.Contains("MyProjects"), "balanced block (empty) + own lines");
        Check(Modes.Commit(p) && Modes.Current() == "balanced", "balanced committed");

        // ----- full: vault auto snapshot off, back on when leaving -----
        Check(Conf.Get("VAULT_AUTO") == null, "vault auto snapshot on (default)");
        p = Modes.Preview("full", dryRun: false);
        Check(p.Settings.GetValueOrDefault("VAULT_AUTO") == "0" && p.Settings.GetValueOrDefault("AMNESIA_MODE_AUTOSNAP") == "1", "full turns auto snapshot off");
        Check(p.Outside.Contains("MyProjects") && !p.Removed.Any(), "full keeps own lines unless ticked");
        Check(Modes.Commit(p) && Conf.Get("VAULT_AUTO") == "0" && Modes.Current() == "full", "full committed");
        var tick = Modes.Preview("full", null, new[] { "MyProjects" });
        Check(tick.Removed.SequenceEqual(new[] { "MyProjects" }) && !tick.NewText.Contains("MyProjects") && tick.WipesMore && tick.Mode == "full", "a ticked own line goes, the mode stays full");
        Check(tick.NewlyWiped.Any(x => x.StartsWith("MyProjects")), "...and the preview shows it will be wiped");
        p = Modes.Preview("balanced", dryRun: false);
        Check(p.Settings.GetValueOrDefault("VAULT_AUTO") == "1" && p.Settings.GetValueOrDefault("AMNESIA_MODE_AUTOSNAP") == "0", "leaving full turns it back on");
        Check(Modes.Commit(p) && Conf.Get("VAULT_AUTO") == "1", "auto snapshot back on");
        Conf.Set("VAULT_AUTO", "0");
        p = Modes.Preview("full", dryRun: false);
        Check(!p.Settings.ContainsKey("VAULT_AUTO"), "full with auto snapshot already off changes no setting");
        Conf.Set("VAULT_AUTO", null);

        // ----- a ticked preset line turns the target into custom -----
        File.AppendAllText(keep, ".ssh\n");
        p = Modes.Preview("light", null, new[] { ".ssh" }, dryRun: false);
        Check(p.Mode == "custom" && p.Note == "to-custom", "ticking a preset line: custom");
        Check(!p.NewText.Contains("# amnesia-mode") && p.NewText.Contains("AppData/Roaming/*") && !p.NewText.Contains(".ssh\n"), "custom: no markers, the line is gone");

        // ----- custom keeps the same list -----
        Modes.Commit(Modes.Preview("light", dryRun: false));
        p = Modes.Preview("custom", dryRun: false);
        Check(p.Mode == "custom" && p.Added.Count == 0 && p.Removed.Count == 0 && !p.NewText.Contains("# amnesia-mode") && !p.NewText.Contains(Modes.Explain), "custom: markers go, the lines stay");
        Check(Modes.Commit(p) && Modes.Current() == "custom" && Conf.Get("AMNESIA_MODE") == "custom", "custom committed");

        // ----- extra lines (from an AI) are checked -----
        p = Modes.Preview("balanced", new[] { "Projects/site", "../x", "C:/Windows", ".amnesia/x", "Keep/a" }, dryRun: false);
        Check(p.Added.Contains("Projects/site") && !p.Added.Any(x => x.Contains("..") || x.Contains(':') || x.StartsWith(".amnesia") || x.StartsWith("Keep")), "extra lines: only safe ones");
        Check(p.NewText.TrimEnd().EndsWith("Projects/site"), "extra lines go below the block");

        // ----- safety -----
        var good = "# amnesia-mode: light begin\nAppData/Roaming/*\n# amnesia-mode end\nMine\n";
        foreach (var bad in new[] {
            "# amnesia-mode: light begin\n# amnesia-mode: light begin\nx\n# amnesia-mode end\n",
            "# amnesia-mode: light begin\nx\n",
            "# amnesia-mode end\nx\n# amnesia-mode: light begin\n",
            "# amnesia-mode: weird begin\nx\n# amnesia-mode end\n",
            "# amnesia-mode something\nx\n" })
        {
            File.WriteAllText(keep, bad);
            var b = Modes.Preview("balanced");
            Check(b.Problem == "mode-broken" && !Modes.Commit(b) && File.ReadAllText(keep) == bad && Modes.Current() == "custom", "damaged block: nothing changes (" + bad.Split('\n')[0] + ")");
        }
        File.WriteAllText(keep, good);
        Check(Modes.BlockOk() && Modes.Own().SequenceEqual(new[] { "Mine" }), "block ok, own lines");
        Modes.PresetOverride = id => id == "light" ? null : id == "balanced" ? Array.Empty<string>() : null;
        p = Modes.Preview("light");
        Check(p.Problem == "mode-preset" && File.ReadAllText(keep) == good, "missing preset: the Keep List is not changed");
        Modes.PresetOverride = id => id == "light" ? new[] { "# only a comment" } : Array.Empty<string>();
        p = Modes.Preview("light");
        Check(p.Problem == "mode-preset" && !Modes.Commit(p) && File.ReadAllText(keep) == good, "empty preset: never an empty Keep List");
        // migration: lines that are exactly a balanced line move into the new block, the rest stays
        Modes.PresetOverride = id => id switch { "balanced" => new[] { "Foo" }, "light" => new[] { "Bar" }, "full" => Array.Empty<string>(), _ => null };
        Conf.Set("AMNESIA_MODE", null);
        File.WriteAllText(keep, "Foo\nMine\n");
        Check(Modes.Current() == "balanced", "no block, every balanced line there: balanced");
        p = Modes.Preview("balanced", dryRun: false);
        Check(p.NewText == $"# amnesia-mode: balanced begin\n{Modes.Explain}\nFoo\n# amnesia-mode end\nMine\n" && p.Outside.SequenceEqual(new[] { "Mine" }), "migration moves the balanced line into the block");
        Modes.PresetOverride = null;
        File.WriteAllText(keep, good);
        Check(Modes.Preview("max").Problem == "mode-unknown", "unknown mode refused");
        // a stopped Keep List: nothing happens
        File.Copy(keep, keep + ".last", true);
        File.Delete(keep);
        p = Modes.Preview("balanced");
        Check(p.Problem == "mode-stopped" && !File.Exists(keep), "Keep List missing (stopped): the mode is not changed");
        File.Copy(keep + ".last", keep);
        p = Modes.Preview("balanced", dryRun: false);
        File.WriteAllText(keep, good + "Another\n");
        Check(!Modes.Commit(p) && p.Problem == "mode-changed" && File.ReadAllText(keep) == good + "Another\n", "Keep List changed since the preview: refused");
        File.WriteAllText(keep, "# mine\nMyProjects\n");
        Conf.Set("AMNESIA_MODE", null);
    }

    static void AiTests(string home, Action<bool, string> Check, Action<string> Make)
    {
        Make("Documents/SecretSub/secretname.txt");
        Make("PrivateClient/plan.txt");
        Make("AppData/Roaming/Signal/db.sqlite");
        Make("AppData/Roaming/HushApp/x");
        Make("looseFile.txt");
        File.AppendAllText(Path.Combine(home, ".amnesia/history.log"), "2026-10-26 10:00:00\tclean\tlogout 12 4096\n");
        Modes.Commit(Modes.Preview("light", dryRun: false));
        File.AppendAllText(Path.Combine(home, ".amnesia/keep.conf"), "PrivateClient/Contracts\n");

        var r = AiReport.Build(false, () => new[] { "Zoom", "Firefox", "Zoom" });
        Check(AiReport.Size(1_500_000) == "1.5 MB" && AiReport.Size(999) == "999 B" && AiReport.Size(2_000_000_000) == "2 GB", "194: decimal sizes like the app");
        var md = AiReport.Markdown(r);
        var json = r.ToJsonString();
        Check(r["schema"]?.ToString() == "amnesia-report/1" && r["platform"]?.ToString() == "windows", "report: schema and platform");
        Check(r["amnesia"]?["mode"]?.ToString() == "light" && r["amnesia"]?["keep_list"]?.ToString() == "ok", "report: mode and Keep List state");
        Check(r["amnesia"]?["last_cleanup"]?["items"]?.GetValue<int>() == 12 && r["amnesia"]?["last_cleanup"]?["kb"]?.GetValue<long>() == 4, "report: last cleanup from history");
        Check(r["keep_list"]?["mode_block"]?["mode"]?.ToString() == "light" && (r["keep_list"]?["own"] as JsonArray)!.Any(x => x!.ToString() == "PrivateClient/Contracts"), "report: mode lines and own lines");
        Check(md.Contains("# (from mode light)") && md.Contains("PrivateClient/Contracts"), "markdown: Keep List block");
        Check(md.Contains("| PrivateClient |") && md.Contains("| HushApp | AppData\\Roaming |") && md.Contains("Signal"), "markdown: top level and app data folders shown");
        Check(md.Contains("Zoom, Firefox") || md.Contains("Firefox, Zoom"), "installed apps listed once");
        Check(md.Contains("loose files") && r["home_loose_files"]?["count"]?.GetValue<int>() >= 1, "loose files counted, not named");
        foreach (var s in new[] { "secretname", "SecretSub", "plan.txt", "looseFile", "index.html", "k.txt" })
            Check(!md.Contains(s) && !json.Contains(s), $"report never names files or sub folders ({s})");
        foreach (var h in new[] { "## System", "## Keep List", "## Profile Vault", "## Vault profiles", "## Home folder", "## App data folders", "## Installed apps", "## What gets deleted at the next sign out", "## Care overview" })
            Check(md.Contains(h), "markdown section " + h);

        var rh = AiReport.Build(true);
        var mh = AiReport.Markdown(rh);
        Check(!mh.Contains("PrivateClient") && !mh.Contains("HushApp") && !mh.Contains("MyProjects") && mh.Contains("folder 1"), "hide names: own folders, app data and own lines hidden");
        Check(mh.Contains("| Documents |") && mh.Contains("| Signal |") && mh.Contains("AppData/Roaming/*"), "hide names: standard folders, vault apps and mode lines stay");
        Check(mh.Contains("line 1 (path)") && rh["keep_dir"]?["path"]?.ToString() == "(hidden)" && mh.Contains("Folder names: hidden"), "hide names: own lines and Keep path hidden");
        // v0.10: a vault folder deeper than the top level is never named, also not in the vault profiles section
        Make("PrivateClient/DeepCase/a.txt");
        var deep = Vault.AddFolder("PrivateClient/DeepCase");
        VaultProfiles.Save(null, "Clients", new[] { Vault.FolderPrefix + deep });
        var rd = AiReport.Markdown(AiReport.Build(false));
        Check(deep != null && !rd.Contains("DeepCase") && rd.Contains("- Clients: " + Vault.FolderPrefix + "folder 1"), "a vault folder below the top level is not named in vault profiles");
        Vault.RemoveFolder(Vault.FolderPrefix + deep);
        try { File.Delete(VaultProfiles.File); } catch { }

        Check(AiReport.Prompt("en").Contains("```amnesia-suggestion") && AiReport.Prompt("id").Contains("```amnesia-suggestion") && AiReport.Prompt("id").Contains("Bahasa Indonesia"), "prompt in both languages, same block");
        var full = AiReport.WithPrompt("en", md);
        Check(full.Contains("````markdown") && full.TrimEnd().EndsWith("````"), "prompt + report in one fence");
        var saved = AiReport.Save(full);
        Check(File.Exists(saved) && Path.GetDirectoryName(saved) == Path.Combine(home, "Keep") && Path.GetFileName(saved).StartsWith("Amnesia report "), "saved in the Keep folder");

        // ----- the answer -----
        Check(AiReport.Parse("no block here")["error"]?.ToString() == "no-block", "parse: no block");
        Check(AiReport.Parse("```amnesia-suggestion\n{nope\n```")["error"]?.ToString() == "bad-json", "parse: bad json");
        Check(AiReport.Parse("```amnesia-suggestion\n[1,2]\n```")["error"]?.ToString() == "not-object", "parse: not an object");
        Check(AiReport.Parse(new string('x', 70_000))["error"]?.ToString() == "too-big", "parse: too big");
        Check(AiReport.Parse("```json\n{}\n```\n```Amnesia-Suggestion\n{\"mode\":null}\n```")["ok"]?.GetValue<bool>() == true, "parse: the block's name in any case, other blocks skipped");
        var answer = "Here you go.\n```amnesia-suggestion\n" + new JsonObject
        {
            ["mode"] = "balanced",
            ["keep_add"] = new JsonArray("~/Projects", "C:\\Windows", "../etc", "Docs/../x", ".amnesia/x", ".amnesia-trash", "Keep/stuff", "*", "*/foo",
                "app:Foo", "a\u0001b", "PrivateClient/Contracts", "%USERPROFILE%\\Music\\Band", "\\\\server\\share", "/etc", "Projects", new string('a', 301), 5),
            ["keep_remove"] = new JsonArray("PrivateClient\\Contracts", "NotThere", "AppData/Roaming/*"),
            ["profiles"] = new JsonObject { ["Work"] = new JsonArray("chrome", "Claude", "FakeApp"), ["Semua"] = new JsonArray(), ["  "] = new JsonArray(), ["Personal"] = new JsonArray("Signal") },
            ["notes"] = "<b>hi</b>\u0007",
            ["extra"] = 1,
        }.ToJsonString() + "\n```\nmore text";
        var a = AiReport.Parse(answer);
        string[] Ls(string k) => (a[k] as JsonArray)!.Select(x => x!.ToString()).ToArray();
        string? Why(string item) => (a["rejected"] as JsonArray)!.Concat((a["skipped"] as JsonArray)!).OfType<JsonObject>().FirstOrDefault(x => x["item"]?.ToString() == item)?["why"]?.ToString();
        Check(a["ok"]?.GetValue<bool>() == true && a["mode"]?.ToString() == "balanced", "parse: ok, mode");
        Check(Ls("keep_add").SequenceEqual(new[] { "Projects", "Music/Band" }), "parse: only safe new lines, cleaned (" + string.Join(",", Ls("keep_add")) + ")");
        Check(Why("C:\\Windows") == "absolute" && Why("/etc") == "absolute" && Why("\\\\server\\share") == "absolute", "parse: absolute paths rejected");
        Check(Why("../etc") == "dots" && Why("Docs/../x") == "dots", "parse: .. rejected");
        Check(Why(".amnesia/x") == "amnesia" && Why(".amnesia-trash") == "amnesia", "parse: Amnesia's own folders rejected");
        Check(Why("Keep/stuff") == "in-keep", "parse: inside the Keep folder rejected");
        Check(Why("*") == "too-wide" && Why("*/foo") == "too-wide", "parse: wildcard-only first part rejected");
        Check(Why("app:Foo") == "tag" && Why("a\u0001b") == "control" && Why("5") == "not-text", "parse: tags, control characters, not text");
        Check((a["rejected"] as JsonArray)!.OfType<JsonObject>().Any(x => x["why"]?.ToString() == "too-long"), "parse: too long rejected");
        Check(Why("PrivateClient/Contracts") == "already-kept", "parse: already on the list skipped");
        Check(Ls("keep_remove").SequenceEqual(new[] { "PrivateClient/Contracts", "AppData/Roaming/*" }) && Why("NotThere") == "not-on-list", "parse: remove only lines on the list");
        var prof = a["profiles"] as JsonObject;
        Check(prof!.Count == 2 && (prof["Work"] as JsonArray)!.Select(x => x!.ToString()).SequenceEqual(new[] { "Chrome", "Claude" }), "parse: profile apps from the vault list only");
        Check(Ls("ignored_apps").SequenceEqual(new[] { "FakeApp" }) && Why("Semua") == "reserved-name" && Why("  ") == "bad-name", "parse: unknown apps ignored, reserved names rejected");
        Check(a["notes"]?.ToString() == "<b>hi</b>", "parse: notes are plain text, control characters gone");
        var bad = AiReport.Parse("```amnesia-suggestion\n{\"mode\":\"max\",\"keep_add\":\"x\"}\n```");
        Check(bad["mode"] == null && (bad["rejected"] as JsonArray)!.OfType<JsonObject>().Any(x => x["why"]?.ToString() == "unknown-mode"), "parse: unknown mode rejected");
        var many = new JsonObject(); for (int i = 0; i < 12; i++) many["P" + i] = new JsonArray();
        Check((AiReport.Parse("```amnesia-suggestion\n" + new JsonObject { ["profiles"] = many }.ToJsonString() + "\n```")["profiles"] as JsonObject)!.Count == 10, "parse: at most 10 profiles");

        // applying goes through the mode preview: the ticked lines, checked again
        var pv = Modes.Preview("light", Ls("keep_add"), new[] { "PrivateClient/Contracts" }, dryRun: false);
        Check(pv.Problem == null && pv.Added.SequenceEqual(new[] { "Projects", "Music/Band" }) && pv.Removed.SequenceEqual(new[] { "PrivateClient/Contracts" }) && pv.WipesMore, "suggestion applied through the mode preview");
        var before = File.ReadAllText(Path.Combine(home, ".amnesia/keep.conf"));
        Check(before.Contains("PrivateClient/Contracts"), "nothing applied before the confirm");
        Check(Modes.Commit(pv) && Modes.Current() == "light" && !File.ReadAllText(Path.Combine(home, ".amnesia/keep.conf")).Contains("PrivateClient"), "confirmed: applied, still light");
    }
}
