// v0.9 Care tests. Run on their own fake user folder (a subfolder of the test folder) with a fake Recycle Bin, so the
// rest of the tests never see them. Nothing outside the test folder is touched.
using Amnesia.Core;

static class CareTests
{
    public static void Run(string fake, Action<bool, string> Check, Action<string> Make, Func<string, bool> There)
    {
        Console.WriteLine("v0.9 Care:");
        var before = Environment.GetEnvironmentVariable("AMNESIA_HOME");
        var home = Path.Combine(fake, "care-home");
        var binDir = Path.Combine(fake, "care-bin");
        Directory.CreateDirectory(home);
        Directory.CreateDirectory(binDir);
        Environment.SetEnvironmentVariable("AMNESIA_HOME", home);
        try { Tests(home, binDir, Check, rel => Make("care-home/" + rel), rel => There("care-home/" + rel)); }
        finally { Environment.SetEnvironmentVariable("AMNESIA_HOME", before); }
    }

    static bool RunGit(string dir, params string[] args)
    {
        try
        {
            Directory.CreateDirectory(dir);
            var psi = new System.Diagnostics.ProcessStartInfo("git") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            psi.ArgumentList.Add("-C"); psi.ArgumentList.Add(dir);
            foreach (var a in args) psi.ArgumentList.Add(a);
            using var p = System.Diagnostics.Process.Start(psi)!;
            p.StandardOutput.ReadToEnd(); p.StandardError.ReadToEnd();
            return p.WaitForExit(10_000) && p.ExitCode == 0;
        }
        catch { return false; } // no git on this computer: the real git check is skipped
    }

    static void Tests(string home, string binDir, Action<bool, string> Check, Action<string> Make, Func<string, bool> There)
    {
        string F(string rel) => Path.Combine(home, rel.Replace('/', Path.DirectorySeparatorChar));
        var old = DateTime.UtcNow.AddDays(-40);
        void Age(string rel, DateTime t)
        {
            var p = F(rel);
            if (Directory.Exists(p))
            {
                foreach (var f in Directory.EnumerateFileSystemEntries(p, "*", SearchOption.AllDirectories).OrderByDescending(x => x.Length))
                    if (File.Exists(f)) File.SetLastWriteTimeUtc(f, t); else Directory.SetLastWriteTimeUtc(f, t);
                Directory.SetLastWriteTimeUtc(p, t);
            }
            else File.SetLastWriteTimeUtc(p, t);
        }
        bool Link(string rel, string target)
        {
            try { Directory.CreateSymbolicLink(F(rel), F(target)); return true; } catch { return false; }
        }
        Directory.CreateDirectory(Path.Combine(home, ".amnesia"));
        File.WriteAllLines(Path.Combine(home, ".amnesia", "keep.conf"), new[] { "AppData/Roaming/KeptApp", "Projects/kept" });
        var binned = new List<string>();
        int bins = 0;
        var care = new Care
        {
            // the fake Recycle Bin: moves the item out of the fake user folder
            Recycle = p =>
            {
                var dest = Path.Combine(binDir, Guid.NewGuid().ToString("N"));
                if (Directory.Exists(p)) Directory.Move(p, dest); else File.Move(p, dest);
                binned.Add(p);
                return true;
            },
            EmptyBin = () => { bins++; return true; },
            BinSize = () => 5000,
            GitTracked = (repo, rel) => rel == "tracked-build" ? true : rel == "odd" ? null : false,
        };

        // ---------- the one check every delete passes ----------
        foreach (var f in new[] { "Keep/notes.txt", "Keep/Safe/secret.txt", ".amnesia/vault/x.amv", "AppData/Local/Microsoft/x/y", "OneDrive/doc.txt",
                     "Downloads/a.msi", ".amnesia-trash/20260101-000000/x/y.txt", "Real/inner/file.txt" })
            Make(f);
        Check(care.Refuse(home, "cache") == "outside", "Care never takes the user folder itself");
        Check(care.Refuse(Path.GetDirectoryName(home)!, "cache") == "outside", "...nor anything outside it");
        Check(care.Refuse(F(".amnesia/vault"), "cache") == "amnesia" && care.Refuse(F(".amnesia"), "cache") == "amnesia", ".amnesia and the vault are refused");
        Check(care.Refuse(F("Keep"), "build") == "keep-root" && care.Refuse(F("Keep/notes.txt"), "build") == null, "the Keep folder itself is refused, what is inside may go");
        Check(care.Refuse(F("Keep/Safe/secret.txt"), "build") == "keep-root", "the open Safe box is refused");
        Check(care.Refuse(F("AppData/Local"), "cache") == "system" && care.Refuse(F("Downloads"), "installer") == "system", "Windows' own folders themselves are refused");
        Check(care.Refuse(F("AppData/Local/Microsoft/x"), "cache") == "system", "AppData\\Local\\Microsoft is refused");
        Check(care.Refuse(F("OneDrive/doc.txt"), "installer") == "cloud", "cloud folders are refused");
        Check(care.Refuse(F(".amnesia-trash"), "atrash") == "amnesia" && care.Refuse(F(".amnesia-trash/20260101-000000"), "cache") == "amnesia"
              && care.Refuse(F(".amnesia-trash/20260101-000000"), "atrash") == null, "the Amnesia trash: one batch, only by its own feature");
        Check(care.Refuse(F("Downloads/missing.msi"), "installer") == "gone", "a missing item is refused");
        bool links = Link("Linked", "Real");
        if (links)
        {
            Check(care.Refuse(F("Linked/inner/file.txt"), "installer") == "link", "an item below a link is refused (links are never followed)");
            Check(care.Refuse(F("Linked"), "installer") == "link", "a link itself is refused");
        }
        Check(Care.OnKeepList("AppData/Roaming/KeptApp/Cache", new[] { "AppData/Roaming/KeptApp" }) && Care.OnKeepList("Projects", new[] { "Projects/kept" })
              && !Care.OnKeepList("Projects/other", new[] { "Projects/kept" }), "Keep List: on it, inside it, or holding it");

        // ---------- Clean now ----------
        Make("AppData/Local/Temp/old.tmp"); Age("AppData/Local/Temp/old.tmp", old);
        Make("AppData/Local/Temp/oldDir/a.tmp"); Age("AppData/Local/Temp/oldDir", old);
        Make("AppData/Local/Temp/new.tmp");
        Make("AppData/Local/Temp/mixed/old.tmp"); Age("AppData/Local/Temp/mixed", old); Make("AppData/Local/Temp/mixed/fresh.tmp");
        Make("AppData/Local/Temp/.net/Amnesia/x.dll"); Age("AppData/Local/Temp/.net", old);
        Make("AppData/Local/CrashDumps/app.dmp");
        Make("AppData/Local/SomeApp/User Data/Default/Cache/data_1");
        Make("AppData/Local/SomeApp/User Data/Default/Code Cache/js/x");
        Make("AppData/Local/SomeApp/User Data/Default/Preferences");
        Make("AppData/Roaming/KeptApp/GPUCache/data_0");
        Make("AppData/Local/Microsoft/Edge/User Data/Default/Cache/data_1");
        Make("AppData/Local/Deep/a/b/c/d/e/f/Cache/x");
        Make(".amnesia-trash/20260101-000000-apps/prog/x.exe");
        Age(".amnesia-trash/20260101-000000", old);
        Directory.SetCreationTimeUtc(F(".amnesia-trash/20260101-000000"), old);
        if (links) { Make("Elsewhere/Cache/x"); Link("AppData/Local/LinkedApp", "Elsewhere"); }
        var q = care.ScanQuick(new CareBudget());
        CareItem? Q(string rel) => q.FirstOrDefault(i => i.Rel == rel);
        Check(Q("AppData/Local/Temp/old.tmp") is { Selected: true, Cat: "temp" } && Q("AppData/Local/Temp/oldDir") is { Selected: true }, "Clean now: old Temp files and folders, ticked");
        Check(Q("AppData/Local/Temp/new.tmp") == null && Q("AppData/Local/Temp/mixed") == null, "...not what changed today (also deep inside a folder)");
        Check(!q.Any(i => i.Rel.StartsWith("AppData/Local/Temp/.net")), "...never Temp\\.net (running programs unpack there)");
        Check(Q("AppData/Local/CrashDumps/app.dmp") is { Selected: true, Cat: "crash" }, "crash dumps, ticked");
        Check(Q("AppData/Local/SomeApp/User Data/Default/Cache") is { Selected: true, Cat: "cache", Group: "SomeApp" } && Q("AppData/Local/SomeApp/User Data/Default/Code Cache") is { Selected: true },
            "app caches (Cache, Code Cache), ticked, grouped by app");
        Check(!q.Any(i => i.Rel.Contains("Preferences")), "...never the app's own settings");
        Check(Q("AppData/Roaming/KeptApp/GPUCache") is { Selected: false, Disabled: false, Reason: "keeplist" }, "a cache on the Keep List: listed, not ticked, can be ticked by hand");
        Check(!q.Any(i => i.Rel.StartsWith("AppData/Local/Microsoft")), "...never inside AppData\\Local\\Microsoft");
        Check(!q.Any(i => i.Rel.StartsWith("AppData/Local/Deep/")), "...no deeper than 5 levels");
        Check(Q(".amnesia-trash/20260101-000000") is { Selected: true, Cat: "atrash" }, "the Amnesia trash, ticked");
        Check(Q(".amnesia-trash/20260101-000000-apps") == null, "...program folders of Remove new apps wait their 3 days");
        if (links) Check(!q.Any(i => i.Rel.StartsWith("AppData/Local/LinkedApp")), "a cache behind a link is never listed");
        var bin = q.FirstOrDefault(i => i.Cat == "bin");
        Check(bin is { Selected: false, Bytes: 5000 }, "the Recycle Bin is listed but never ticked for you");

        // something changed after the scan: skipped and counted
        File.AppendAllText(F("AppData/Local/Temp/old.tmp"), "more");
        var picked = q.Where(i => i.Selected).ToList();
        var r = care.Act("quick", picked);
        Check(There("AppData/Local/Temp/old.tmp") && r.Changed == 1, "a file that changed since the scan is left alone and counted");
        Check(!There("AppData/Local/Temp/oldDir") && !There("AppData/Local/CrashDumps/app.dmp") && !There("AppData/Local/SomeApp/User Data/Default/Cache")
              && !There(".amnesia-trash/20260101-000000"), "Clean now deletes what was ticked");
        Check(There("AppData/Local/SomeApp/User Data/Default/Preferences") && There("AppData/Roaming/KeptApp/GPUCache/data_0") && There("AppData/Local/Temp/new.tmp")
              && There(".amnesia-trash/20260101-000000-apps/prog/x.exe") && There("AppData/Local/Temp/.net/Amnesia/x.dll"), "...and nothing else");
        Check(There("AppData/Local/Temp") && There("AppData/Local/CrashDumps") && There(".amnesia-trash"), "...the folders themselves stay");
        Check(bins == 0, "the Recycle Bin is not emptied unless ticked");
        Check(r.Cats.Any(c => c.Cat == "cache" && c.Done == 2) && r.Failed == 1 && r.Bytes > 0, "a result per category, with the space freed");
        var hist = File.ReadAllLines(Path.Combine(home, ".amnesia", "history.log")).Last().Split('\t');
        Check(hist.Length == 3 && hist[1] == "care" && System.Text.RegularExpressions.Regex.IsMatch(hist[2], @"^quick \d+ \d+ 1$"), "History: care quick <items> <KB> <failed>");
        var r2 = care.Act("quick", new[] { bin! });
        Check(bins == 1 && r2.Done == 1, "the Recycle Bin is emptied only when ticked");
        var trace = File.ReadAllText(Path.Combine(home, ".amnesia", "trace.log"));
        Check(!trace.Contains("old.tmp") && !trace.Contains("SomeApp") && trace.Contains("care"), "trace.log has steps and counts, no file names");

        // ---------- project build folders ----------
        void Proj(string dir, string marker, string target, bool isOld)
        {
            Make($"{dir}/{marker}");
            Make($"{dir}/{target}/pkg/index.js");
            if (isOld) Age($"{dir}/{target}", old);
        }
        Proj("Projects/web", "package.json", "node_modules", true);
        Make("Projects/web/node_modules/inner/node_modules/x/package.json"); Age("Projects/web/node_modules", old);
        Proj("Projects/fresh", "package.json", "node_modules", false);
        Proj("Projects/rs", "Cargo.toml", "target", true);
        Make("Projects/rs/target/debug/id_rsa");
        Age("Projects/rs/target", old);
        Proj("Projects/nested", "package.json", "dist", true);
        Make("Projects/nested/dist/.git/HEAD"); Age("Projects/nested/dist", old);
        Make("Projects/nomarker/dist/a.js"); Age("Projects/nomarker/dist", old);
        Proj("Projects/kept", "package.json", "node_modules", true);
        Proj("Documents/App", "App.csproj", "obj", true);
        Proj("Documents/App", "App.csproj", "bin", true);
        Proj("Projects/.hidden/web", "package.json", "node_modules", true);
        Proj("Projects/repo/tracked-build-parent", "package.json", "build", true);
        Make("Projects/repo/.git/HEAD");
        Proj("Projects/repo", "package.json", "tracked-build", true);  // not a build folder name: never listed
        Proj("Projects/repo2", "build.gradle", "build", true);
        Make("Projects/repo2/.git/HEAD");
        Proj("Projects/repo3/odd-parent", "package.json", "node_modules", true);
        Proj("Keep/code/tool", "Package.swift", ".build", true);
        Proj("AppData/Local/x", "package.json", "node_modules", true);
        Proj("Projects/a/b/c/d/e/f/g", "package.json", "node_modules", true);
        if (links) Link("Projects/linked", "Projects/web");
        var gitCalls = new List<string>();
        care.GitTracked = (repo, rel) =>
        {
            gitCalls.Add(rel);
            return rel == "tracked-build-parent/build" ? true : rel == "build" ? false : rel.EndsWith("odd-parent/node_modules") ? null : false;
        };
        Make("Projects/repo3/.git/HEAD");
        var p = care.ScanProjects(new CareBudget());
        CareItem? P(string rel) => p.FirstOrDefault(i => i.Rel == rel);
        Check(P("Projects/web/node_modules") is { Selected: true, Disabled: false, Where: "recycle", Group: "Projects/web" }, "build folders: old node_modules, ticked, to the Recycle Bin, grouped by project");
        Check(!p.Any(i => i.Rel.StartsWith("Projects/web/node_modules/")), "...never looked into once found");
        Check(P("Projects/fresh/node_modules") is { Selected: false, Disabled: false, Reason: "build-recent" }, "...used in the last 7 days: listed, not ticked");
        Check(P("Projects/rs/target") is { Disabled: true, Reason: "secret" }, "...one with a key file inside is protected");
        Check(P("Projects/nested/dist") is { Disabled: true, Reason: "nested-git" }, "...one with a git repo inside is protected");
        Check(P("Projects/nomarker/dist") == null, "...a dist folder without package.json is not a build folder");
        Check(P("Projects/kept/node_modules") is { Disabled: true, Reason: "keeplist" }, "...on the Keep List: shown, can't be ticked");
        Check(P("Documents/App/obj") is { Selected: true } && P("Documents/App/bin") is { Selected: true }, "...bin and obj next to a .csproj");
        Check(!p.Any(i => i.Rel.Contains(".hidden")), "...hidden folders are not looked into");
        Check(P("Projects/repo/tracked-build-parent/build") is { Disabled: true, Reason: "git" }, "...tracked by git: protected");
        Check(P("Projects/repo2/build") is { Selected: true }, "...in a git repo but not tracked: may go");
        Check(P("Projects/repo3/odd-parent/node_modules") is { Disabled: true, Reason: "unchecked" }, "...git could not tell: protected");
        Check(P("Keep/code/tool/.build") is { Selected: true }, "...also inside the Keep folder");
        Check(!p.Any(i => i.Rel.StartsWith("AppData")), "...never in AppData");
        Check(P("Projects/a/b/c/d/e/f/g/node_modules") == null, "...no deeper than 6 levels");
        if (links) Check(!p.Any(i => i.Rel.StartsWith("Projects/linked")), "...links are not followed");
        Check(Care.GitLsFiles(F("Projects/no-such-repo"), "x") == null, "git on a folder that is not there: could not tell (protected)");
        if (RunGit(F("Projects/realrepo"), "init", "-q"))
        {
            Make("Projects/realrepo/build/out.txt"); Make("Projects/realrepo/dist/x.js");
            if (RunGit(F("Projects/realrepo"), "add", "build/out.txt"))
                Check(Care.GitLsFiles(F("Projects/realrepo"), "build") == true && Care.GitLsFiles(F("Projects/realrepo"), "dist") == false, "real git: a tracked folder and an untracked one");
        }
        binned.Clear();
        var pr = care.Act("projects", p.Where(i => i.Selected).Concat(p.Where(i => i.Disabled)).ToList());
        Check(!There("Projects/web/node_modules") && There("Projects/web/package.json") && binned.Count == pr.Done && pr.Done == p.Count(i => i.Selected),
            "the ticked build folders went to the (fake) Recycle Bin");
        Check(There("Projects/rs/target") && There("Projects/kept/node_modules") && There("Projects/fresh/node_modules") && There("Projects/repo/tracked-build-parent/build"),
            "...protected and unticked ones stay, even when sent anyway");
        var noBin = new Care();
        Make("Projects/web2/package.json"); Make("Projects/web2/node_modules/x.js"); Age("Projects/web2/node_modules", old);
        var p2 = noBin.ScanProjects(new CareBudget()).Where(i => i.Rel == "Projects/web2/node_modules").ToList();
        var pr2 = noBin.Act("projects", p2);
        Check(There("Projects/web2/node_modules/x.js") && pr2.Failed == 1, "no Recycle Bin: nothing is deleted instead");

        // ---------- old installers ----------
        Make("Downloads/old.msi"); Age("Downloads/old.msi", old);
        Make("Downloads/new.msix");
        Make("Downloads/AppSetup.exe"); Age("Downloads/AppSetup.exe", old);
        Make("Downloads/tool.exe"); Age("Downloads/tool.exe", old);
        Make("Downloads/installer-files.zip"); Age("Downloads/installer-files.zip", old);
        Make("Downloads/photos.zip"); Age("Downloads/photos.zip", old);
        Make("Downloads/win.iso"); Age("Downloads/win.iso", old);
        Make("Downloads/disk.vhdx"); Make("Desktop/Brankas.sparsebundle/x");
        Make("Downloads/MyVM/MyVM.vmx"); Make("Downloads/MyVM/tools.msi"); Age("Downloads/MyVM/tools.msi", old);
        Make("Downloads/a/b/deep.msi"); Age("Downloads/a/b/deep.msi", old);
        Make("Downloads/a/one.msi"); Age("Downloads/a/one.msi", old);
        Make("Keep/setups/kept.msi"); Age("Keep/setups/kept.msi", old);
        var ins = care.ScanInstallers(new CareBudget());
        CareItem? I(string rel) => ins.FirstOrDefault(i => i.Rel == rel);
        Check(I("Downloads/old.msi") is { Selected: true, Where: "recycle" } && I("Downloads/a/one.msi") is { Selected: true } && I("Keep/setups/kept.msi") is { Selected: true },
            "installers: an .msi older than 14 days is ticked (Downloads, a folder in it, Keep)");
        Check(I("Downloads/new.msix") is { Selected: false }, "...a new one is listed, not ticked");
        Check(I("Downloads/AppSetup.exe") is { Selected: false } && I("Downloads/tool.exe") == null, "...a setup .exe is listed, never ticked; other programs are not listed");
        Check(I("Downloads/installer-files.zip") is { Selected: false } && I("Downloads/photos.zip") == null, "...a .zip only when it is called setup or install, never ticked");
        Check(I("Downloads/win.iso") is { Selected: false }, "...a disc image is never ticked");
        Check(I("Downloads/disk.vhdx") == null && !ins.Any(i => i.Rel.Contains("Brankas")) && I("Downloads/MyVM/tools.msi") == null, "...virtual machines and disk images are never listed");
        Check(I("Downloads/a/b/deep.msi") == null, "...only 2 levels deep");
        var ir = care.Act("installers", ins.Where(i => i.Selected));
        Check(!There("Downloads/old.msi") && There("Downloads/new.msix") && There("Downloads/AppSetup.exe") && ir.Done == 3, "the ticked installers went to the Recycle Bin");

        // ---------- app leftovers ----------
        Make("AppData/Roaming/Foo App/settings.json");
        Make("AppData/Roaming/Foo App/Cache/c1");
        Make("AppData/Roaming/Foo App/sub/GPUCache/g1");
        Make("AppData/Local/FooSoft/FooApp/data.db");
        Make("AppData/Local/Foo App Helper/x");
        Make("AppData/LocalLow/Other/x");
        var lf = care.ScanLeftovers("Foo App 2.1 (x64)", "FooSoft Inc.", new CareBudget());
        CareItem? Lf(string rel) => lf.FirstOrDefault(i => i.Rel == rel);
        Check(Lf("AppData/Roaming/Foo App") is { Selected: false, Reason: "leftover-data", Where: "recycle" } && Lf("AppData/Local/FooSoft/FooApp") is { Selected: false },
            "leftovers: the app's own folders by exact name (also Publisher\\App), not ticked (your data)");
        Check(Lf("AppData/Roaming/Foo App/Cache") is { Selected: true } && Lf("AppData/Roaming/Foo App/sub/GPUCache") is { Selected: true }, "...its cache folders are ticked");
        Check(Lf("AppData/Local/Foo App Helper") == null && !lf.Any(i => i.Rel.Contains("Other")), "...only the exact name, nothing that only looks alike");
        Check(care.ScanLeftovers("Go", null, new CareBudget()).Count == 0, "...a name that is too short finds nothing");
        var lr = care.Act("apps", lf.Where(i => i.Selected), baseItems: 1, baseKb: 2048);
        Check(!There("AppData/Roaming/Foo App/Cache") && There("AppData/Roaming/Foo App/settings.json") && lr.Done == 2, "the ticked leftovers went to the Recycle Bin, the data stays");
        var lr2 = care.Act("apps", lf.Where(i => i.Rel == "AppData/Roaming/Foo App"));
        Check(lr2.Done == 0 && lr2.Changed == 1 && There("AppData/Roaming/Foo App/settings.json"), "a folder that changed since the scan (its cache went) is left alone");
        hist = File.ReadAllLines(Path.Combine(home, ".amnesia", "history.log")).Reverse().Skip(1).First().Split('\t');
        Check(hist[2].StartsWith("apps 3 "), "History counts the uninstall too");

        // ---------- v0.9 audit: a Keep List that can't be trusted stops Care too ----------
        var kc = Path.Combine(home, ".amnesia", "keep.conf");
        var keepLines = File.ReadAllLines(kc);
        Make("Downloads/stop-test.msi"); Age("Downloads/stop-test.msi", old);
        var stopList = care.ScanInstallers(new CareBudget()).Where(i => i.Rel == "Downloads/stop-test.msi").ToList();
        File.WriteAllLines(kc + ".last", keepLines);
        File.Delete(kc);
        string? Stops(Action a) { try { a(); return null; } catch (InvalidOperationException e) { return e.Message; } }
        Check(Stops(() => care.ScanQuick(new CareBudget())) == "keeplist-missing" && Stops(() => care.ScanProjects(new CareBudget())) == "keeplist-missing"
            && Stops(() => care.ScanInstallers(new CareBudget())) == "keeplist-missing", "Care stops when the Keep List has gone missing");
        Check(Stops(() => care.Act("installers", stopList)) == "keeplist-missing" && There("Downloads/stop-test.msi"), "...and deletes nothing it found before");
        File.WriteAllText(kc, "AppData/Roaming/KeptApp\0\0");
        Check(Stops(() => care.ScanInstallers(new CareBudget())) == "keeplist-unreadable", "...or when it can't be read");
        File.WriteAllLines(kc, keepLines);
        File.Delete(kc + ".last");
        // a ticked cache inside a ticked folder: its bytes are counted once
        Make("AppData/Roaming/Bar App/data.bin");
        Make("AppData/Roaming/Bar App/Cache/c1");
        File.WriteAllBytes(F("AppData/Roaming/Bar App/data.bin"), new byte[3000]);
        File.WriteAllBytes(F("AppData/Roaming/Bar App/Cache/c1"), new byte[5000]);
        var bl = care.ScanLeftovers("Bar App", null, new CareBudget());
        var br = care.Act("apps", bl.Where(i => i.Rel.StartsWith("AppData/Roaming/Bar App")));
        Check(br.Done == 2 && !There("AppData/Roaming/Bar App") && br.Bytes == bl.First(i => i.Rel == "AppData/Roaming/Bar App").Bytes, "a cache inside a folder that also went is counted once");

        // ---------- limits and the overview ----------
        var small = new CareBudget(maxEntries: 3);
        care.ScanProjects(small);
        Check(small.Cut, "a scan stops after its limit of entries");
        var cts = new CancellationTokenSource();
        cts.Cancel();
        try { care.ScanQuick(new CareBudget(cts.Token)); Check(false, "Cancel stops a scan"); }
        catch (OperationCanceledException) { Check(true, "Cancel stops a scan"); }
        var timed = new CareBudget(maxTime: TimeSpan.Zero);
        Thread.Sleep(5);
        care.ScanInstallers(timed);
        Check(timed.Cut, "a scan stops after its time limit");
        using (var big = File.Create(F("Downloads/big.mkv"))) big.SetLength(210L << 20); // sparse: takes no real space
        Make("Downloads/old-file.pdf"); Age("Downloads/old-file.pdf", old);
        Make("Keep/doc.txt");
        var o = care.Overview(new CareBudget());
        Check(o.DiskTotal > 0 && o.DiskFree >= 0, "overview: disk size and free space");
        Check(o.Sizes["keep"].Bytes > 0 && o.Sizes["downloads"].Bytes >= 210L << 20 && o.Sizes["bin"].Bytes == 5000, "...sizes of Keep, Downloads, the Recycle Bin");
        Check(o.Files.Any(f => f.Rel == "Downloads/big.mkv") && o.Files.All(f => f.Bytes >= 200L << 20), "...files of 200 MB and more");
        Check(o.OldDownloads >= 2 && o.Folders.Count > 0 && o.Folders.Count <= 10, "...old downloads and the biggest folders");
    }
}
