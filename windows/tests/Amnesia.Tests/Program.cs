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

        Console.WriteLine("v0.8 backup and restore leftovers:");
        Conf.Set("BACKUP_DEST", dest); Make("Keep/amnesia_backup_2026-01-01_000000.amb"); Make("Keep/amnesia_backup_half.amb.partial");
        var where2 = Backup.Create();
        CleanEngine.Delete(Path.Combine(fake, "Keep"));
        Backup.Restore(where2, "correct horse battery");
        Check(There("Keep/important.txt") && !There("Keep/amnesia_backup_2026-01-01_000000.amb") && !There("Keep/amnesia_backup_half.amb.partial"), "an old backup inside Keep is not packed again");
        Check(!Directory.EnumerateFiles(Path.Combine(fake, ".amnesia"), ".restore-*.zip").Any(), "the unpacked restore file is gone");
        Check(!There(".amnesia/vault.incoming") && !There(".amnesia/vault.old") && Vault.Exists, "vault swapped in whole, nothing left over");
        var vd = Path.Combine(fake, ".amnesia", "vault");
        Directory.Move(vd, vd + ".old"); Make(".amnesia/vault.incoming/half.amv"); Make(".amnesia/.restore-abc.zip");
        Check(Backup.Sweep() >= 2 && Vault.Exists && !There(".amnesia/vault.incoming") && !There(".amnesia/.restore-abc.zip"), "a restore cut half way: old vault put back, leftovers gone");
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

    Console.WriteLine("v0.7 PIN:");
    var ph = Pin.Hash("246810");
    Check(Pin.Verify("246810", ph) && !Pin.Verify("246811", ph) && !Pin.Verify("246810", null), "PIN hash checks the right PIN only");
    Check(Pin.Hash("246810") != ph, "the same PIN gives a different hash each time (salt)");
    Check(!Pin.GoodPin("12345") && Pin.GoodPin("123456") && !Pin.GoodPin("12345a"), "lab PIN = 6 or more digits");

    Console.WriteLine("v0.7 lab lock:");
    var setFile = Path.Combine(fake, ".amnesia/settings.conf");
    var setBefore = File.ReadAllText(setFile);
    var labDir = Path.Combine(fake, "ProgramData-lab");
    Environment.SetEnvironmentVariable("AMNESIA_LAB_DIR", labDir);
    try
    {
        Check(!Lab.Active && Conf.Get("IDLE_MIN") == null, "no lab lock: own settings");
        Settings("LANG=id", "IDLE_MIN=15", "ENABLED=0");
        Lab.Stage(labDir, "246810", "C:\\x\\Amnesia.exe");
        Check(Lab.Active && Lab.Check("246810") && !Lab.Check("111111"), "locked, the PIN works, a wrong one does not");
        Settings("LANG=en", "IDLE_MIN=0", "ENABLED=0");
        Check(Conf.Get("IDLE_MIN") == "15", "a locked setting keeps the admin's value when the user changes it");
        Check(Conf.Get("LANG") == "en", "language stays per user");
        Check(Conf.Enabled, "always On while locked");
        File.WriteAllText(Conf.PauseFile, "");
        Check(!Conf.Paused, "Pause is ignored while locked");
        File.Delete(Conf.PauseFile);
        Check(KeepList.File == Lab.KeepFile && File.Exists(Lab.KeepFile), "the Keep List comes from the locked copy");
        Directory.Delete(labDir, true);
        Check(!Lab.Active && Conf.Get("IDLE_MIN") == "0" && !Conf.Enabled, "lock off: own settings again");
    }
    finally { Environment.SetEnvironmentVariable("AMNESIA_LAB_DIR", null); File.WriteAllText(setFile, setBefore); }

    Console.WriteLine("v0.7 vault: previous snapshot, shrunk, Edge setup:");
    File.WriteAllText(Path.Combine(fake, ".claude/settings.json"), "first");
    Vault.Snapshot(new[] { "Claude Code" });
    File.WriteAllText(Path.Combine(fake, ".claude/settings.json"), "second");
    Vault.Snapshot(new[] { "Claude Code" });
    Check(Vault.Manifest()["Claude Code"]?["prevTime"] != null, "the snapshot before is kept as 'previous'");
    Vault.Restore("correct horse battery", new[] { "Claude Code" }, previous: true);
    Check(File.ReadAllText(Path.Combine(fake, ".claude/settings.json")) == "first", "restore 'previous' brings back the older one");
    Vault.Restore("correct horse battery", new[] { "Claude Code" });
    Check(File.ReadAllText(Path.Combine(fake, ".claude/settings.json")) == "second", "a normal restore uses the newest");
    var big = new byte[6 * 1024 * 1024]; new Random(7).NextBytes(big);
    File.WriteAllBytes(Path.Combine(fake, ".claude/big.bin"), big);
    Vault.Snapshot(new[] { "Claude Code" });
    File.Delete(Path.Combine(fake, ".claude/big.bin"));
    Vault.Snapshot(new[] { "Claude Code" });
    Check(Vault.Manifest()["Claude Code"]?["shrunk"]?.GetValue<bool>() == true, "a much smaller new snapshot is marked");
    var edgeDefault = Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Default");
    foreach (var f in new[] { "Cookies", "History", "Network/Cookies" }) CleanEngine.Delete(Path.Combine(edgeDefault, f));
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Local State"), "{\"fre\":{\"has_user_completed_fre\": false}}");
    Vault.Snapshot(new[] { "Microsoft Edge" });
    Check(Vault.Manifest()["Microsoft Edge"]?["setup"]?.GetValue<string>() == "unfinished", "Edge setup not finished is noted");
    // v0.7.1: Edge leaves has_user_completed_fre false when its welcome is skipped
    var edgeApp = Vault.Apps.First(x => x.Name == "Microsoft Edge");
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Local State"), "{\"fre\":{\"has_user_completed_fre\": false},\"profile\":{\"has_first_visible_browser_session_completed\": true}}");
    Check(!Vault.SetupUnfinished(edgeApp), "v0.7.1: welcome skipped but the browser was used (first session completed): no warning");
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Local State"), "{\"fre\":{\"has_user_completed_fre\": false}}");
    Make("AppData/Local/Microsoft/Edge/User Data/Default/Network/Cookies");
    Check(!Vault.SetupUnfinished(edgeApp), "v0.7.1: welcome skipped but the profile has cookies: no warning");
    File.Delete(Path.Combine(edgeDefault, "Network/Cookies"));
    Make("AppData/Local/Microsoft/Edge/User Data/Default/History");
    Check(!Vault.SetupUnfinished(edgeApp), "v0.7.1: welcome skipped but the profile has history: no warning");
    File.Delete(Path.Combine(edgeDefault, "History"));
    Check(Vault.SetupUnfinished(edgeApp), "v0.7.1: really never used: still a warning");
    File.WriteAllText(Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Local State"), "{\"fre\":{\"has_user_completed_fre\": true}}");
    Vault.Snapshot(new[] { "Microsoft Edge" });
    Check(Vault.Manifest()["Microsoft Edge"]?["setup"] == null, "and not after it is finished");
    Vault.DeleteSnapshots(new[] { "Claude Code" });
    Check(!Directory.EnumerateFiles(Path.Combine(fake, ".amnesia"), "*.prev.amv", SearchOption.AllDirectories).Any(f => f.Contains("claude", StringComparison.OrdinalIgnoreCase)), "deleting a snapshot deletes 'previous' too");

    Console.WriteLine("v0.7.1 automatic snapshot while signed in:");
    var appsDir = Path.Combine(fake, ".amnesia/vault/apps");
    File.WriteAllText(Path.Combine(appsDir, "microsoft-edge.amv.new"), "half");
    Check(Vault.RemoveUnfinished() == 1 && !File.Exists(Path.Combine(appsDir, "microsoft-edge.amv.new")) && File.Exists(Path.Combine(appsDir, "microsoft-edge.amv")), "a half written snapshot is deleted, the finished one stays");
    var procs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "msedge" };
    var auto = new AutoSnap(TimeSpan.FromMinutes(2), TimeSpan.Zero);
    var now = DateTime.UtcNow;
    Check(!auto.Due(procs.Contains, now).Contains("Microsoft Edge"), "an app is not saved while it runs");
    Check(!auto.Due(procs.Contains, now).Contains("Microsoft Edge"), "still running: still not saved");
    procs.Clear();
    Check(auto.Due(procs.Contains, now).Contains("Microsoft Edge"), "closed after running: saved");
    Check(!auto.Due(procs.Contains, now).Contains("Microsoft Edge"), "only once per close");
    Vault.Choose("Claude Code", true);
    Make(".claude/later.json");
    Check(!auto.Due(procs.Contains, DateTime.UtcNow).Contains("Claude Code"), "an app without its own program waits until its data is quiet");
    Check(auto.Due(procs.Contains, DateTime.UtcNow.AddMinutes(3)).Contains("Claude Code"), "then it is saved");
    Vault.Snapshot(new[] { "Claude Code" });
    Check(!auto.Due(procs.Contains, DateTime.UtcNow.AddMinutes(3)).Contains("Claude Code"), "and not again until it changes");
    Make("AppData/Local/Microsoft/Edge/User Data/Default/Bookmarks");
    procs.Add("msedge");
    Check(Vault.Snapshot(new[] { "Microsoft Edge" }, changedOnly: true, running: procs.Contains).Count == 0, "the background snapshot skips an app that was opened again");
    procs.Clear();
    Check(Vault.Snapshot(new[] { "Microsoft Edge" }, changedOnly: true, running: procs.Contains).Count == 1, "and saves it once it is closed");

    Console.WriteLine("v0.7.1 Explorer caches:");
    Make("AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db");
    var liveNo = new CleanEngine { ExplorerLiveOk = false }.Run("logout", true).Items.Select(i => i.Path).ToList();
    Check(!liveNo.Contains("AppData\\Local\\Microsoft\\Windows\\Explorer\\iconcache_48.db"), "a sign out cleanup while Explorer still runs (panic) leaves the icon cache alone");
    var liveYes = new CleanEngine { ExplorerLiveOk = true }.Run("logout", true).Items.Select(i => i.Path).ToList();
    Check(liveYes.Contains("AppData\\Local\\Microsoft\\Windows\\Explorer\\iconcache_48.db"), "at the real end of the session it goes");
    Check(CleanEngine.TouchesShell(new[] { new CleanItem("Desktop\\notes.txt", "file") }) && !CleanEngine.TouchesShell(new[] { new CleanItem("Downloads\\a.zip", "file") }), "Explorer is told when Desktop items went");

    Console.WriteLine("v0.8 cloud folders and virtual machines:");
    Settings("ENABLED=1", $"APP_PATH={exe}");
    File.WriteAllLines(Conf2, new[] { "Keep/ignored", "AppData/Roaming/Code*/User" });
    foreach (var f in new[] { "Dropbox/a.txt", "Dropbox (Work)/b.txt", "Google Drive/c.txt", "iCloudDrive/d.txt", "MyCloud/e.txt",
                 "VirtualBox VMs/win/win.vdi", "Downloads/disk.vhdx", "Downloads/small.iso", "Documents/Lab/vm/disk.vmdk", "Documents/Lab/notes.txt",
                 "AppData/Local/wsl/abc/ext4.vhdx", "AppData/Local/wsl/abc/other", ".android/avd/pixel.avd/x", ".android/cache/y", "Downloads/plain.txt" })
        Make(f);
    using (var bigIso = File.Create(Path.Combine(fake, "Downloads/big.iso"))) bigIso.SetLength(CleanEngine.BigIso); // sparse, takes no real space
    var cloudEngine = new CleanEngine { CloudRoots = () => new[] { Path.Combine(fake, "MyCloud"), "C:\\Elsewhere\\Sync", Path.GetTempPath() } };
    var d8 = cloudEngine.Run("now", true).Items.Select(i => i.Path).ToList();
    foreach (var s in new[] { "Dropbox", "Dropbox (Work)", "Google Drive", "iCloudDrive", "MyCloud" })
        Check(!d8.Any(d => d == s || d.StartsWith(s + "\\")), $"cloud folder {s} stays (its app would delete it from the cloud)");
    foreach (var s in new[] { "VirtualBox VMs", "Downloads\\disk.vhdx", "Downloads\\big.iso", "Documents\\Lab\\vm\\disk.vmdk", "AppData\\Local\\wsl", ".android\\avd" })
        Check(!d8.Any(d => d == s || d.StartsWith(s + "\\") || s.StartsWith(d + "\\")), $"virtual machine data {s} stays");
    Check(d8.Contains("Downloads\\small.iso"), "a small .iso still goes");
    Check(d8.Contains("Documents\\Lab\\notes.txt"), "the rest of a folder with a VM disk still goes");
    Check(d8.Contains(".android\\cache"), "the rest of .android still goes");
    Check(d8.Contains("Downloads\\plain.txt"), "normal files still go");
    Settings("ENABLED=1", $"APP_PATH={exe}", "KEEP_VM=0");
    var d8off = new CleanEngine().Run("now", true).Items.Select(i => i.Path).ToList();
    Check(d8off.Contains("Downloads\\disk.vhdx") && d8off.Contains("VirtualBox VMs"), "KEEP_VM=0: virtual machines go too");
    Check(!d8off.Contains("Dropbox"), "KEEP_VM=0 never touches cloud folders");
    Settings("ENABLED=1", $"APP_PATH={exe}");

    Console.WriteLine("v0.8 Remove new apps never takes protected folders:");
    foreach (var f in new[] { "Keep/tes-hapus/penting.txt", "AppData/Local/Programs/NewApp/app.exe", "AppData/Roaming/NewTool/x", "AppData/Local/Programs/Amnesia/Amnesia.exe" })
        Make(f);
    var rules = new CleanEngine();
    string F(string rel) => Path.Combine(fake, rel);
    Check(!rules.MayRemoveAppFolder(F("Keep/tes-hapus")), "a folder in Keep (the T7 test)");
    Check(!rules.MayRemoveAppFolder(F("Keep")), "the Keep folder itself");
    Check(!rules.MayRemoveAppFolder(F("Documents")) && !rules.MayRemoveAppFolder(fake), "the user folder and Documents");
    Check(!rules.MayRemoveAppFolder(F("AppData/Local")) && !rules.MayRemoveAppFolder(F("AppData/Local/Programs")), "AppData\\Local and Programs themselves");
    Check(!rules.MayRemoveAppFolder(F("AppData/Roaming/Code")), "a folder with something on the Keep List inside");
    Check(!rules.MayRemoveAppFolder(F("AppData/Local/Programs/Amnesia")), "Amnesia itself");
    Check(!rules.MayRemoveAppFolder(F("AppData/Local/Packages/App")), "Store app data");
    Check(!rules.MayRemoveAppFolder(F("AppData/Local/Programs/../../../Keep")), "a path that climbs out with ..");
    Check(!rules.MayRemoveAppFolder(Path.GetTempPath()) && !rules.MayRemoveAppFolder(""), "outside the user folder / empty");
    Check(!rules.MayRemoveAppFolder(F("AppData/Local/Programs/Missing")), "a folder that isn't there");
    Check(rules.MayRemoveAppFolder(F("AppData/Local/Programs/NewApp")) && rules.MayRemoveAppFolder(F("AppData/Roaming/NewTool")), "a new program's own folder may go");
    Check(CleanEngine.ToTrash(F("AppData/Local/Programs/NewApp")) && !There("AppData/Local/Programs/NewApp"), "it is moved, not deleted");
    var appsBatch = Directory.GetDirectories(Path.Combine(fake, ".amnesia-trash")).FirstOrDefault(d => d.EndsWith("-apps"));
    Check(appsBatch != null && File.Exists(Path.Combine(appsBatch, "AppData", "Local", "Programs", "NewApp", "app.exe")), "found in .amnesia-trash");
    Real("now");
    Check(appsBatch != null && Directory.Exists(appsBatch), "a cleanup keeps it for 3 days");
    Check(There("Keep/tes-hapus/penting.txt"), "Keep\\tes-hapus untouched");

    Console.WriteLine("v0.8 Keep List knows which app a folder belongs to:");
    var cands = new[] { "AppData/Roaming/discord", "AppData/Local/Discord", "AppData/Roaming/Code", "AppData/Local/Google",
        "AppData/Local/Google/Chrome", "AppData/Roaming/Spotify", "AppData/Local/Microsoft", "AppData/Roaming/Obsidian", "AppData/Local/Temp" };
    Check(AppMatch.Folders("Discord", "Discord Inc.", null, cands).SequenceEqual(new[] { "AppData/Roaming/discord", "AppData/Local/Discord" }), "Discord: both its folders");
    Check(AppMatch.Folders("Google Chrome", "Google LLC", @"C:\Program Files\Google\Chrome\Application", cands).SequenceEqual(new[] { "AppData/Local/Google/Chrome" }), "Chrome: Google/Chrome, not all of Google");
    Check(AppMatch.Folders("Microsoft Visual Studio Code", "Microsoft Corporation", @"C:\Users\x\AppData\Local\Programs\Microsoft VS Code", cands).Count == 0, "no wild guesses (Microsoft is skipped)");
    Check(AppMatch.Folders("Obsidian", "Obsidian", null, cands).SequenceEqual(new[] { "AppData/Roaming/Obsidian" }), "Obsidian");

    Console.WriteLine("v0.8 signed updates:");
    using (var ec = System.Security.Cryptography.ECDsa.Create(System.Security.Cryptography.ECCurve.NamedCurves.nistP256))
    {
        var pubKey = Convert.ToBase64String(ec.ExportSubjectPublicKeyInfo());
        var sums = System.Text.Encoding.UTF8.GetBytes("abc123  Amnesia-Setup-0.8.0-x64.exe\n");
        var sig = ec.SignData(sums, System.Security.Cryptography.HashAlgorithmName.SHA256, System.Security.Cryptography.DSASignatureFormat.Rfc3279DerSequence);
        Check(UpdateSig.Verify(sums, sig, pubKey), "a good signature passes");
        var changed = (byte[])sums.Clone(); changed[0] ^= 1;
        Check(!UpdateSig.Verify(changed, sig, pubKey), "a changed checksum list fails");
        Check(!UpdateSig.Verify(sums, sig), "no key in this copy: nothing passes");
        Check(!UpdateSig.Verify(sums, new byte[3], pubKey), "a broken signature fails");
        var sumsFile = Path.Combine(fake, "sums.txt"); File.WriteAllBytes(sumsFile, sums);
        File.WriteAllText(Path.Combine(fake, "key.pem"), ec.ExportECPrivateKeyPem());
        var osl = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("openssl", $"dgst -sha256 -sign \"{Path.Combine(fake, "key.pem")}\" -out \"{sumsFile}.sig\" \"{sumsFile}\"") { UseShellExecute = false });
        osl?.WaitForExit();
        if (File.Exists(sumsFile + ".sig")) Check(UpdateSig.Verify(sums, File.ReadAllBytes(sumsFile + ".sig"), pubKey), "a signature made with openssl (the publish script) passes");
    }

    Console.WriteLine("v0.8 Safe box (experimental):");
    {
        try { Safe.Create("short"); Check(false, "a short safe password is refused"); } catch (VaultError e) { Check(e.Code == "short-password", "a short safe password is refused"); }
        Safe.Create("correct horse battery safe");
        Check(Safe.Exists && Safe.IsOpen, "a new safe starts open (Keep\\Safe)");
        Make("Keep/Safe/passport.pdf"); Make("Keep/Safe/deep/notes.txt");
        Check(Safe.Close("test") == 2 && !There("Keep/Safe") && Safe.Exists, "closing packs 2 files and deletes the open copy");
        Check(!File.ReadAllText(Safe.File_).Contains("passport"), "closed safe is locked (no readable names)");
        try { Safe.Open("wrong wrong wrong"); Check(false, "wrong safe password"); } catch (VaultError e) { Check(e.Code == "wrong", "wrong safe password: nothing opened"); }
        Check(!There("Keep/Safe"), "...and nothing unpacked");
        Check(Safe.Open("correct horse battery safe") == 2 && There("Keep/Safe/passport.pdf") && There("Keep/Safe/deep/notes.txt"), "the right password opens it again");
        Check(!Directory.EnumerateFiles(Path.Combine(fake, ".amnesia", "safe"), ".open-*").Any(), "no unpacked zip left over");
        Check(Del(Dry()).All(d => !d.StartsWith("Keep")), "an open safe is never wiped (it is in Keep)");
        Safe.Close("test");
        Safe.Delete("correct horse battery safe");
        Check(!Safe.Exists && !There(".amnesia/safe"), "a deleted safe is gone");
    }

    Console.WriteLine("v0.8 Store app data (opt-in):");
    foreach (var f in new[] { "AppData/Local/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/LocalState/cache.db",
                 "AppData/Local/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0/Settings/settings.dat",
                 "AppData/Local/Packages/Microsoft.Windows.Photos_8wekyb3d8bbwe/LocalState/db.sqlite",
                 "AppData/Local/Packages/5319275A.WhatsAppDesktop_cv1g1gvanyjgm/LocalState/session.db" }) Make(f);
    Check(!Del(Dry()).Any(d => d.Contains("SpotifyAB")), "off by default: Store app data stays");
    var storeConf = File.ReadAllText(Path.Combine(fake, ".amnesia/settings.conf"));
    Conf.Set("WIPE_STORE", "1");
    File.AppendAllLines(Conf2, new[] { "AppData/Local/Packages/5319275A.WhatsAppDesktop_cv1g1gvanyjgm" });
    var st = Del(Dry());
    Check(st.Contains("AppData\\Local\\Packages\\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\\LocalState\\cache.db"), "on: a Store app's own data goes");
    Check(!st.Any(d => d.Contains("SpotifyAB") && d.Contains("Settings")), "its Settings folder stays");
    Check(!st.Any(d => d.Contains("Microsoft.Windows.Photos")), "Windows' own apps stay");
    Check(!st.Any(d => d.Contains("WhatsAppDesktop")), "a Store app on the Keep List stays");
    File.WriteAllText(Path.Combine(fake, ".amnesia/settings.conf"), storeConf);

    Console.WriteLine("v0.8 sign out list made a moment before:");
    Make("Downloads/early.txt");
    var prepared = new CleanEngine { Fast = true };
    prepared.Prepare("logout");
    Check(prepared.Planned > 0 && There("Downloads/early.txt"), "Prepare only looks");
    Make("Downloads/late.txt");
    var r8 = prepared.Run("logout", false);
    Check(!There("Downloads/early.txt") && There("Downloads/late.txt"), "the real run uses the list (a later file waits for the sign in check)");
    Check(r8.Bytes == -1, "fast run: sizes not counted");
    Check(File.ReadAllText(Path.Combine(fake, ".amnesia/trace.log")).Contains("using the list made"), "trace.log says the list was made before");
    Real("login");
    Check(!There("Downloads/late.txt"), "the sign in check takes the later file");
    var paused8 = new CleanEngine();
    paused8.Prepare("logout");
    File.WriteAllText(Path.Combine(fake, ".amnesia/pause_once"), "");
    Make("Downloads/paused.txt");
    Check(paused8.Run("logout", false).Skipped == "paused" && There("Downloads/paused.txt"), "a prepared list still obeys Pause");
    File.Delete(Path.Combine(fake, ".amnesia/pause_once"));
    File.WriteAllLines(Conf2, new[] { ".ssh" });

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
