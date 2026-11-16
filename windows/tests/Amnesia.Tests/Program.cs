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
    // v0.11.1 W6: one damaged archive must not stop the restore of the other apps
    {
        var ccAmv = Path.Combine(fake, ".amnesia", "vault", "apps", "claude-code.amv");
        var goodAmv = File.ReadAllBytes(ccAmv);
        var badAmv = (byte[])goodAmv.Clone();
        for (int k = badAmv.Length / 2; k < Math.Min(badAmv.Length, badAmv.Length / 2 + 16); k++) badAmv[k] ^= 0xFF;
        File.WriteAllBytes(ccAmv, badAmv);
        var edgeCookies = Path.Combine(fake, "AppData/Local/Microsoft/Edge/User Data/Default/Cookies");
        File.WriteAllText(edgeCookies, "old2");
        List<string>? mixed = null;
        try { mixed = Vault.Restore("correct horse battery", new[] { "Claude Code", "Microsoft Edge" }); }
        catch (Exception e) { Check(false, "v0.11.1: a damaged archive stops the whole restore (" + e.GetType().Name + ")"); }
        Check(mixed != null && mixed.Contains("Microsoft Edge") && !mixed.Contains("Claude Code"), "v0.11.1: the other app is put back, the damaged one is not in the list");
        Check(File.ReadAllText(edgeCookies) != "old2", "v0.11.1: ...and its data really is back");
        Check(Vault.LastProblems.TryGetValue("Claude Code", out var dmg) && dmg == "failed", "v0.11.1: the damaged app is reported by name");
        Check(!There(".amnesia/vault/.stage"), "v0.11.1: nothing unpacked is left behind");
        File.WriteAllBytes(ccAmv, goodAmv);
    }
    // v0.11.1: the "3 wrong passwords" counter is a plain file. This test writes down what that means today (the app text says
    // it only stops someone at the screen): anyone who can write the file gets as many tries as they want.
    {
        var attemptsF = Path.Combine(fake, ".amnesia", "vault", "attempts");
        File.WriteAllText(attemptsF, "-1000");
        for (int k = 0; k < 4; k++) { try { Vault.CheckPassword("wrong wrong wrong"); } catch (VaultError) { } }
        Check(Vault.Exists && Vault.Attempts == -996, "v0.11.1 (known limit): with the counter set to -1000, four wrong passwords delete nothing");
        File.WriteAllText(attemptsF, "0");
        Check(Vault.Attempts == 0, "v0.11.1: ...and the counter can be put back");
    }
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
    // v0.9 audit: the panic deletes Explorer's caches before the cleanup itself checks the Keep List
    var kcSaved = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
    File.WriteAllText(Conf2, "AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db\n");
    Check(CleanEngine.DeleteExplorerCaches() == 0 && There("AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db"), "panic: an Explorer cache on the Keep List stays");
    File.WriteAllText(Conf2, "Keep\0\0");
    Check(CleanEngine.DeleteExplorerCaches() == 0 && There("AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db"), "panic: a Keep List that can't be read stops it too");
    File.WriteAllText(Conf2, "");
    Check(CleanEngine.DeleteExplorerCaches() >= 1 && !There("AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db"), "panic: otherwise the Explorer caches go");
    if (kcSaved != null) File.WriteAllText(Conf2, kcSaved); else File.Delete(Conf2);
    Make("AppData/Local/Microsoft/Windows/Explorer/iconcache_48.db");

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
        Check(!File.Exists(Safe.File_ + ".prev"), "v0.8.1: no second full copy (safe.ams.prev) after a good close");
        Check(Safe.Count == 2, "v0.8.1: the closed safe knows it holds 2 files (for the uninstall warning)");
        Check(!File.ReadAllText(Safe.File_).Contains("passport"), "closed safe is locked (no readable names)");
        try { Safe.Open("wrong wrong wrong"); Check(false, "wrong safe password"); } catch (VaultError e) { Check(e.Code == "wrong", "wrong safe password: nothing opened"); }
        Check(!There("Keep/Safe"), "...and nothing unpacked");
        Check(Safe.Open("correct horse battery safe") == 2 && There("Keep/Safe/passport.pdf") && There("Keep/Safe/deep/notes.txt"), "the right password opens it again");
        Check(!Directory.EnumerateFiles(Path.Combine(fake, ".amnesia", "safe"), ".open-*").Any(), "no unpacked zip left over");
        Make("Keep/Safe/third.txt");
        Check(Safe.Count == 3, "v0.8.1: an open safe counts what is in Keep\\Safe now");
        Check(Del(Dry()).All(d => !d.StartsWith("Keep")), "an open safe is never wiped (it is in Keep)");
        Safe.Close("test");
        // v0.11.1 W1: an empty Keep\Safe that Open did not make must never be packed over a closed safe
        {
            var pw = "correct horse battery safe";
            var packed = File.ReadAllBytes(Safe.File_);
            Directory.CreateDirectory(Path.Combine(fake, "Keep", "Safe"));
            Check(!Safe.IsOpen, "v0.11.1: an empty Keep\\Safe that Open did not make is not an open safe");
            Check(Safe.Close("test") == -1, "v0.11.1: closing refuses to pack an empty stray Keep\\Safe");
            Check(File.ReadAllBytes(Safe.File_).SequenceEqual(packed) && !File.Exists(Safe.File_ + ".prev") && Safe.Count == 3, "v0.11.1: the closed safe and its file count are untouched, no .prev dropped");
            Directory.CreateDirectory(Path.Combine(fake, "Keep", "Safe"));
            Check(Safe.Open(pw) == 3 && There("Keep/Safe/third.txt"), "v0.11.1: Open still works when an empty stray Keep\\Safe is in the way");
            Check(Safe.IsOpen, "v0.11.1: ...and then it is open");
            // the user may empty the open safe on purpose: that is a real (empty) close
            foreach (var f in Directory.GetFileSystemEntries(Path.Combine(fake, "Keep", "Safe"))) { if (Directory.Exists(f)) Directory.Delete(f, true); else File.Delete(f); }
            Check(Safe.Close("test") == 0 && Safe.Count == 0 && !There("Keep/Safe"), "v0.11.1: an emptied safe (opened by Open) closes as an empty safe");
            Safe.Open(pw);
            Make("Keep/Safe/third.txt");
            Safe.Close("test");

            // a stray folder with only Explorer junk or empty subfolders is still stray
            packed = File.ReadAllBytes(Safe.File_);
            File.WriteAllText(Safe.File_ + ".prev", "old");
            Directory.CreateDirectory(Path.Combine(fake, "Keep", "Safe", "a", "b"));
            File.WriteAllText(Path.Combine(fake, "Keep", "Safe", "desktop.ini"), "x");
            File.WriteAllText(Path.Combine(fake, "Keep", "Safe", "Thumbs.db"), "x");
            Check(!Safe.IsOpen && Safe.Close("test") == -1, "v0.11.1: a stray Keep\\Safe with only desktop.ini, Thumbs.db and empty folders is not an open safe either");
            Check(File.ReadAllBytes(Safe.File_).SequenceEqual(packed) && Safe.Count == 1 && File.Exists(Safe.File_ + ".prev") && !There("Keep/Safe"), "v0.11.1: safe and an existing .prev untouched; the junk folder is gone");
            File.Delete(Safe.File_ + ".prev");

            // a marker left behind when Keep\Safe was removed by hand must not make a later empty folder count as open
            Safe.Open(pw);
            Directory.Delete(Path.Combine(fake, "Keep", "Safe"), true);
            Check(Safe.Close("test") == -1, "v0.11.1: Keep\\Safe taken away by hand: nothing to close");
            Directory.CreateDirectory(Path.Combine(fake, "Keep", "Safe"));
            Check(Safe.Close("test") == -1 && File.ReadAllBytes(Safe.File_).SequenceEqual(packed) && Safe.Count == 1, "v0.11.1: ...and an empty folder that appears later is still not packed over the safe");

            // a safe left open by v0.11.0 has no marker: it must still close with its files
            Safe.Open(pw);
            File.Delete(Path.Combine(fake, ".amnesia", "safe", "open.marker"));
            Make("Keep/Safe/new.txt");
            Check(Safe.IsOpen && Safe.Close("test") == 2 && Safe.Count == 2, "v0.11.1: an open safe from before the marker (files, no marker) still closes with its files");

            // a close that packed fine but could not delete everything must not be packed again as if it were open
            if (OperatingSystem.IsWindows())
            {
                Safe.Open(pw);
                using (var locked = new FileStream(Path.Combine(fake, "Keep", "Safe", "new.txt"), FileMode.Open, FileAccess.Read, FileShare.Read))
                    Check(Safe.Close("test") == 2 && There("Keep/Safe/new.txt"), "v0.11.1: a locked file keeps part of the open copy after a good close");
                packed = File.ReadAllBytes(Safe.File_);
                Check(!Safe.IsOpen && Safe.Close("test") == -1 && File.ReadAllBytes(Safe.File_).SequenceEqual(packed), "v0.11.1: leftovers of a finished close are not packed over the full safe");
                // the same again, but the next call is Open: it replaces the leftovers with the real contents
                Safe.Open(pw);
                using (var locked2 = new FileStream(Path.Combine(fake, "Keep", "Safe", "new.txt"), FileMode.Open, FileAccess.Read, FileShare.Read))
                    Safe.Close("test");
                Make("Keep/Safe/leftover.txt");
                Check(!Safe.IsOpen && Safe.Open(pw) == 2 && Safe.IsOpen && !There("Keep/Safe/leftover.txt") && There("Keep/Safe/new.txt"), "v0.11.1: opening again replaces the leftovers with the real contents");
                Safe.Close("test");
            }
        }
        Safe.Delete("correct horse battery safe");
        Check(!Safe.Exists && !There(".amnesia/safe"), "a deleted safe is gone");
        Check(Safe.Count == 0 && Conf.Get("SAFE_FILES") == null, "v0.8.1: and its file count too");
    }

    Console.WriteLine("v0.11.1 W2 wildcard Keep lines protect matches at any depth:");
    {
        var savedKeep = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
        foreach (var f in new[] { "Documents/Old/Deep/vault.kdbx", "Documents/Old/Deep/other.txt", "Documents/Old/junk.txt", "Documents/top.kdbx",
                     "Documents/Plain/x.txt", "AppData/Local/Microsoft/Windows/Foo/pw.kdbx", "AppData/Local/Microsoft/Windows/Foo/cache.bin" })
            Make(f);
        File.WriteAllLines(Conf2, new[] { "*.kdbx" });
        var rw = Dry();
        var dw = Del(rw);
        Check(!dw.Contains("Documents\\Old") && !dw.Contains("Documents\\Old\\Deep") && !dw.Contains("Documents"), "a folder that holds a deep match is not wiped whole");
        Check(dw.Contains("Documents\\Old\\Deep\\other.txt") && dw.Contains("Documents\\Old\\junk.txt"), "the rest inside it still goes");
        Check(!dw.Contains("Documents\\Old\\Deep\\vault.kdbx") && rw.Kept.Contains("Documents\\Old\\Deep\\vault.kdbx"), "the deep match stays and the preview lists it as kept");
        Check(!dw.Contains("Documents\\top.kdbx") && rw.Kept.Contains("Documents\\top.kdbx"), "a top-level match still stays");
        Check(dw.Contains("Documents\\Plain"), "a folder without any match still goes whole");
        Check(!new CleanEngine().ExtraOk(Path.Combine(fake, "AppData", "Local", "Microsoft", "Windows", "Foo")), "the Extra list also leaves a folder that holds a match");
        Check(new CleanEngine().ExtraOk(Path.Combine(fake, "AppData", "Local", "Microsoft", "Windows", "Foo", "cache.bin")), "...but may take a file that does not match");
        // trace folders (Recent, ...): a match in them, or a folder holding one, is not swept either
        Make("AppData/Roaming/Microsoft/Windows/Recent/mine.kdbx"); Make("AppData/Roaming/Microsoft/Windows/Recent/folder/deep.kdbx"); Make("AppData/Roaming/Microsoft/Windows/Recent/other.lnk");
        var dt = Del(Dry());
        Check(!dt.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\mine.kdbx") && !dt.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\folder") && dt.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\other.lnk"), "trace folders leave a wildcard match (and a folder holding one) alone");
        var rr2 = Real("now");
        Check(There("Documents/Old/Deep/vault.kdbx") && There("Documents/top.kdbx") && !There("Documents/Old/junk.txt") && !There("Documents/Plain"), "a real run keeps the matches at any depth and wipes the rest");
        // follow-ups
        // 1. an absurdly deep folder is never walked to the end (no stack overflow): it stays
        var deepRel = "Documents/Deep" + string.Concat(Enumerable.Repeat("/d", 170));
        Make(deepRel + "/x.txt");
        File.WriteAllLines(Conf2, new[] { "*.kdbx" });
        var dDeep = Del(Dry());
        Check(!dDeep.Any(d => d.StartsWith("Documents\\Deep")), "v0.11.1: a folder nested far deeper than any real one is left alone (and the run does not crash)");
        Directory.Delete(Path.Combine(fake, "Documents", "Deep"), true);
        // 2. browser folders: the wildcard line keeps its match, the rest of the browser data still goes
        Make("AppData/Local/Microsoft/Edge/User Data/Default/Bookmarks"); Make("AppData/Local/Microsoft/Edge/User Data/Default/History");
        File.WriteAllLines(Conf2, new[] { "*/Bookmarks" });
        var rEdge = Dry(); var dEdge = Del(rEdge);
        Check(!dEdge.Contains("AppData\\Local\\Microsoft\\Edge") && !dEdge.Any(d => d.EndsWith("\\Bookmarks")) && rEdge.Kept.Contains("AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Bookmarks"), "v0.11.1: a browser folder is not wiped whole when a Keep line matches inside it");
        Check(dEdge.Contains("AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\History"), "v0.11.1: ...and the rest of it (history) still goes");
        Directory.Delete(Path.Combine(fake, "AppData", "Local", "Microsoft", "Edge"), true);
        // 3. what a trace folder keeps is in the preview too
        File.WriteAllLines(Conf2, new[] { "*.kdbx" });
        Make("AppData/Roaming/Microsoft/Windows/Recent/mine.kdbx");
        Check(Dry().Kept.Contains("AppData\\Roaming\\Microsoft\\Windows\\Recent\\mine.kdbx"), "v0.11.1: a match kept in a trace folder is listed as kept in the preview");
        if (savedKeep != null) File.WriteAllText(Conf2, savedKeep); else File.Delete(Conf2);
        foreach (var d in new[] { "Documents/Old", "Documents/top.kdbx", "AppData/Local/Microsoft/Windows/Foo", "AppData/Roaming/Microsoft/Windows/Recent/mine.kdbx", "AppData/Roaming/Microsoft/Windows/Recent/folder" })
        { var p = Path.Combine(fake, d); if (Directory.Exists(p)) Directory.Delete(p, true); else if (File.Exists(p)) File.Delete(p); }
    }

    Console.WriteLine("v0.11.1 W3 keep.conf and settings.conf are written whole or not at all:");
    {
        var settingsF = Path.Combine(fake, ".amnesia", "settings.conf");
        var lastW3 = Conf2 + ".last";
        var savedKeep = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
        var savedSettings = File.ReadAllText(settingsF);
        var savedLast = File.Exists(lastW3) ? File.ReadAllText(lastW3) : null;
        File.WriteAllLines(Conf2, new[] { "# list", "Documents/A", "Documents/B" });
        // a write that cannot finish leaves the old file exactly as it was (the temp name is taken by a folder here)
        Directory.CreateDirectory(Conf2 + ".tmp"); Directory.CreateDirectory(settingsF + ".tmp");
        try { KeepList.Remove("Documents/A"); } catch { }
        Check(File.ReadAllLines(Conf2).Length == 3, "a failed Remove leaves keep.conf as it was");
        try { KeepList.Add("Documents/C"); } catch { }
        Check(File.ReadAllLines(Conf2).Length == 3, "a failed Add leaves keep.conf as it was");
        try { Conf.Set("W3KEY", "1"); } catch { }
        Check(File.ReadAllText(settingsF) == savedSettings, "a failed settings write leaves settings.conf as it was");
        Directory.Delete(Conf2 + ".tmp"); Directory.Delete(settingsF + ".tmp");
        Check(KeepList.Add("Documents/C") == "Documents/C" && KeepList.Paths().Count == 3 && !File.Exists(Conf2 + ".tmp"), "Add works and leaves no temp file");
        Conf.Set("W3KEY", "1");
        Check(Conf.Get("W3KEY") == "1" && !File.Exists(settingsF + ".tmp"), "settings write works and leaves no temp file");
        Conf.Set("W3KEY", null);
        // taking the last line off never leaves a zero byte file (that would read as "broken")
        File.WriteAllLines(Conf2, new[] { "Documents/A" });
        Check(KeepList.Remove("Documents/A") && new FileInfo(Conf2).Length > 0 && KeepList.Check(out _) == null && KeepList.Paths().Count == 0, "removing the last line leaves a readable list with no lines, not a zero byte file");
        // a zero byte keep.conf where there was a list stops the cleanup, like a missing one
        File.WriteAllLines(lastW3, new[] { "Documents/A" });
        File.WriteAllBytes(Conf2, Array.Empty<byte>());
        Check(KeepList.Check(out _) == "unreadable", "a zero byte keep.conf with a good last copy is not trusted");
        Check(Dry().Skipped == "keeplist-unreadable", "...the dry run says so");
        var stopW3 = Real("now");
        Check(stopW3.Skipped == "keeplist-unreadable" && File.ReadAllText(Conf2) == File.ReadAllText(lastW3), "...the real run stops, deletes nothing and puts the last good copy back");
        File.WriteAllBytes(Conf2, Array.Empty<byte>());
        File.WriteAllLines(lastW3, new[] { "# nothing kept" });
        Check(KeepList.Check(out _) == null, "a zero byte keep.conf is fine when the last copy kept nothing either");
        File.Delete(lastW3);
        Check(KeepList.Check(out _) == null, "...and on a new install (no last copy)");
        if (savedKeep != null) File.WriteAllText(Conf2, savedKeep); else File.Delete(Conf2);
        File.WriteAllText(settingsF, savedSettings);
        if (savedLast != null) File.WriteAllText(lastW3, savedLast);
    }

    Console.WriteLine("v0.11.1 W4 Keep lines written as full paths or with ~, and a relative KEEP_DIR:");
    {
        var settingsF = Path.Combine(fake, ".amnesia", "settings.conf");
        var savedKeep = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
        var savedSettings = File.ReadAllText(settingsF);
        foreach (var f in new[] { "Documents/Tilde/a.txt", "Documents/Abs/a.txt", "Documents/Fwd/a.txt", "Documents/Plain/a.txt", "Documents/RelKeep/a.txt", "Documents/Other/a.txt", "Documents/Slash/a.txt", "Documents/EnvA/a.txt", "Documents/EnvB/a.txt" }) Make(f);
        File.WriteAllLines(Conf2, new[] { "~/Documents/Tilde", fake + "\\Documents\\Abs", fake.Replace('\\', '/') + "/Documents/Fwd", "D:\\Elsewhere\\X", "../Outside", "~",
            "//Documents/Slash", "%USERPROFILE%\\Documents\\EnvA", "$HOME/Documents/EnvB" });
        var pw4 = KeepList.Paths();
        Check(pw4.SequenceEqual(new[] { "Documents/Tilde", "Documents/Abs", "Documents/Fwd", "Documents/Slash", "Documents/EnvA", "Documents/EnvB" }), "v0.11.1: ~/X, %USERPROFILE%/X, $HOME/X and full paths inside the user folder become profile-relative lines; a doubled slash still protects as before; the others are not applied");
        Check(KeepList.Ignored().Count == 3, "v0.11.1: lines that can never match (other drive, .., ~ alone) are reported");
        var r4 = Dry(); var d4 = Del(r4);
        Check(r4.Kept.Contains("Documents\\Tilde") && r4.Kept.Contains("Documents\\Abs") && r4.Kept.Contains("Documents\\Fwd") && r4.Kept.Contains("Documents\\Slash") && r4.Kept.Contains("Documents\\EnvA") && r4.Kept.Contains("Documents\\EnvB") && d4.Contains("Documents\\Plain"), "v0.11.1: such lines now protect what they name");
        Check(KeepList.Add("Documents/X/..") == null && KeepList.Add("../x") == null && KeepList.Paths().Count == 6, "v0.11.1: a line with .. is not written to the list");
        Check(Vault.AddFolder("~/../x") == null && Vault.AddFolder("../x") == null, "v0.11.1: the vault folder list refuses a path that climbs out too");
        // KEEP_DIR written by hand without ~/ or a full path is a folder in the user folder
        var sl = File.ReadAllLines(settingsF).Where(l => !l.StartsWith("KEEP_DIR=")).Append("KEEP_DIR=Documents\\RelKeep").ToArray();
        File.WriteAllLines(settingsF, sl);
        Check(Conf.KeepRel == "Documents/RelKeep" && Conf.KeepDir == Path.Combine(fake, "Documents", "RelKeep"), "v0.11.1: a hand-written relative KEEP_DIR means a folder in the user folder");
        File.WriteAllLines(Conf2, new[] { "# nothing" });
        var r4b = Dry();
        Check(r4b.Kept.Contains("Documents\\RelKeep") && Del(r4b).Contains("Documents\\Other"), "v0.11.1: ...and it keeps its protection");
        File.WriteAllLines(settingsF, sl.Where(l => !l.StartsWith("KEEP_DIR=")).Append("KEEP_DIR=..\\Elsewhere"));
        Check(Conf.KeepRel == "Keep", "v0.11.1: a KEEP_DIR that climbs out of the user folder falls back to Keep");
        foreach (var odd in new[] { "./AppData/Roaming", "./.amnesia", "Documents/./../AppData" })
        {
            File.WriteAllLines(settingsF, sl.Where(l => !l.StartsWith("KEEP_DIR=")).Append("KEEP_DIR=" + odd));
            Check(Conf.KeepRel == "Keep", "v0.11.1: KEEP_DIR=" + odd + " does not slip past the AppData and .amnesia rules");
        }
        foreach (var d in new[] { "Tilde", "Abs", "Fwd", "Plain", "RelKeep", "Other", "Slash", "EnvA", "EnvB" }) Directory.Delete(Path.Combine(fake, "Documents", d), true);
        File.WriteAllText(settingsF, savedSettings);
        if (savedKeep != null) File.WriteAllText(Conf2, savedKeep); else File.Delete(Conf2);
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

    Console.WriteLine("v0.8.1 sign out order (your own folders first, Temp last):");
    var ord = CleanEngine.Order(new[] { new CleanItem(@"AppData\Local\Temp\a.tmp", "file"), new CleanItem("Registry: x", "trace"), new CleanItem(@"AppData\Roaming\Chat", "folder"),
        new CleanItem(@"Downloads\movie.mp4", "file"), new CleanItem(@"Documents\Projects", "folder"), new CleanItem(@"AppData\Local\Temp\big", "folder") }).Select(i => i.Path).ToList();
    Check(ord.SequenceEqual(new[] { @"Documents\Projects", @"Downloads\movie.mp4", @"AppData\Roaming\Chat", @"AppData\Local\Temp\big", @"AppData\Local\Temp\a.tmp", "Registry: x" }), "own folders, then app data, then Temp; folders before files");
    Make("Downloads/o1.txt"); Make("AppData/Local/Temp/o2.tmp");
    var listed = new CleanEngine().Run("logout", true).Items.Select(i => i.Path).ToList();
    Check(listed.IndexOf(@"Downloads\o1.txt") >= 0 && listed.IndexOf(@"Downloads\o1.txt") < listed.IndexOf(@"AppData\Local\Temp\o2.tmp"), "the real list is in that order");

    Console.WriteLine("v0.8.1 a new app's program folder waits 3 days in the trash (ZZTesApp test):");
    foreach (var d in Directory.Exists(Path.Combine(fake, ".amnesia-trash")) ? Directory.GetDirectories(Path.Combine(fake, ".amnesia-trash")) : Array.Empty<string>()) Directory.Delete(d, true);
    Make("AppData/Local/ZZTesApp/app.exe"); Make("AppData/Local/Programs/antigravity/Antigravity.exe"); Make("AppData/Roaming/OldApp/x"); Make("AppData/Local/Programs/Other/x.exe");
    var withApps = new CleanEngine { Fast = true, NewAppFolders = () => new[] { F("AppData/Local/ZZTesApp"), F("AppData/Local/Programs/antigravity") + "/", Path.GetTempPath(), F("AppData"), F("AppData/Local"), F("AppData/Local/Programs") } };
    var r81 = withApps.Run("logout", false);
    var appTrash = Directory.GetDirectories(Path.Combine(fake, ".amnesia-trash")).Where(d => d.EndsWith("-apps")).ToList();
    Check(r81.Skipped == null && !There("AppData/Local/ZZTesApp") && appTrash.Any(d => File.Exists(Path.Combine(d, "AppData", "Local", "ZZTesApp", "app.exe"))), "ZZTesApp went to the 3-day trash, not the normal one");
    Check(appTrash.Any(d => File.Exists(Path.Combine(d, "AppData", "Local", "Programs", "antigravity", "Antigravity.exe"))), "an app in AppData\\Local\\Programs too");
    Check(!There("AppData/Roaming/OldApp") && !appTrash.Any(d => Directory.Exists(Path.Combine(d, "AppData", "Roaming", "OldApp"))), "other app data goes to the normal trash");
    Check(!There("AppData/Local/Programs/Other") && !appTrash.Any(d => Directory.Exists(Path.Combine(d, "AppData", "Local", "Programs", "Other"))), "a shared folder (Programs) as program folder changes nothing");
    var trace81 = File.ReadAllText(Path.Combine(fake, ".amnesia/trace.log"));
    Check(trace81.Contains("new app folders moved to the trash for 3 days: 2") && !trace81.Contains("ZZTesApp"), "trace.log says so, without names");
    Real("login");
    Check(appTrash.All(Directory.Exists) && !Directory.GetDirectories(Path.Combine(fake, ".amnesia-trash")).Any(d => !d.EndsWith("-apps")), "the sign in check empties the normal trash and keeps these 3 days");

    Console.WriteLine("v0.11.1 W5 a new app's folder that could not go to the 3-day trash is not deleted:");
    {
        var trashP = Path.Combine(fake, ".amnesia-trash");
        if (Directory.Exists(trashP)) Directory.Delete(trashP, true);
        File.WriteAllText(trashP, "blocked"); // a file where the trash folder should be: nothing can be moved into it
        Make("AppData/Local/ZZTesApp2/app.exe"); Make("AppData/Local/ZZTesApp2/lib.dll");
        var engW5 = new CleanEngine { Fast = true, NewAppFolders = () => new[] { F("AppData/Local/ZZTesApp2") } };
        var rW5 = engW5.Run("logout", false);
        Check(There("AppData/Local/ZZTesApp2/app.exe") && There("AppData/Local/ZZTesApp2/lib.dll"), "v0.11.1: the folder stays whole when the safety-net move failed");
        Check(rW5.Failed >= 1, "v0.11.1: ...and counts as could not be deleted");
        File.Delete(trashP);
        if (Directory.Exists(Path.Combine(fake, "AppData", "Local", "ZZTesApp2"))) Directory.Delete(Path.Combine(fake, "AppData", "Local", "ZZTesApp2"), true);
    }

    Console.WriteLine("v0.11.1 W7 the trash is emptied on Turn Off and on uninstall:");
    {
        var trashP = Path.Combine(fake, ".amnesia-trash");
        if (Directory.Exists(trashP)) Directory.Delete(trashP, true);
        Directory.CreateDirectory(Path.Combine(trashP, "20260101-000000", "Documents"));
        File.WriteAllText(Path.Combine(trashP, "20260101-000000", "Documents", "wiped.txt"), "x");
        Directory.CreateDirectory(Path.Combine(trashP, "20260101-000001-apps", "AppData"));
        File.WriteAllText(Path.Combine(trashP, "20260101-000001-apps", "AppData", "app.exe"), "x");
        CleanEngine.PurgeTrash(false);
        Check(!Directory.Exists(Path.Combine(trashP, "20260101-000000")) && Directory.Exists(Path.Combine(trashP, "20260101-000001-apps")), "Turn Off: wiped files are gone, a new app's folder keeps its 3 days");
        CleanEngine.PurgeTrash(true);
        Check(!Directory.Exists(trashP), "uninstall: everything in the trash is gone, and the trash folder too");
        CleanEngine.PurgeTrash(true);
        Check(!Directory.Exists(trashP), "...and an empty or missing trash is fine");
    }

    Console.WriteLine("v0.11.1 W8 an update is only installed when it is newer:");
    Check(UpdateSig.IsNewer("0.12.0", "0.11.1") && UpdateSig.IsNewer("1.0", "0.99.9"), "a newer version counts");
    Check(!UpdateSig.IsNewer("0.11.1", "0.11.1") && !UpdateSig.IsNewer("0.10.0", "0.11.1"), "the same or an older (replayed) release does not");
    Check(!UpdateSig.IsNewer("not-a-version", "0.11.1") && !UpdateSig.IsNewer("0.12.0", "x"), "a version that cannot be read does not");

    Console.WriteLine("v0.11.1 follow-up fixes:");
    {
        var settingsF = Path.Combine(fake, ".amnesia", "settings.conf");
        var savedSettings = File.ReadAllText(settingsF);
        var savedKeep = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
        var lastA = Conf2 + ".last";
        var savedLast = File.Exists(lastA) ? File.ReadAllText(lastA) : null;
        var sl = File.ReadAllLines(settingsF).Where(l => !l.StartsWith("KEEP_DIR=")).ToArray();
        // 1. a KEEP_DIR with .. that still lands inside the user folder is that folder (v0.9 behaviour), never a fall back to Keep
        Make("Stuff/a.txt"); Make("Documents/Gone/a.txt");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=~/Documents/../Stuff"));
        File.WriteAllLines(Conf2, new[] { "# nothing" });
        Check(Conf.KeepRel == "Stuff" && Conf.KeepDir == Path.Combine(fake, "Stuff"), "follow-up 1: KEEP_DIR=~/Documents/../Stuff is the folder Stuff");
        var rA1 = Dry();
        Check(rA1.Kept.Contains("Stuff") && !Del(rA1).Contains("Stuff") && Del(rA1).Contains("Documents\\Gone"), "follow-up 1: ...and Stuff is protected, not wiped");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=Documents/../../Outside"));
        Check(Conf.KeepRel == "Keep", "follow-up 1: a path that climbs out of the user folder is still Keep");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=Documents/./../AppData/X"));
        Check(Conf.KeepRel == "Keep", "follow-up 1: ...and one that resolves into AppData too");
        File.WriteAllText(settingsF, savedSettings);
        Directory.Delete(Path.Combine(fake, "Stuff"), true); Directory.Delete(Path.Combine(fake, "Documents", "Gone"), true);

        // 2. the "leftover" state: nothing is deleted before the password is right; a file saved there later is not lost; no unpacked copy stays
        foreach (var old in Directory.GetDirectories(Path.Combine(fake, "Keep"), "Safe recovered*")) Directory.Delete(old, true); // left by an earlier test
        var pw = "correct horse battery safe";
        Safe.Create(pw);
        Make("Keep/Safe/a.txt");
        Safe.Close("test");
        var markerF = Path.Combine(fake, ".amnesia", "safe", "open.marker");
        Directory.CreateDirectory(Path.Combine(fake, "Keep", "Safe"));
        Make("Keep/Safe/a.txt"); Make("Keep/Safe/new-after.txt");
        Make("Keep/Safe/old-copied.txt"); // copied in with an old date: dates cannot tell it from the leftover copy
        var aTxt = Path.Combine(fake, "Keep", "Safe", "a.txt");
        File.SetLastWriteTimeUtc(aTxt, DateTime.UtcNow.AddMinutes(-20));
        File.SetLastWriteTimeUtc(Path.Combine(fake, "Keep", "Safe", "old-copied.txt"), DateTime.UtcNow.AddMinutes(-30));
        // the close wrote down what was left (path, size, date): only exactly that is the packed copy
        File.WriteAllLines(markerF, new[] { "leftover", "a.txt|" + new FileInfo(aTxt).Length + "|" + new FileInfo(aTxt).LastWriteTimeUtc.Ticks });
        try { Safe.Open("wrong wrong wrong"); Check(false, "follow-up 2: wrong password"); } catch (VaultError) { }
        Check(There("Keep/Safe/a.txt") && There("Keep/Safe/new-after.txt"), "follow-up 2: a wrong password deletes nothing");
        Check(Safe.Open(pw) == 1 && There("Keep/Safe/a.txt") && !There("Keep/Safe/new-after.txt"), "follow-up 2: the right password replaces the leftovers with the real contents");
        var recovered = Directory.GetDirectories(Path.Combine(fake, "Keep"), "Safe recovered*");
        Check(recovered.Length == 1 && File.Exists(Path.Combine(recovered[0], "new-after.txt")) && File.Exists(Path.Combine(recovered[0], "old-copied.txt")) && !File.Exists(Path.Combine(recovered[0], "a.txt")),
            "follow-up 2: a file that is not exactly the packed copy (new, or copied in with an old date) is moved to 'Safe recovered', not deleted");
        Safe.Close("test");
        foreach (var d in recovered) Directory.Delete(d, true);
        File.WriteAllText(Path.Combine(fake, "Keep", "Safe"), "in the way");
        try { Safe.Open(pw); Check(false, "follow-up 2: Open with something in the way"); } catch (Exception) { }
        Check(!Directory.Exists(Path.Combine(fake, "Keep", "Safe.opening")), "follow-up 2: a failed Open leaves no unpacked copy behind");
        File.Delete(Path.Combine(fake, "Keep", "Safe"));

        // 2b. the list of what is left is taken when each file is read (a file saved while the rest is being packed is not "the packed copy")
        if (OperatingSystem.IsWindows())
        {
            foreach (var old in Directory.GetDirectories(Path.Combine(fake, "Keep"), "Safe recovered*")) Directory.Delete(old, true);
            Safe.Open(pw);
            Make("Keep/Safe/busy.txt");
            var busyPath = Path.Combine(fake, "Keep", "Safe", "busy.txt");
            FileStream? h = null;
            try
            {
                // after the pack read the file, a program opens it, saves into it and keeps it open (so it cannot be deleted)
                Safe.AfterPackTest = () => { h = new FileStream(busyPath, FileMode.Open, FileAccess.ReadWrite, FileShare.ReadWrite); h.Seek(0, SeekOrigin.End); h.Write(System.Text.Encoding.UTF8.GetBytes(" saved while packing")); h.Flush(); };
                Safe.Close("test");
            }
            finally { Safe.AfterPackTest = null; h?.Dispose(); }
            Check(There("Keep/Safe/busy.txt") && !Safe.IsOpen, "follow-up 2b: a file in use keeps part of the open copy after a close (leftover)");
            Check(Safe.Open(pw) >= 1, "follow-up 2b: Open replaces the leftovers");
            var rec2 = Directory.GetDirectories(Path.Combine(fake, "Keep"), "Safe recovered*");
            Check(rec2.Length == 1 && File.Exists(Path.Combine(rec2[0], "busy.txt")) && File.ReadAllText(Path.Combine(rec2[0], "busy.txt")).Contains("saved while packing"), "follow-up 2b: the version saved while packing is moved to 'Safe recovered', not deleted");
            Safe.Close("test");
            foreach (var d in rec2) Directory.Delete(d, true);
        }

        // 2c. a marker that cannot be read or has nothing readable in it never makes the folder "open" (a partial copy must not be packed over the safe)
        {
            Safe.Open(pw);
            var before2c = File.ReadAllBytes(Safe.File_);
            File.WriteAllText(markerF, "");
            Check(!Safe.IsOpen && Safe.Close("test") == -1 && File.ReadAllBytes(Safe.File_).SequenceEqual(before2c), "follow-up 2c: an empty marker is not 'open': nothing is packed over the safe");
            if (OperatingSystem.IsWindows())
            {
                using (new FileStream(markerF, FileMode.Open, FileAccess.Read, FileShare.None))
                    Check(!Safe.IsOpen && Safe.Close("test") == -1 && File.ReadAllBytes(Safe.File_).SequenceEqual(before2c), "follow-up 2c: a marker that cannot be read is not 'open' either");
            }
            File.WriteAllText(markerF, "open");
            // the marker cannot be rewritten: the close must leave the open copy whole (nothing deleted)
            File.SetAttributes(markerF, FileAttributes.ReadOnly);
            try { Safe.Close("test"); } catch (Exception) { }
            File.SetAttributes(markerF, FileAttributes.Normal);
            Check(There("Keep/Safe/a.txt") && Safe.IsOpen, "follow-up 2d: if the state cannot be written down, the open copy is not deleted");
            Safe.Close("test");
        }

        // 2e. links or cloud placeholders in the open copy are never packed: the open copy stays instead of being deleted
        if (OperatingSystem.IsWindows())
        {
            Safe.Open(pw);
            Directory.CreateDirectory(Path.Combine(fake, "Documents", "LinkTarget")); Make("Documents/LinkTarget/t.txt");
            var link = Path.Combine(fake, "Keep", "Safe", "lnk");
            using (var mk = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", "/c mklink /J \"" + link + "\" \"" + Path.Combine(fake, "Documents", "LinkTarget") + "\"") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!) { mk.StandardOutput.ReadToEnd(); mk.WaitForExit(); }
            if (Directory.Exists(link))
            {
                Safe.Close("test");
                Check(Directory.Exists(Path.Combine(fake, "Keep", "Safe")) && Safe.IsOpen && File.Exists(Path.Combine(fake, "Documents", "LinkTarget", "t.txt")), "follow-up 2e: a link inside the open copy keeps the copy open (it was not packed), and its target is untouched");
                Directory.Delete(link); // removes the junction only
                Safe.Close("test");
            }
            Directory.Delete(Path.Combine(fake, "Documents", "LinkTarget"), true);
        }

        // 3. an open safe from before the marker that cannot be listed (locked Keep) still counts as open
        if (OperatingSystem.IsWindows())
        {
            Safe.Open(pw);
            File.Delete(markerF);
            Make("Keep/Safe/legacy.txt");
            var dirA = Path.Combine(fake, "Keep", "Safe");
            void Icacls(string args) { using var pr = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("icacls", args) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!; pr.StandardOutput.ReadToEnd(); pr.WaitForExit(); }
            Icacls("\"" + dirA + "\" /deny \"" + Environment.UserName + "\":(RD)");
            var packedBefore = File.ReadAllBytes(Safe.File_);
            try
            {
                Check(Safe.IsOpen, "follow-up 3: an open safe whose folder cannot be listed is still open (not mistaken for a stray folder)");
                try { Safe.Close("test"); } catch (Exception) { }
                Check(File.ReadAllBytes(Safe.File_).SequenceEqual(packedBefore) && Safe.Count != 0, "follow-up 3: closing a folder that cannot be listed never packs it empty over the safe");
            }
            finally { Icacls("\"" + dirA + "\" /remove:d \"" + Environment.UserName + "\""); }
            Safe.Close("test");
        }
        Safe.Delete(pw);

        // KEEP_DIR names Windows reads as another name: trailing dots and spaces are dropped, a name that only starts like AppData is its own
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=~/Stuff."));
        Check(Conf.KeepRel == "Stuff", "follow-up: KEEP_DIR=~/Stuff. is the folder Stuff (Windows drops the trailing dot)");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=~/Docs/..."));
        Check(Conf.KeepRel == "Docs", "follow-up: a segment of only dots is not a folder name");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=~/AppDataX"));
        Check(Conf.KeepRel == "AppDataX", "follow-up: AppDataX is not AppData");
        File.WriteAllLines(settingsF, sl.Append("KEEP_DIR=~/appdata/Roaming/Y"));
        Check(Conf.KeepRel == "Keep", "follow-up: AppData (any case) still falls back to Keep");
        File.WriteAllText(settingsF, savedSettings);

        // 4. the app itself never writes a zero byte keep.conf; a zero byte one with a good last copy is put back
        File.WriteAllLines(Conf2, new[] { "Documents/A", "Documents/B" });
        File.WriteAllLines(lastA, new[] { "Documents/A", "Documents/B" });
        var pv = Modes.Preview("custom", null, new[] { "Documents/A", "Documents/B" }, dryRun: false);
        Check(pv.Problem == null && Modes.Commit(pv) && new FileInfo(Conf2).Length > 0 && KeepList.Check(out _) == null, "follow-up 4: taking every line off in a mode switch leaves a readable list, not a zero byte file");
        File.WriteAllBytes(Conf2, Array.Empty<byte>());
        File.WriteAllLines(lastA, new[] { "Documents/A", "Documents/B" });
        Check(KeepList.Add("Documents/C") == "Documents/C" && KeepList.Paths().Contains("Documents/A") && KeepList.Paths().Contains("Documents/B"), "follow-up 5: adding a line to a zero byte keep.conf puts the last good copy back first");
        File.WriteAllBytes(Conf2, Array.Empty<byte>());
        var stopA = Real("now");
        Check(stopA.Skipped == "keeplist-unreadable" && new FileInfo(Conf2).Length > 0 && KeepList.Paths().Contains("Documents/B"), "follow-up 5: a stopped run puts the last good copy back, so the next cleanup has its list");

        if (savedKeep != null) File.WriteAllText(Conf2, savedKeep); else File.Delete(Conf2);
        if (savedLast != null) File.WriteAllText(lastA, savedLast); else File.Delete(lastA);
    }

    Console.WriteLine("v0.8.1 new apps list:");
    Check(NewApps.BaseName("Surfshark 6.20.0999") == "Surfshark" && NewApps.BaseName("Antigravity 2.24.0") == "Antigravity" && NewApps.BaseName("7-Zip 24.08 (x64)") == "7-Zip" && NewApps.BaseName("Notepad++") == "Notepad++", "the version is not part of the name");
    var bl = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "machine:Surfshark 6.13.0999", "user:Discord", "start:Discord.lnk", "reg:*listed" };
    Check(!NewApps.IsNew("machine:Surfshark 6.20.0999", bl) && !NewApps.IsNew("user:Discord", bl), "an app that was only updated is not new (Surfshark 6.13 to 6.20)");
    Check(NewApps.IsNew("user:Antigravity 2.24.0", bl) && NewApps.IsNew("machine:Surfshark Helper 1.0", bl) && NewApps.IsNew("user:Surfshark 6.20.0999", bl), "a really new app is new (other name or other kind)");
    var guid = "121a0be4-63bd-531e-acf8-fc3924c7e984";
    var loc81 = @"C:\Users\x\AppData\Local\Programs\antigravity";
    Check(NewApps.IsGuid(guid) && NewApps.RegName(guid, "Antigravity", null, loc81) == "Antigravity" && NewApps.RegName(guid, null, null, loc81 + "\\") == "antigravity"
          && NewApps.RegName("Discord", "Other", null, null) == "Discord" && NewApps.RegName(guid, null, null, null) == guid, "a registry key named by a GUID gets a real name");
    var groups81 = NewApps.Group(new[]
    {
        new AppRow("start:Antigravity.lnk", "start", "Antigravity", null), new AppRow("user:{X}_is1", "user", "Antigravity 2.24.0", loc81),
        new AppRow("reg:" + guid, "reg", "Antigravity", loc81 + "\\"), new AppRow("user:Discord", "user", "Discord", null),
        new AppRow("machine:Microsoft Teams", "machine", "Microsoft Teams", null), new AppRow("machine:Microsoft Edge", "machine", "Microsoft Edge", null),
        new AppRow("start:Microsoft Teams.lnk", "start", "Microsoft Teams", null),
    });
    var ag = groups81.FirstOrDefault(g => g.Any(r => r.Id == "start:Antigravity.lnk"));
    Check(ag != null && ag.Count == 3 && NewApps.GroupName(ag) == "Antigravity 2.24.0", "Antigravity: 3 rows, one line, named after its uninstall entry");
    Check(groups81.Count == 4 && groups81.Any(g => g.Count == 2 && g.All(r => r.Name == "Microsoft Teams")), "Teams and Edge stay two apps; Teams' shortcut joins Teams");
    var home81 = OperatingSystem.IsWindows() ? @"C:\Users\x" : "/home/x";
    string H81(string rel) => home81 + (OperatingSystem.IsWindows() ? "\\" + rel.Replace('/', '\\') : "/" + rel);
    var kp = NewApps.KeepPaths("Antigravity 2.24.0", "Google", new[] { H81("AppData/Local/Programs/antigravity"), null, H81("AppData/Local/Programs"), @"D:\Apps\Antigravity", H81("AppData/Local/Programs/Amnesia") },
        new[] { "AppData/Roaming/Antigravity", "AppData/Local/Programs", "AppData/Roaming/Code", "AppData/Local/Programs/antigravity" }, home81);
    Check(kp.SequenceEqual(new[] { "AppData/Local/Programs/antigravity", "AppData/Roaming/Antigravity" }), "Keep on a new app keeps its program folder and its data folder");
    Check(NewApps.KeepPaths("Tool", null, new[] { H81("AppData/Local") }, Array.Empty<string>(), home81).Count == 0, "...never a whole AppData folder");
    Check(AppMatch.Technical("Sentry") && AppMatch.Technical("AMD_Common") && AppMatch.Technical("CrashDumps") && !AppMatch.Technical("Surfshark") && !AppMatch.Technical("discord"), "Keep List chips: technical folders are not suggested as apps");

    // ---------- v0.9 safety (winsafe): Keep List stop + last good copy, one check before every delete, could not tell = keep, delete catalog ----------
    Console.WriteLine("v0.9 safety:");
    {
        var setFile9 = Path.Combine(fake, ".amnesia/settings.conf");
        var setOld9 = File.ReadAllText(setFile9);
        var keepOld9 = File.Exists(Conf2) ? File.ReadAllText(Conf2) : null;
        var last9 = Conf2 + ".last";
        var hist9 = Path.Combine(fake, ".amnesia/history.log");
        string Hist9() => File.Exists(hist9) ? File.ReadAllText(hist9) : "";
        string Trace9() => File.ReadAllText(Path.Combine(fake, ".amnesia/trace.log"));
        Settings("ENABLED=1", $"APP_PATH={exe}");
        Make("AppData/Local/Programs/Amnesia/Amnesia.exe");
        File.WriteAllLines(Conf2, new[] { "# v0.9", ".ssh", "Documents/Taxes" });
        if (File.Exists(last9)) File.Delete(last9);

        // 158: the last good copy
        Check(Dry().Skipped == null, "158: no keep.conf.last yet: a dry run runs as before");
        Make("Downloads/a9.txt");
        var run9 = Real("now");
        Check(run9.Skipped == null && !There("Downloads/a9.txt"), "158: a normal real run still cleans");
        Check(File.Exists(last9) && File.ReadAllText(last9) == File.ReadAllText(Conf2), "158: after a real run keep.conf.last is a copy of keep.conf");
        Check(!File.Exists(last9 + ".tmp"), "158: no half written copy is left");

        // missing
        var good9 = File.ReadAllText(Conf2);
        File.Delete(Conf2);
        Make("Downloads/b9.txt");
        var dry9 = Dry();
        Check(dry9.Skipped == "keeplist-missing" && dry9.Items.Count == 0 && !File.Exists(Conf2), "158: keep.conf gone: the dry run says keeplist-missing and changes nothing");
        var stop9 = Real("logout");
        Check(stop9.Skipped == "keeplist-missing" && There("Downloads/b9.txt"), "158: keep.conf gone: the real run stops and deletes nothing");
        Check(Hist9().Contains("\tstopped\tlogout keeplist-missing"), "158: History: stopped logout keeplist-missing");
        Check(Trace9().Contains("stop: keep list missing") && !Trace9().Contains("b9.txt"), "158: trace.log says why, without file names");
        Check(File.Exists(Conf2) && File.ReadAllText(Conf2) == good9, "158: keep.conf comes back from the last good copy");
        Check(Real("login").Skipped == null && !There("Downloads/b9.txt"), "158: the next run cleans again with the restored list");
        Check(There(".ssh/id_ed25519") || !There(".ssh"), "158: the restored list still protects .ssh");

        // unreadable (broken: zero bytes inside, like after a power cut)
        File.WriteAllBytes(Conf2, new byte[] { 0, 0, 0, 0 });
        Make("Downloads/c9.txt");
        Check(Dry().Skipped == "keeplist-unreadable", "158: a broken keep.conf: the dry run says keeplist-unreadable");
        var stopU9 = Real("now");
        Check(stopU9.Skipped == "keeplist-unreadable" && There("Downloads/c9.txt"), "158: a broken keep.conf: the real run stops and deletes nothing");
        Check(Hist9().Contains("\tstopped\tnow keeplist-unreadable"), "158: History: stopped now keeplist-unreadable");
        Check(File.ReadAllText(last9) == good9, "158: a stopped run never overwrites the last good copy");
        File.WriteAllText(Conf2, good9);

        // KeepList.Add on a lost keep.conf puts the old list back first
        File.Delete(Conf2);
        KeepList.Add("Pictures/Mine");
        var lines9 = File.ReadAllLines(Conf2);
        Check(lines9.Contains(".ssh") && lines9.Contains("Pictures/Mine"), "158: adding to a lost Keep List brings the old lines back first");
        File.WriteAllText(Conf2, good9);

        // 159: one check before every move or delete
        string F9(string rel) => Path.Combine(fake, rel.Replace('/', Path.DirectorySeparatorChar));
        Make("Keep/k9.txt"); Make(".amnesia-trash/old9/x.txt"); Make("Documents/d9.txt");
        Check(CleanEngine.Refuse(fake) == "home" && CleanEngine.Refuse(fake + Path.DirectorySeparatorChar) == "home", "159: never the user folder itself");
        Check(CleanEngine.Refuse(Path.GetTempPath()) == "outside" && CleanEngine.Refuse(fake + "-other" + Path.DirectorySeparatorChar + "x") == "outside", "159: never outside the user folder (a look-alike name too)");
        Check(CleanEngine.Refuse("Downloads/x") == "outside", "159: a path that is not full is refused");
        Check(CleanEngine.Refuse(F9(".amnesia")) == "amnesia" && CleanEngine.Refuse(F9(".amnesia/settings.conf")) == "amnesia", "159: never .amnesia or what is in it");
        Check(CleanEngine.Refuse(F9(".amnesia-trash")) == "trash" && CleanEngine.Refuse(F9(".amnesia-trash/old9")) == null, "159: never the trash folder itself, what is inside it may go");
        Check(CleanEngine.Refuse(F9("Keep")) == "keep" && CleanEngine.Refuse(F9("Keep/k9.txt")) == "keep", "159: never the Keep folder or what is in it");
        Check(CleanEngine.Refuse(F9("Keep/k9.txt"), insideKeep: true) == null && CleanEngine.Refuse(F9("Keep"), insideKeep: true) == "keep", "159: inside Keep only when asked (Care), never Keep itself");
        Check(CleanEngine.Refuse(F9("Documents/../Keep")) == "dots" && CleanEngine.Refuse(F9("Downloads") + Path.DirectorySeparatorChar + ".." + Path.DirectorySeparatorChar + "Downloads") == "dots", "159: a path with .. is refused");
        Check(CleanEngine.Refuse(F9("Documents/d9.txt")) == null && CleanEngine.Refuse(F9("Documents/nothing9.txt")) == "gone", "159: a normal file may go, a missing one is 'gone'");
        Check(!CleanEngine.SafeDelete(F9("Keep")) && There("Keep/k9.txt") && !CleanEngine.SafeDelete(fake) && There("Documents/d9.txt"), "159: SafeDelete refuses Keep and the user folder");
        Check(!CleanEngine.ToTrash(F9("Keep/k9.txt")) && There("Keep/k9.txt"), "159: ToTrash refuses Keep");
        Settings("ENABLED=1", $"APP_PATH={exe}", "KEEP_DIR=~/Documents/Safe9");
        Make("Documents/Safe9/s.txt");
        Check(CleanEngine.Refuse(F9("Documents")) == "keep" && CleanEngine.Refuse(F9("Documents/Safe9")) == "keep" && CleanEngine.Refuse(F9("Documents/d9.txt")) == null, "159: never a folder that holds the Keep folder");
        Settings("ENABLED=1", $"APP_PATH={exe}");
        // links (symbolic links on Linux are reparse points to .NET, like junctions on Windows)
        var outside9 = Path.Combine(Path.GetTempPath(), "amnesia-out-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(outside9); File.WriteAllText(Path.Combine(outside9, "precious.txt"), "x");
        bool links9 = true;
        try { Directory.CreateSymbolicLink(F9("Documents/link9"), outside9); } catch { links9 = false; }
        if (links9)
        {
            Check(CleanEngine.Refuse(F9("Documents/link9")) == "link" && CleanEngine.Refuse(F9("Documents/link9/precious.txt")) == "link", "159: a link and anything reached through it are refused");
            Check(!CleanEngine.SafeDelete(F9("Documents/link9/precious.txt")) && File.Exists(Path.Combine(outside9, "precious.txt")), "159: nothing is deleted through a link");
            Directory.Delete(F9("Documents/link9"));
            // a .amnesia-trash that is a link is never emptied
            var trashOld9 = F9(".amnesia-trash");
            CleanEngine.Delete(trashOld9);
            Directory.CreateSymbolicLink(trashOld9, outside9);
            typeof(CleanEngine).GetMethod("Purge", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!.Invoke(null, null);
            Check(File.Exists(Path.Combine(outside9, "precious.txt")), "159: a .amnesia-trash that is a link is never emptied");
            Directory.Delete(trashOld9);
        }
        else Check(true, "159: links can't be made here (skipped)");
        try { Directory.Delete(outside9, true); } catch { }

        // 160: could not tell = it stays
        Make("Projects9/main.c"); Make("Downloads/e9.txt");
        var cloud9 = new CleanEngine { CloudRoots = () => throw new IOException("registry denied") }.Run("now", true);
        var cd9 = cloud9.Items.Select(i => i.Path).ToList();
        Check(!cd9.Contains("Projects9") && cloud9.Kept.Contains("Projects9") && cd9.Contains("Downloads\\e9.txt"), "160: cloud folders unknown: your own top level folders stay, the rest is wiped as usual");
        Check(new CleanEngine().Run("now", true).Items.Any(i => i.Path == "Projects9"), "160: with the cloud check working that folder goes as before");
        Make("AppData/Roaming/Tool9/data.bin");
        var apps9 = new CleanEngine { NewAppFolders = () => throw new UnauthorizedAccessException() }.Run("now", false);
        var waiting9 = Directory.GetDirectories(F9(".amnesia-trash")).Where(d => d.EndsWith("-apps")).Any(d => File.Exists(Path.Combine(d, "AppData", "Roaming", "Tool9", "data.bin")));
        Check(apps9.Skipped == null && waiting9, "160: new app list failed: AppData folders wait 3 days in the trash instead of going for good");
        Check(Trace9().Contains("new app list failed") && !Trace9().Contains("Tool9"), "160: trace.log says so, without names");
        Make("AppData/Roaming/Tool9b/x.bin");
        var rules9 = new CleanEngine();
        Check(rules9.MayRemoveAppFolder(F9("AppData/Roaming/Tool9b")), "160: Remove new apps may take a normal program folder");
        File.WriteAllBytes(Conf2, new byte[] { 0, 0 });
        Check(!new CleanEngine().MayRemoveAppFolder(F9("AppData/Roaming/Tool9b")), "160: Keep List unreadable: Remove new apps takes nothing");
        File.WriteAllText(Conf2, good9);
        Check(!new CleanEngine { CloudRoots = () => throw new IOException() }.MayRemoveAppFolder(F9("AppData/Roaming/Tool9b")), "160: cloud folders unknown: Remove new apps takes nothing");

        // 163: catalog. Only the approved helpers may delete for good (CleanEngine.Delete, and the pause file).
        string? src9 = null;
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
            for (var d = new DirectoryInfo(start); d != null && src9 == null; d = d.Parent)
                if (File.Exists(Path.Combine(d.FullName, "src", "Amnesia.Core", "CleanEngine.cs"))) src9 = Path.Combine(d.FullName, "src", "Amnesia.Core");
                else if (File.Exists(Path.Combine(d.FullName, "windows", "src", "Amnesia.Core", "CleanEngine.cs"))) src9 = Path.Combine(d.FullName, "windows", "src", "Amnesia.Core");
        Check(src9 != null, "163: the Core source files are found");
        if (src9 != null)
        {
            var bad9 = new List<string>();
            foreach (var name in new[] { "CleanEngine.cs", "Care.cs" })
            {
                var file = Path.Combine(src9, name);
                if (!File.Exists(file)) continue;
                bad9.AddRange(DeleteCatalog.Find(File.ReadAllLines(file), name == "CleanEngine.cs" ? new[] { "Delete" } : Array.Empty<string>()).Select(x => $"{name}: {x}"));
            }
            foreach (var b in bad9) Console.WriteLine("        " + b);
            Check(bad9.Count == 0, "163: no File.Delete or recursive Directory.Delete outside CleanEngine.Delete (and the pause file)");
            var probe9 = new[]
            {
                "    public static bool Delete(string p)", "    {", "        File.Delete(p);", "    }",
                "    static void Other()", "    {", "        Directory.Delete(x, true); // gone", "        new DirectoryInfo(x).Delete(true);",
                "        File.Delete(y);", "        Directory.Delete(z);", "        // File.Delete(comment)", "        try { File.Delete(Conf.PauseFile); } catch { }", "    }",
            };
            Check(DeleteCatalog.Find(probe9, new[] { "Delete" }).Count == 3, "163: the catalog check itself finds a bad delete (and lets the allowed ones be)");
        }

        // back to how it was
        File.WriteAllText(setFile9, setOld9);
        if (keepOld9 != null) File.WriteAllText(Conf2, keepOld9); else File.Delete(Conf2);
        if (File.Exists(last9)) File.Delete(last9);
    }

    Console.WriteLine("Doomsday:");
    try { Vault.Restore("wrong password 1"); } catch (VaultError) { }
    try { Vault.Restore("wrong password 2"); Check(false, "last try warning"); } catch (VaultError e) { Check(e.Code == "wrong" && e.Left == 1, "one try left"); }
    try { Vault.Restore("wrong password 3"); Check(false, "third wrong password"); } catch (VaultError e) { Check(e.Code == "doomsday", "third wrong password: vault deleted"); }
    Check(!Vault.Exists && There("Keep/important.txt"), "vault gone, Keep stays");
    Check(Vault.Chosen().Count == 0, "v0.6: a new vault starts with no apps ticked");
    ProfilesTests.Run(fake, Check, Make, There);
    Vault.Create("correct horse battery", "red balloon", panicFull: true);
    try { Vault.CheckPassword("red balloon"); Check(false, "panic word"); } catch (VaultError e) { Check(e.Code == "doomsday", "panic word deletes the vault"); }
    Check(!Vault.Exists && !There("Keep/important.txt") && There("Keep"), "panic word with \"Keep too\" empties Keep");
    CareTests.Run(fake, Check, Make, There);
    ModesTests.Run(fake, Check, Make, There); // v0.10
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

/// <summary>v0.9 (163): finds deletes for good (File.Delete, recursive Directory.Delete, DirectoryInfo.Delete(true))
/// outside the approved methods. A line that deletes the pause file is allowed too. Comments are left out.</summary>
static class DeleteCatalog
{
    static readonly System.Text.RegularExpressions.Regex Member = new(@"^    (?=[A-Za-z])(?:(?:public|private|internal|protected|static|async|override|readonly|unsafe)\s+)*[\w<>\[\]?,.() ]+?\s+(\w+)\s*(?:<[^>]*>)?\(");
    static readonly System.Text.RegularExpressions.Regex Bad = new(@"\bFile\.Delete\s*\(|\bDirectory\.Delete\s*\([^;]*,\s*true\s*\)|\.Delete\s*\(\s*true\s*\)|FileSystem\.Delete(?:File|Directory)\s*\(");
    public static List<string> Find(string[] lines, string[] allowed)
    {
        var found = new List<string>();
        string member = "";
        for (int i = 0; i < lines.Length; i++)
        {
            var m = Member.Match(lines[i]);
            if (m.Success) member = m.Groups[1].Value;
            var code = lines[i];
            var c = code.IndexOf("//", StringComparison.Ordinal);
            if (c >= 0) code = code[..c];
            if (!Bad.IsMatch(code)) continue;
            if (allowed.Contains(member) || code.Contains("Conf.PauseFile")) continue;
            found.Add($"line {i + 1} in {member}");
        }
        return found;
    }
}
