// Tests for Amnesia.Core on a pretend user folder in a temp folder (AMNESIA_HOME). Ported from tests\test_clean.ps1 (v0.3).
using Amnesia.Core;

var fake = Path.Combine(Path.GetTempPath(), "amnesia-test-" + Guid.NewGuid().ToString("N"));
int fails = 0;
void Check(bool ok, string what) { Console.WriteLine((ok ? "  ok    " : "  FAIL  ") + what); if (!ok) fails++; }
void Make(string rel) { var p = Path.Combine(fake, rel); Directory.CreateDirectory(Path.GetDirectoryName(p)!); File.WriteAllText(p, "x"); }
bool There(string rel) => File.Exists(Path.Combine(fake, rel)) || Directory.Exists(Path.Combine(fake, rel));
void Settings(params string[] lines) => File.WriteAllLines(Path.Combine(fake, ".amnesia/settings.conf"), lines);
var Conf2 = Path.Combine(fake, ".amnesia/keep.conf");
CleanResult Dry() => new CleanEngine().Run("now", true);
CleanResult Real(string m) => new CleanEngine().Run(m, false);
List<string> Del(CleanResult r) => r.Items.Select(i => i.Path).ToList();

Environment.SetEnvironmentVariable("AMNESIA_HOME", fake);
try
{
    foreach (var f in new[] {
        "NTUSER.DAT", "Downloads/movie.mp4", "Downloads/desktop.ini", "Desktop/notes.txt", "Documents/Projects/site/index.html",
        "Documents/Taxes/2026.pdf", "AppData/Roaming/Microsoft/Credentials/abc", "AppData/Roaming/SomeChat/session.db",
        "AppData/Roaming/Code/User/settings.json", "AppData/Roaming/Code/Cache/blob", "AppData/Local/Temp/tmp1.tmp",
        "AppData/Local/Packages/App/x", "AppData/Local/Amnesia/WebView2/x", "Keep/important.txt", "Vault2/secret.txt",
        ".ssh/id_ed25519", ".gitconfig", ".amnesia/settings.conf", "OneDrive/report.docx", "Links/Desktop.lnk",
        "Searches/Everywhere.search-ms", "Favorites/Bing.url", "Favorites/mine.url", "Pictures/Screenshots/shot.png",
        "Videos/Captures/clip.mp4", "AppData/Roaming/Microsoft/Windows/Recent/notes.lnk",
        "AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt",
        "AppData/Local/Microsoft/Windows/Explorer/thumbcache_256.db", "AppData/Local/Microsoft/Edge/User Data/Default/History",
        "AppData/Local/Microsoft/Windows/Notifications/wpndatabase.db",
        "AppData/Local/Packages/Microsoft.Windows.Search_cw5n1h2txyewy/LocalState/DeviceSearchCache/AppCache1.txt",
        "AppData/Local/Packages/Microsoft.Windows.Search_cw5n1h2txyewy/Settings/settings.dat",
        "AppData/Local/CoreAIPlatform.00/UKP/abc/ukg.db" })
        Make(f);
    Settings("LANG=id");
    File.WriteAllLines(Conf2, new[] { "# my keep list", ".ssh", "Documents\\Taxes", "AppData/Roaming/Code*/User", "keychain:whatever", "app:Something" });

    Console.WriteLine("Would be deleted:");
    var r = Dry();
    var del = Del(r);
    var keep = r.Kept;
    Check(del.Contains("Downloads\\movie.mp4"), "Downloads content");
    Check(del.Contains("Desktop\\notes.txt"), "Desktop content");
    Check(del.Contains("Documents\\Projects"), "Documents content");
    Check(del.Contains("AppData\\Roaming\\SomeChat"), "app data in Roaming");
    Check(del.Contains("AppData\\Roaming\\Code\\Cache"), "the rest of a partly kept app");
    Check(del.Contains("AppData\\Local\\Temp\\tmp1.tmp"), "Temp content gone (the Temp folder itself stays)");
    Check(del.Contains("Vault2"), "a folder that only looks like Keep");
    Check(del.Contains(".gitconfig"), "dot files");
    Check(del.Contains("AppData\\Local\\CoreAIPlatform.00"), "Recall snapshots (CoreAIPlatform) go");

    Console.WriteLine("Must stay:");
    foreach (var s in new[] { "Downloads", "Desktop", "Documents", "AppData" }) Check(!del.Contains(s), $"{s} folder itself");
    foreach (var s in new[] { "NTUSER.DAT", "Keep", ".amnesia", ".ssh", "Documents\\Taxes", "AppData\\Roaming\\Code\\User",
                 "AppData\\Roaming\\Microsoft", "AppData\\Local\\Packages", "AppData\\Local\\Amnesia", "Downloads\\desktop.ini" })
        Check(keep.Contains(s) && !del.Contains(s), s);
    Check(!del.Any(d => d.StartsWith("Keep\\") || d.StartsWith(".amnesia")), "nothing inside Keep or .amnesia");

    Console.WriteLine("Windows extras:");
    foreach (var s in new[] { "OneDrive", "Links", "Searches", "Favorites\\Bing.url", "Pictures\\Screenshots" }) Check(!del.Contains(s), $"{s} stays");
    Check(del.Contains("Favorites\\mine.url"), "your own favorites go");
    Check(del.Contains("Pictures\\Screenshots\\shot.png"), "what is inside Screenshots goes");
    Check(del.Contains("Videos\\Captures\\clip.mp4"), "what is inside Captures goes");
    Check(del.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\notes.lnk"), "recent files (trace)");
    Check(del.Contains("AppData\\Roaming\\Microsoft\\Windows\\PowerShell\\PSReadLine\\ConsoleHost_history.txt"), "PowerShell history (trace)");
    Check(!del.Contains("AppData\\Local\\Microsoft\\Windows\\Explorer\\thumbcache_256.db"), "v0.5.2: thumbnail cache stays while Explorer runs (Clean now)");
    var atLogin = new CleanEngine().Run("login", true).Items.Select(i => i.Path).ToList();
    var atLogout = new CleanEngine().Run("logout", true).Items.Select(i => i.Path).ToList();
    Check(!atLogin.Contains("AppData\\Local\\Microsoft\\Windows\\Explorer\\thumbcache_256.db"), "v0.5.2: sign in check leaves Explorer's caches alone (no flicker)");
    Check(atLogout.Contains("AppData\\Local\\Microsoft\\Windows\\Explorer\\thumbcache_256.db"), "thumbnail cache is wiped at sign out (trace)");
    Check(atLogin.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\notes.lnk"), "sign in check still wipes recent files");
    Check(CleanEngine.ExplorerLiveKey(@"Registry: Windows\Shell\BagMRU") && !CleanEngine.ExplorerLiveKey(@"Registry: Explorer\RunMRU"), "shellbags wait for sign out, other history does not");
    Check(del.Contains("AppData\\Local\\Microsoft\\Windows\\Notifications\\wpndatabase.db"), "notification history (trace)");
    Check(del.Contains("AppData\\Local\\Packages\\Microsoft.Windows.Search_cw5n1h2txyewy\\LocalState\\DeviceSearchCache\\AppCache1.txt"), "Start menu search history (trace)");
    Check(!del.Any(d => d.Contains("Search_cw5n1h2txyewy\\Settings")), "rest of the Search app data stays");
    Check(del.Contains("AppData\\Local\\Microsoft\\Edge"), "Edge profile (history, cookies) is wiped");
    Check(!del.Contains("AppData\\Local\\Microsoft"), "rest of AppData\\Local\\Microsoft stays");
    Check(!del.Any(d => d.StartsWith("Registry")), "tests never list the registry");

    // a Keep folder somewhere else, set in settings.conf
    Settings("KEEP_DIR=~/Vault2");
    var r2 = Dry();
    Check(r2.Kept.Contains("Vault2"), "KEEP_DIR from settings is kept");
    Check(Del(r2).Contains("Keep"), "old Keep folder is no longer protected");
    Settings("KEEP_DIR=~/AppData/Local");
    Check(Dry().Kept.Contains("Keep"), "KEEP_DIR inside AppData is refused (back to Keep)");
    Settings("LANG=id");

    // Edge on the Keep List stays
    var kcOld = File.ReadAllLines(Conf2);
    File.AppendAllLines(Conf2, new[] { "AppData\\Local\\Microsoft\\Edge" });
    Check(!Del(Dry()).Contains("AppData\\Local\\Microsoft\\Edge"), "Edge on the Keep List stays");
    File.WriteAllLines(Conf2, kcOld);

    // the Keep shortcut on the Desktop stays, unless switched off
    Make("Desktop/Keep.lnk");
    Check(!Del(Dry()).Contains("Desktop\\Keep.lnk"), "Keep shortcut on the Desktop stays");
    Settings("LANG=id", "KEEP_SHORTCUT=0");
    Check(Del(Dry()).Contains("Desktop\\Keep.lnk"), "Keep shortcut switched off: wiped like any file");
    Settings("LANG=id");

    Console.WriteLine("Keep List page:");
    Check(KeepList.Add(Path.Combine(fake, "Documents", "Projects")) == "Documents/Projects", "adding a full path makes it relative");
    Check(KeepList.Add("Documents/Projects") == null, "the same path is not added twice");
    Check(KeepList.Add(OperatingSystem.IsWindows() ? "D:\\Elsewhere" : "/elsewhere") == null, "a path outside the user folder is refused");
    Check(Dry().Kept.Contains("Documents\\Projects"), "an added path is kept");
    Check(KeepList.Remove("Documents\\Projects"), "removing a path");
    Check(File.ReadAllLines(Conf2).Contains("# my keep list") && File.ReadAllLines(Conf2).Contains("app:Something"), "comments and other lines stay");
    Check(Wild.Like("AppData/Roaming/Code - Insiders/User", "AppData/Roaming/Code*/User") && !Wild.Like("Docs", "D?"), "wildcards");

    Console.WriteLine("Safety (real cleanup):");
    var r3 = Real("logout");
    Check(r3.Skipped == "off", "Amnesia off: nothing happens");
    Check(There("Downloads/movie.mp4"), "files are still there");
    var exe = Path.Combine(fake, "AppData/Local/Programs/Amnesia/Amnesia.exe");
    Settings("ENABLED=1", $"APP_PATH={exe}");
    Check(Real("logout").Skipped == "app-missing", "Amnesia.exe deleted: nothing happens");
    Check(There("Downloads/movie.mp4"), "files are still there");
    Make("AppData/Local/Programs/Amnesia/Amnesia.exe");
    Make("AppData/Local/Temp/.net/Amnesia/abc123/WebView2Loader.dll");
    Make("AppData/Local/Temp/other.tmp");
    File.WriteAllText(Path.Combine(fake, ".amnesia/pause_once"), "");
    Check(Real("logout").Skipped == "paused", "Pause: sign out skipped");
    Check(Real("login").Skipped == "paused", "Pause: sign in skipped too");
    Check(!There(".amnesia/pause_once"), "Pause is used up after one sign in");
    Check(There("Downloads/movie.mp4"), "files are still there after a pause");

    Console.WriteLine("Real cleanup:");
    Make("Documents/readonly.txt");
    File.SetAttributes(Path.Combine(fake, "Documents/readonly.txt"), FileAttributes.ReadOnly);
    var r7 = Real("logout");
    Check(r7.Count > 0 && r7.Failed == 0, $"sign out moved {r7.Count} item(s)");
    Check(!There("Downloads/movie.mp4"), "Downloads content gone");
    Check(!There("Documents/readonly.txt"), "read-only files go too");
    Check(There(".amnesia-trash"), "waiting in .amnesia-trash (emptied at sign in)");
    foreach (var s in new[] { "Downloads", "Desktop", "Documents", "NTUSER.DAT", "Keep/important.txt", ".ssh/id_ed25519", "Documents/Taxes/2026.pdf",
                 "AppData/Roaming/Code/User/settings.json", "AppData/Roaming/Microsoft/Credentials/abc", "AppData/Local/Packages/App/x",
                 "OneDrive/report.docx", "Links/Desktop.lnk", "Desktop/Keep.lnk", "Downloads/desktop.ini", "Pictures/Screenshots",
                 "AppData/Roaming/Microsoft/Windows/Recent", "AppData/Local/Packages/Microsoft.Windows.Search_cw5n1h2txyewy/Settings/settings.dat" })
        Check(There(s), $"{s} still there");
    Check(!There("AppData/Roaming/Microsoft/Windows/Recent/notes.lnk"), "recent files gone");
    Check(!There("AppData/Local/Microsoft/Windows/Explorer/thumbcache_256.db"), "thumbnail cache gone");
    Check(!There("AppData/Local/Microsoft/Edge"), "Edge history gone");
    Check(There("AppData/Local/Temp/.net/Amnesia/abc123/WebView2Loader.dll"), "Amnesia window part in Temp stays");
    Check(!There("AppData/Local/Temp/other.tmp"), "rest of Temp gone");
    Make("Downloads/new-after-crash.zip");
    Real("login");
    Check(!There(".amnesia-trash"), "sign in empties the trash");
    Check(!There("Downloads/new-after-crash.zip"), "sign in catches what was left behind");
    Check(There("Keep/important.txt"), "Keep is still there");
    var hist = File.ReadAllLines(Path.Combine(fake, ".amnesia/history.log"));
    Check(hist.Count(h => System.Text.RegularExpressions.Regex.IsMatch(h, "\tclean\tlogout \\d+ \\d+$")) == 1, "History has the sign out");
    Check(hist.Count(h => h.Contains("\tpaused\t")) == 2, "History has the pause");
    Check(!File.ReadAllText(Path.Combine(fake, ".amnesia/trace.log")).Contains("movie"), "trace.log has no file names");

    Console.WriteLine("Vault:");
    Make("AppData/Local/Google/Chrome/User Data/Default/Cookies");
    Make("AppData/Local/Google/Chrome/User Data/Default/Cache/data_1");
    Make("AppData/Local/Google/Chrome/User Data/Local State");
    Make(".claude/settings.json");
    Make("Documents/Notes/a.txt");
    try { Vault.Create("short"); Check(false, "short password refused"); } catch (VaultError e) { Check(e.Code == "short-password", "short password refused"); }
    try { Vault.Create("correct horse battery", "correct horse battery"); Check(false, "panic word = password refused"); } catch (VaultError e) { Check(e.Code == "panic-same", "panic word = password refused"); }
    Vault.Create("correct horse battery", "red balloon");
    Check(Vault.Exists, "vault created");
    Vault.Choose("Chrome", true); Vault.Choose("Claude Code", true);
    Check(Vault.AddFolder(Path.Combine(fake, "Documents", "Notes")) == "Documents/Notes", "a folder can go in the vault");
    var saved = Vault.Snapshot();
    Check(saved.Count == 3, $"snapshot saved {saved.Count} item(s) without a password");
    Check(Vault.Snapshot(changedOnly: true).Count == 0, "automatic snapshot skips apps that did not change");
    Thread.Sleep(1100);
    Make(".claude/new.json");
    var again = Vault.Snapshot(changedOnly: true);
    Check(again.Count == 1 && again[0] == "Claude Code", "automatic snapshot saves only the changed app");
    // the next sign out wipes the app data; restore brings it back
    CleanEngine.Delete(Path.Combine(fake, "AppData/Local/Google"));
    CleanEngine.Delete(Path.Combine(fake, ".claude"));
    CleanEngine.Delete(Path.Combine(fake, "Documents/Notes"));
    try { Vault.Restore("wrong password 1"); Check(false, "wrong password"); } catch (VaultError e) { Check(e.Code == "wrong" && e.Left == 2, "wrong password: 2 tries left"); }
    var back = Vault.Restore("correct horse battery");
    Check(back.Count == 3, "restore with the right password");
    Check(There("AppData/Local/Google/Chrome/User Data/Default/Cookies") && There("AppData/Local/Google/Chrome/User Data/Local State"), "Chrome logins are back");
    Check(!There("AppData/Local/Google/Chrome/User Data/Default/Cache/data_1"), "Chrome cache was not saved");
    Check(There(".claude/new.json") && There("Documents/Notes/a.txt"), "Claude Code and the folder are back");
    Check(Vault.Attempts == 0, "the right password resets the wrong count");
    Make(".claude/now.json");
    Vault.Restore("correct horse battery", new[] { "Claude Code" });
    Check(There("AppData/Local/Temp/Amnesia-before-restore/.claude/now.json"), "data you had is moved to Temp first, not deleted");
    Check(!Dry().Kept.Any(k => k.Contains("before-restore")), "that copy is wiped at the next sign out");
    // v0.5.1: Edge kept "Access denied": a folder a program holds open must not stop the restore or lose the snapshot
    Make("AppData/Local/Microsoft/Edge/User Data/Default/Cookies");
    Make("AppData/Local/Microsoft/Edge/User Data/Default/Preferences");
    Vault.Choose("Microsoft Edge", true);
    Check(Vault.Snapshot(new[] { "Microsoft Edge" }).Count == 1, "Edge snapshot");
    Make("AppData/Local/Microsoft/Edge/User Data/Default/LOCK");
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Default/Cookies"), "old");
    Vault.TestBusy = p => p.EndsWith("User Data") || p.EndsWith("Default") || p.EndsWith("LOCK") || p.EndsWith("Preferences");
    var edge = Vault.Restore("correct horse battery", new[] { "Microsoft Edge", "Claude Code" });
    Vault.TestBusy = null;
    Check(edge.Contains("Microsoft Edge") && edge.Contains("Claude Code"), "a busy Edge folder is still put back, and the other apps too");
    Check(File.ReadAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Default/Cookies")) != "old", "Edge logins are back file by file");
    Check(Vault.LastProblems.TryGetValue("Microsoft Edge", out var pr) && pr == "in-use:1", $"the file still in use is counted ({pr})");
    Check(There("AppData/Local/Temp/Amnesia-before-restore/AppData/Local/Microsoft/Edge/User Data/Default/Cookies"), "the Edge data you had is kept in Temp");
    Check(Vault.Manifest().ContainsKey("Microsoft Edge") && Vault.Snapshot(new[] { "Microsoft Edge" }).Count == 1, "the Edge snapshot is still in the vault");
    Vault.TestBusy = p => true;
    try { Vault.Restore("correct horse battery", new[] { "Claude Code" }); Check(Vault.LastProblems.ContainsKey("Claude Code"), "everything in use: the restore says so"); }
    catch (VaultError e) { Check(e.Code == "restore-failed", "nothing put back: clear error"); }
    Vault.TestBusy = null;
    Check(Vault.Manifest().ContainsKey("Claude Code"), "a failed restore keeps the snapshot");
    // v0.6: Claude from the Microsoft Store keeps its data in Packages\Claude_*\LocalCache
    Make("AppData/Local/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/config.json");
    Check(Vault.Present(Vault.Apps.First(x => x.Name == "Claude")).Contains("AppData/Local/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude"), "Store Claude shows up in the vault");
    Vault.Choose("Claude", true);
    Check(Vault.Snapshot(new[] { "Claude" }).Count == 1, "Store Claude snapshot");
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/config.json"), "changed");
    Vault.Restore("correct horse battery", new[] { "Claude" });
    Check(File.ReadAllText(Path.Combine(fake, "AppData/Local/Packages/Claude_pzs8sxrjxfjjc/LocalCache/Roaming/Claude/config.json")) != "changed", "Store Claude restored");

    Console.WriteLine("Backup:");
    var dest = Path.Combine(Path.GetTempPath(), "amnesia-test-usb-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(dest);
    try
    {
        Conf.Set("BACKUP_DEST", dest); Conf.Set("BACKUP_EVERY", "day");
        Check(Backup.Due(), "first automatic backup is due");
        var where = Backup.Create();
        Check(File.Exists(where) && Path.GetFileName(where).StartsWith("amnesia_backup_"), "backup made without a password");
        Check(!Backup.Due(), "next one is not due yet");
        Check(Backup.List().Count == 1, "backup listed");
        Check(!File.ReadAllText(where).Contains("important"), "backup is locked (no readable content)");
        // a new PC: everything gone
        CleanEngine.Delete(Path.Combine(fake, "Keep")); CleanEngine.Delete(Path.Combine(fake, ".amnesia"));
        try { Backup.Restore(where, "nope nope nope"); Check(false, "wrong password on a backup"); } catch (VaultError e) { Check(e.Code == "wrong", "wrong password on a backup"); }
        int n = Backup.Restore(where, "correct horse battery");
        Check(n > 0 && There("Keep/important.txt"), "Move to a new PC puts Keep back");
        Check(Vault.Exists && Vault.Manifest().ContainsKey("Chrome"), "and the vault with its snapshots");
        Check(File.ReadAllLines(Conf2).Contains(".ssh"), "and the Keep List");
        Check(Conf.Get("ENABLED") == null, "Amnesia is not turned on by a backup");
        var bytes = File.ReadAllBytes(where); bytes[^40] ^= 1; File.WriteAllBytes(where + "-bad", bytes);
        try { Backup.Restore(where + "-bad", "correct horse battery"); Check(false, "damaged backup refused"); }
        catch (Exception e) { Check(e is System.Security.Cryptography.CryptographicException or InvalidDataException, "damaged backup refused"); }
        File.WriteAllBytes(where + "-cut", File.ReadAllBytes(where)[..^100]);
        try { Backup.Restore(where + "-cut", "correct horse battery"); Check(false, "cut backup refused"); }
        catch (Exception e) { Check(e is System.Security.Cryptography.CryptographicException or InvalidDataException or EndOfStreamException, "cut backup refused"); }
    }
    finally { Directory.Delete(dest, true); }

    // ---------- v0.5 ----------
    Console.WriteLine("v0.5 more traces:");
    foreach (var f in new[] { "AppData/Local/Microsoft/Windows/WER/ReportArchive/AppCrash_x/Report.wer",
                 "AppData/Local/Packages/Microsoft.WindowsNotepad_8wekyb3d8bbwe/LocalState/TabState/abc.bin",
                 "AppData/Local/Packages/Microsoft.WindowsNotepad_8wekyb3d8bbwe/Settings/settings.dat",
                 "AppData/Roaming/Microsoft/Office/Recent/plan.docx.LNK" })
        Make(f);
    var d5 = Del(Dry());
    Check(d5.Contains("AppData\\Local\\Microsoft\\Windows\\WER\\ReportArchive"), "crash reports (WER)");
    Check(d5.Contains("AppData\\Local\\Packages\\Microsoft.WindowsNotepad_8wekyb3d8bbwe\\LocalState\\TabState\\abc.bin"), "Notepad unsaved tabs");
    Check(!d5.Any(x => x.EndsWith("Notepad_8wekyb3d8bbwe\\Settings\\settings.dat")), "Notepad settings stay");
    Check(d5.Contains("AppData\\Roaming\\Microsoft\\Office\\Recent\\plan.docx.LNK"), "Office recent files");

    Console.WriteLine("v0.5 Extra cleaning list (Winapp2):");
    var w2text = string.Join("\n", new[] {
        "; Version: 260915", "",
        "[Some App Logs *]", "DetectFile=%LocalAppData%\\Microsoft\\SomeApp", "FileKey1=%LocalAppData%\\Microsoft\\SomeApp|*.log", "FileKey2=%LocalAppData%\\Microsoft\\SomeApp\\Cache|*|REMOVESELF",
        "RegKey1=HKCU\\Software\\SomeApp\\Recent", "RegKey2=HKCU\\Software\\SomeApp|LastFile", "",
        "[Not Installed *]", "DetectFile=%LocalAppData%\\NotHere", "FileKey1=%LocalAppData%\\Microsoft\\Windows|*.db", "",
        "[Danger *]", "FileKey1=%AppData%\\Microsoft\\Protect|*|RECURSE", "FileKey2=%AppData%\\Microsoft\\Credentials|*", "RegKey1=HKCU\\Software\\Classes\\foo", "RegKey2=HKCU\\Software", "RegKey3=HKLM\\Software\\X", "",
        "[Program Files *]", "FileKey1=%ProgramFiles%\\Thing|*.log", "",
        "[With Warning *]", "Warning=breaks things", "FileKey1=%LocalAppData%\\Microsoft\\SomeApp|*.ini", "",
        "[Excluding *]", "FileKey1=%LocalAppData%\\Microsoft\\SomeApp|*.txt", "ExcludeKey1=FILE|%LocalAppData%\\Microsoft\\SomeApp\\|keep.txt", "",
        "[Keep List wins *]", "FileKey1=%AppData%\\Microsoft\\MyNotes|*", "" });
    foreach (var f in new[] { "AppData/Local/Microsoft/SomeApp/a.log", "AppData/Local/Microsoft/SomeApp/b.ini", "AppData/Local/Microsoft/SomeApp/note.txt",
                 "AppData/Local/Microsoft/SomeApp/keep.txt", "AppData/Local/Microsoft/SomeApp/Cache/c1", "AppData/Roaming/Microsoft/Protect/S-1/key",
                 "AppData/Local/Microsoft/Windows/x.db", "AppData/Roaming/Microsoft/MyNotes/n.txt" })
        Make(f);
    File.AppendAllLines(Conf2, new[] { "AppData/Roaming/Microsoft/MyNotes" });
    var w2 = Winapp2.Parse(w2text);
    Check(w2.Count == 7 && Winapp2.Version(w2text) == "260915", "list read (7 entries, version)");
    string? Env(string n) => n.ToLowerInvariant() switch { "localappdata" => Path.Combine(fake, "AppData", "Local"), "appdata" => Path.Combine(fake, "AppData", "Roaming"), "programfiles" => "/nonexistent", _ => null };
    var eng = new CleanEngine();
    var plan = Winapp2.Plan(w2, Env, _ => false, eng.ExtraOk);
    var pf = plan.Files.Select(f => Path.GetRelativePath(fake, f).Replace('\\', '/')).ToList();
    Check(pf.Contains("AppData/Local/Microsoft/SomeApp/a.log"), "matching file found");
    Check(pf.Contains("AppData/Local/Microsoft/SomeApp/Cache"), "REMOVESELF folder found");
    Check(pf.Contains("AppData/Local/Microsoft/SomeApp/note.txt") && !pf.Contains("AppData/Local/Microsoft/SomeApp/keep.txt"), "ExcludeKey respected");
    Check(!pf.Contains("AppData/Local/Microsoft/SomeApp/b.ini"), "entries with a Warning are skipped");
    Check(!pf.Contains("AppData/Local/Microsoft/Windows/x.db"), "entries whose app is not installed are skipped");
    Check(!pf.Any(p => p.Contains("/Protect") || p.Contains("/Credentials")), "saved passwords (DPAPI, Credentials) never");
    Check(!pf.Any(p => p.Contains("MyNotes")), "the Keep List wins over the list");
    Check(plan.Reg.Contains(("HKCU\\Software\\SomeApp\\Recent", null)) && plan.Reg.Contains(("HKCU\\Software\\SomeApp", "LastFile")), "HKCU registry lines kept");
    Check(!plan.Reg.Any(r => r.Key.Contains("Classes") || r.Key == "HKCU\\Software" || r.Key.StartsWith("HKLM")), "Classes, all of Software and HKLM never");
    Check(!Winapp2.RegAllowed("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run") && Winapp2.RegAllowed("HKCU\\Software\\Foo\\Bar"), "registry safety list");
    var withList = new CleanEngine { ExtraTraces = ok => Winapp2.Plan(w2, Env, _ => false, ok).Files }.Run("now", true);
    Check(withList.Items.Any(i => i.Path == "AppData\\Local\\Microsoft\\SomeApp\\a.log" && i.Kind == "trace"), "the cleanup uses the list (preview)");
    Check(!eng.ExtraOk(Path.Combine(fake, "Keep", "important.txt")) && !eng.ExtraOk(Path.Combine(fake, "Documents", "x")) && !eng.ExtraOk("/etc/passwd"), "outside the allowed folders: never");
    Check(!Winapp2.LooksValid(w2text), "a tiny file is not taken as the real list");
    // the real list, when the test run is given one (W2_REAL=path): must be read quickly and safely
    if (Environment.GetEnvironmentVariable("W2_REAL") is { Length: > 0 } real && File.Exists(real))
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var txt = File.ReadAllText(real);
        var all = Winapp2.Parse(txt);
        var rp = Winapp2.Plan(all, Env, _ => true, eng.ExtraOk);
        Console.WriteLine($"        real list: {all.Count} entries, {rp.Files.Count} files, {rp.Reg.Count} registry lines, {sw.ElapsedMilliseconds} ms");
        Check(Winapp2.LooksValid(txt) && all.Count > 3000, "the real Winapp2.ini is recognised");
        Check(rp.Reg.All(r => Winapp2.RegAllowed(r.Key)) && rp.Files.All(eng.ExtraOk), "everything planned from the real list passes the safety rules");
        Check(sw.Elapsed.TotalSeconds < 6, "and it is quick");
    }

    Console.WriteLine("v0.5 leftovers:");
    var pfRoot = Path.Combine(fake, "_pf");
    foreach (var f in new[] { "_pf/OldTool/readme.txt", "_pf/Mozilla Firefox/firefox.exe", "_pf/GoneApp/bin/gone.exe", "_pf/Empty Folder/.x", "_pf/Microsoft/x", "_pf/VideoLAN/VLC/vlc.exe" })
        Make(f);
    File.Delete(Path.Combine(fake, "_pf/Empty Folder/.x"));
    var lo = Leftovers.Folders(new[] { pfRoot }, new[] { "Mozilla Firefox (x64 en-US)", "VLC media player", "VideoLAN" }, new[] { Path.Combine(pfRoot, "VideoLAN", "VLC") });
    var ln = lo.Select(l => l.Name).ToList();
    Check(ln.Contains("OldTool") && ln.Contains("GoneApp") && ln.Contains("Empty Folder"), "folders of programs that are gone");
    Check(!ln.Contains("Mozilla Firefox") && !ln.Contains("VideoLAN") && !ln.Contains("Microsoft"), "installed programs and Windows' own folders stay off the list");
    Check(lo.First(l => l.Name == "GoneApp").Level == "careful" && lo.First(l => l.Name == "OldTool").Level == "likely" && lo.First(l => l.Name == "Empty Folder").Empty, "careful when programs are inside");
    Check(Leftovers.Allowed(Path.Combine(pfRoot, "OldTool"), new[] { pfRoot }) && !Leftovers.Allowed(Path.Combine(pfRoot, "GoneApp", "bin"), new[] { pfRoot }) && !Leftovers.Allowed(pfRoot, new[] { pfRoot }), "only folders one level below the roots can be deleted");
    Check(Leftovers.Norm("Visual Studio Code 1.95") == "visualstudiocode" && Leftovers.Used("Code", new[] { "code" }), "name matching");
    Check(RegNew.Find(new[] { "Microsoft", "7-Zip" }, new[] { "Microsoft", "7-Zip", "NewApp", "Classes", "Amnesia" }).SequenceEqual(new[] { "NewApp" }), "new registry settings: only the new app");
    var (ue, ua) = UninstallCmd.Parse("MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}", quiet: true);
    Check(ue == "MsiExec.exe" && ua == "/X{12345678-1234-1234-1234-123456789ABC} /qb /norestart", "MSI: /I becomes /X (remove, not repair)");
    var (ue2, ua2) = UninstallCmd.Parse("\"C:\\Program Files\\App\\unins000.exe\" /SILENT");
    Check(ue2 == "C:\\Program Files\\App\\unins000.exe" && ua2 == "/SILENT", "quoted uninstaller");

    Console.WriteLine("v0.5 privacy switches + undo:");
    var store = new FakeReg();
    store.Set("K\\Adv", "Start_TrackProgs", 1);
    var tw = new[] { new Tweak("track", "K\\Adv", "Start_TrackProgs", 0), new Tweak("track", "K\\Adv", "Start_TrackDocs", 0) };
    Check(!Tweaks.IsOn(store, tw), "off at first");
    Tweaks.Apply(store, tw);
    Check(Tweaks.IsOn(store, tw) && store.Get("K\\Adv", "Start_TrackDocs") == 0, "Apply sets both values");
    Tweaks.Apply(store, tw); // twice must not forget the real old value
    Tweaks.Undo(store, tw);
    Check(store.Get("K\\Adv", "Start_TrackProgs") == 1 && store.Get("K\\Adv", "Start_TrackDocs") == null, "Undo puts back the old value and removes what was not there");
    Check(!File.Exists(Tweaks.UndoFile), "undo list cleaned up");

    Console.WriteLine("Doomsday:");
    try { Vault.Restore("wrong password 1"); } catch (VaultError) { }
    try { Vault.Restore("wrong password 2"); Check(false, "last try warning"); } catch (VaultError e) { Check(e.Code == "wrong" && e.Left == 1, "one try left"); }
    try { Vault.Restore("wrong password 3"); Check(false, "third wrong password"); } catch (VaultError e) { Check(e.Code == "doomsday", "third wrong password: vault deleted"); }
    Check(!Vault.Exists && There("Keep/important.txt"), "vault gone, Keep stays");
    Check(Vault.Chosen().Count == 0, "v0.6: a new vault starts with no apps ticked");
    Vault.Create("correct horse battery", "red balloon", panicFull: true);
    try { Vault.CheckPassword("red balloon"); Check(false, "panic word"); } catch (VaultError e) { Check(e.Code == "doomsday", "panic word deletes the vault"); }
    Check(!Vault.Exists && !There("Keep/important.txt") && There("Keep"), "panic word with \"Keep too\" empties Keep");
}
finally
{
    Environment.SetEnvironmentVariable("AMNESIA_HOME", null);
    try { Directory.Delete(fake, true); } catch { }
}

if (fails > 0) { Console.WriteLine($"{fails} test(s) failed"); return 1; }
Console.WriteLine("All Amnesia tests passed");
return 0;

sealed class FakeReg : IRegStore
{
    readonly Dictionary<string, int> d = new();
    public int? Get(string key, string name) => d.TryGetValue(key + "|" + name, out var v) ? v : null;
    public void Set(string key, string name, int value) => d[key + "|" + name] = value;
    public void Delete(string key, string name) => d.Remove(key + "|" + name);
}
