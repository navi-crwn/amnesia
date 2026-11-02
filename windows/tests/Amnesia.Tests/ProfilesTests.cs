// v0.10 vault profiles tests. Run on their own fake user folder (profiles-home, a subfolder of the test folder), so the
// rest of the tests never see them. Nothing outside the test folder is touched.
using Amnesia.Core;

static class ProfilesTests
{
    public static void Run(string fake, Action<bool, string> Check, Action<string> Make, Func<string, bool> There)
    {
        Console.WriteLine("v0.10 vault profiles:");
        var before = Environment.GetEnvironmentVariable("AMNESIA_HOME");
        var home = Path.Combine(fake, "profiles-home");
        Directory.CreateDirectory(Path.Combine(home, ".amnesia"));
        Environment.SetEnvironmentVariable("AMNESIA_HOME", home);
        try { Tests(home, Check, rel => Make("profiles-home/" + rel), rel => There("profiles-home/" + rel)); }
        finally { Environment.SetEnvironmentVariable("AMNESIA_HOME", before); }
    }

    static void Tests(string home, Action<bool, string> Check, Action<string> Make, Func<string, bool> There)
    {
        string F(string rel) => Path.Combine(home, rel.Replace('/', Path.DirectorySeparatorChar));
        string Read(string rel) => File.ReadAllText(F(rel));
        void Put(string rel, string text) { Directory.CreateDirectory(Path.GetDirectoryName(F(rel))!); File.WriteAllText(F(rel), text); }
        bool Throws(Action a, string code) { try { a(); return false; } catch (InvalidOperationException e) { return e.Message == code; } }
        List<string> Ids() => VaultProfiles.All().Select(p => p.Id).ToList();
        VaultProfile? P(string id) => VaultProfiles.All().FirstOrDefault(p => p.Id == id);

        File.WriteAllLines(F(".amnesia/settings.conf"), new[] { "LANG=en" });
        Put("AppData/Roaming/Claude/config.json", "claude-v1");
        Put(".claude/settings.json", "code-v1");
        Put("AppData/Local/Google/Chrome/User Data/Default/Login Data", "chrome-v1");
        Put("AppData/Roaming/Telegram Desktop/tdata/key", "tg-v1");
        Put("AppData/Roaming/Mozilla/Firefox/profiles.ini", "ff-v1");

        // ---------- built-ins ----------
        var all = VaultProfiles.All();
        Check(all.Count == 3 && all[0].Id == "all" && all[0].Name == "Everything" && all[1].Id == "work" && all[2].Id == "personal",
            "no file: Everything first, then the built-ins Work and Personal");
        Check(all.All(p => p.BuiltIn), "no file: all of them are built-in");
        Check(P("work")!.Apps.SequenceEqual(new[] { "Claude", "Claude Code", "Chrome" }), "Work holds only the work apps on this PC");
        Check(P("personal")!.Apps.SequenceEqual(new[] { "Telegram", "Firefox" }), "Personal holds the chat apps and the second browser on this PC");
        Check(!File.Exists(VaultProfiles.File), "nothing is written before the first save");
        Check(VaultProfiles.Shared().Count == 0, "the built-ins share no app");
        Conf.Set("LANG", "id");
        Check(P("all")!.Name == "Semua" && P("work")!.Name == "Kerja" && P("personal")!.Name == "Santai", "built-in names follow the language (Indonesian)");
        Conf.Set("LANG", "en");
        Check(VaultProfiles.Last == "all", "last profile: Everything by default");
        VaultProfiles.Last = "all";
        Check(!File.Exists(VaultProfiles.File), "189: picking Everything writes no file");
        VaultProfiles.Last = "work";
        Check(VaultProfiles.Last == "work" && File.Exists(VaultProfiles.File), "the last profile is remembered");
        Check(VaultProfiles.All().Skip(1).All(p => p.BuiltIn), "remembering the last profile does not turn the built-ins into stored ones");
        VaultProfiles.Last = "nope";
        Check(VaultProfiles.Last == "all", "a last profile that does not exist reads as Everything");

        // ---------- AppsFor / Ignored ----------
        Check(VaultProfiles.AppsFor("all") == null && VaultProfiles.AppsFor("") == null, "AppsFor: Everything means no subset (restore all)");
        Check(VaultProfiles.AppsFor("work")!.SequenceEqual(new[] { "Claude", "Claude Code", "Chrome" }), "AppsFor: a profile gives its apps");
        Check(VaultProfiles.AppsFor("gone") is { Count: 0 }, "AppsFor: an unknown profile gives an empty list, never everything");
        Check(VaultProfiles.Ignored(new[] { "Claude", "Nope", "nope" }).SequenceEqual(new[] { "Nope" }), "Ignored: names that are not vault apps");

        // ---------- save ----------
        var personal = VaultProfiles.Save("personal", "Personal", new[] { "Telegram", "Firefox", "Chrome" });
        Check(personal.Id == "personal" && personal.Apps.Count == 3 && !personal.BuiltIn, "save changes a built-in");
        Check(File.Exists(VaultProfiles.File) && Ids().SequenceEqual(new[] { "all", "work", "personal" }), "after the first save the file holds the whole list");
        Check(VaultProfiles.All().Skip(1).All(p => !p.BuiltIn), "after the first save nothing is built-in any more");
        var sh = VaultProfiles.Shared();
        Check(sh.Count == 1 && sh.ContainsKey("Chrome") && sh["Chrome"].SequenceEqual(new[] { "work", "personal" }), "shared: Chrome is in Work and Personal");
        Check(VaultProfiles.Last == "all", "a save keeps the last profile as it was");

        var mine = VaultProfiles.Save(null, "  My Stuff ", new[] { "claude", "Nope", "Claude", "Folder: nowhere" });
        Check(mine.Id == "my-stuff" && mine.Name == "My Stuff", "new profile: id made from the name, name trimmed");
        Check(mine.Apps.SequenceEqual(new[] { "Claude" }), "new profile: unknown apps dropped, duplicates removed, names as the vault writes them");
        var mine2 = VaultProfiles.Save(null, "My stuff.", new[] { "Git" });
        Check(mine2.Id == "my-stuff-2", "a second profile with the same id gets its own id");
        Check(Throws(() => VaultProfiles.Save(null, "my stuff", new[] { "Claude" }), "profile-name-taken"), "the same name twice is refused");
        Check(Throws(() => VaultProfiles.Save(null, "Semua", new string[0]), "profile-name-reserved")
            && Throws(() => VaultProfiles.Save(null, "everything", new string[0]), "profile-name-reserved")
            && Throws(() => VaultProfiles.Save(null, "ALL", new string[0]), "profile-name-reserved"), "Everything / Semua / all are reserved names");
        Check(Throws(() => VaultProfiles.Save(null, "   ", new string[0]), "profile-name")
            && Throws(() => VaultProfiles.Save(null, new string('x', 41), new string[0]), "profile-name")
            && Throws(() => VaultProfiles.Save(null, "two\nlines", new string[0]), "profile-name"), "an empty, too long or two-line name is refused");
        var renamed = VaultProfiles.Save("my-stuff", "Banking", new[] { "Firefox" });
        Check(renamed.Id == "my-stuff" && P("my-stuff")!.Name == "Banking" && P("my-stuff")!.Apps.SequenceEqual(new[] { "Firefox" }), "rename keeps the id");
        Check(VaultProfiles.Shared()["Firefox"].SequenceEqual(new[] { "personal", "my-stuff" }), "shared: Firefox in Personal and Banking");
        Check(Throws(() => VaultProfiles.Save("my-stuff-2", "Banking", new string[0]), "profile-name-taken"), "rename to a name that is taken is refused");
        var text = Read(".amnesia/profiles.json");
        Check(text.Contains("\"version\": 1") && !text.Contains("v1") && !text.Contains("correct horse"), "profiles.json holds names and app names only");
        Check(!File.Exists(VaultProfiles.File + ".tmp"), "the file is written through a temp file and a rename");

        // ---------- delete ----------
        VaultProfiles.Last = "my-stuff-2";
        Check(VaultProfiles.Delete("my-stuff-2") && VaultProfiles.Last == "all", "delete; the last profile falls back to Everything");
        Check(!VaultProfiles.Delete("all") && !VaultProfiles.Delete("gone") && Ids()[0] == "all", "Everything can't be deleted, an unknown one does nothing");
        Check(VaultProfiles.Delete("work") && !Ids().Contains("work"), "a built-in can be deleted");
        Conf.Set("LANG", "id");
        Check(!Ids().Contains("work") && P("all")!.Name == "Semua", "a deleted built-in stays deleted (also after a language change)");
        Conf.Set("LANG", "en");

        // ---------- damaged file ----------
        var good = Read(".amnesia/profiles.json");
        File.WriteAllText(VaultProfiles.File, "{ not json");
        Check(Ids().SequenceEqual(new[] { "all", "work", "personal" }), "a damaged file: the built-ins are shown");
        Check(VaultProfiles.Last == "all", "a damaged file: last is Everything");
        VaultProfiles.Save(null, "Fresh", new[] { "Claude" });
        Check(File.Exists(VaultProfiles.File + ".bad") && Read(".amnesia/profiles.json.bad") == "{ not json", "a damaged file is kept as profiles.json.bad before it is replaced");
        File.WriteAllText(VaultProfiles.File, good);
        File.WriteAllText(VaultProfiles.File, "{\"version\":1,\"profiles\":[{\"id\":\"BAD ID\",\"name\":\"x\",\"apps\":[]},{\"id\":\"all\",\"name\":\"y\",\"apps\":[]},{\"id\":\"ok\",\"name\":\"Ok\",\"apps\":[\"Claude\",\"Claude\",5]}]}");
        Check(Ids().SequenceEqual(new[] { "all", "ok" }) && P("ok")!.Apps.SequenceEqual(new[] { "Claude" }), "rows with a bad id or the reserved id are skipped");
        File.WriteAllText(VaultProfiles.File, good);

        // ---------- restore only a profile ----------
        Vault.Create("correct horse battery", "");
        var saved = Vault.Snapshot(new[] { "Claude", "Claude Code", "Telegram" });
        Check(saved.Count == 3, "snapshot of three apps");
        Put("AppData/Roaming/Claude/config.json", "claude-v2");
        Put(".claude/settings.json", "code-v2");
        Put("AppData/Roaming/Telegram Desktop/tdata/key", "tg-v2");
        VaultProfiles.Save(null, "Work again", new[] { "Claude", "Claude Code", "Chrome" });
        var workId = VaultProfiles.All().First(p => p.Name == "Work again").Id;
        var back = Vault.Restore("correct horse battery", VaultProfiles.AppsFor(workId));
        Check(back.OrderBy(x => x).SequenceEqual(new[] { "Claude", "Claude Code" }), "restore a profile: only its apps with a snapshot come back (Chrome has none)");
        Check(Read("AppData/Roaming/Claude/config.json") == "claude-v1" && Read(".claude/settings.json") == "code-v1", "restore a profile: its apps are back");
        Check(Read("AppData/Roaming/Telegram Desktop/tdata/key") == "tg-v2", "restore a profile: other apps are not touched");
        var onlyChrome = VaultProfiles.Save(null, "Browser", new[] { "Chrome" });
        try { Vault.Restore("correct horse battery", VaultProfiles.AppsFor(onlyChrome.Id)); Check(false, "profile with no snapshot"); }
        catch (VaultError e) { Check(e.Code == "no-snapshot" && Vault.Attempts == 0, "a profile with no snapshot: nothing is restored and no password try is used"); }
        try { Vault.Restore("correct horse battery", VaultProfiles.AppsFor("gone")); Check(false, "unknown profile"); }
        catch (VaultError e) { Check(e.Code == "no-snapshot", "an unknown profile restores nothing (never everything)"); }
        var everything = Vault.Restore("correct horse battery", VaultProfiles.AppsFor("all"));
        Check(everything.Count == 3 && Read("AppData/Roaming/Telegram Desktop/tdata/key") == "tg-v1", "Everything: the restore-all path still restores every app");
        Check(There(".amnesia/profiles.json") && !There(".amnesia/vault/profiles.json"), "profiles live next to the settings, not inside the vault");
    }
}
