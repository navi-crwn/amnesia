// Profile Vault (v0.4, same idea as the Mac): locked snapshots of the apps you choose, so their logins come back after a
// sign out. A snapshot needs no password (it is locked with the vault's public key); opening one needs your password.
// 3 wrong passwords in a row, or the panic word, delete the vault for good (Doomsday).
//
// Honest limit: Chrome, Edge and other Windows apps lock their saved logins to your Windows user (DPAPI). A snapshot
// comes back on the same PC and the same Windows user, not on another PC.
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Amnesia.Core;

public sealed class VaultError(string code, int left = 0) : Exception(code)
{
    public string Code { get; } = code;
    public int Left { get; } = left;
}

public sealed record VaultApp(string Name, string[] Paths, string? Process, bool Chromium = false);

public static class Vault
{
    public const int MinPassword = 12, MaxAttempts = 3;

    // Paths from the user folder. Only apps whose data exists on this PC show up.
    public static readonly VaultApp[] Apps =
    {
        new("Chrome", new[] { "AppData/Local/Google/Chrome/User Data" }, "chrome", true),
        new("Microsoft Edge", new[] { "AppData/Local/Microsoft/Edge/User Data" }, "msedge", true),
        new("Brave", new[] { "AppData/Local/BraveSoftware/Brave-Browser/User Data" }, "brave", true),
        new("Vivaldi", new[] { "AppData/Local/Vivaldi/User Data" }, "vivaldi", true),
        new("Opera", new[] { "AppData/Roaming/Opera Software/Opera Stable" }, "opera", true),
        new("Firefox", new[] { "AppData/Roaming/Mozilla/Firefox" }, "firefox"),
        new("Discord", new[] { "AppData/Roaming/discord" }, "Discord"),
        new("Telegram", new[] { "AppData/Roaming/Telegram Desktop" }, "Telegram"),
        new("Signal", new[] { "AppData/Roaming/Signal" }, "Signal"),
        new("Slack", new[] { "AppData/Roaming/Slack" }, "slack"),
        new("Spotify", new[] { "AppData/Roaming/Spotify" }, "Spotify"),
        new("VS Code", new[] { "AppData/Roaming/Code", ".vscode" }, "Code"),
        new("Cursor", new[] { "AppData/Roaming/Cursor", ".cursor" }, "Cursor"),
        new("Claude", new[] { "AppData/Roaming/Claude", "AppData/Local/Packages/Claude_*/LocalCache/Roaming/Claude" }, "claude"), // v0.6: also the Microsoft Store version
        new("Claude Code", new[] { ".claude", ".claude.json" }, null),
        new("GitHub CLI", new[] { "AppData/Roaming/GitHub CLI" }, null),
        new("Git", new[] { ".gitconfig", ".git-credentials" }, null),
    };

    // Not worth saving: big, and the app makes them again by itself.
    static readonly string[] Exclude =
    {
        "Cache", "Code Cache", "GPUCache", "CacheStorage", "ShaderCache", "GrShaderCache", "DawnCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "component_crx_cache", "Crashpad", "CachedData", "CachedExtensionVSIXs", "cache2", "startupCache",
        "Service Worker/ScriptCache",
    };
    // Chromium browsers: models and helper downloads the browser fetches again by itself. Logins always stay in.
    static readonly string[] ChromiumLight =
    {
        "optimization_guide_model_store", "OptGuideOnDeviceModel", "OnDeviceHeadSuggestModel", "WasmTtsEngine",
        "Safe Browsing", "screen_ai", "GraphiteDawnCache", "BrowserMetrics", "BrowserMetrics-spare.pma", "SODA", "SODALanguagePacks",
    };

    static string V => Path.Combine(Home.Dir, "vault");
    static string FPub => Path.Combine(V, "public.key");
    static string FPriv => Path.Combine(V, "private.key");
    static string FAttempts => Path.Combine(V, "attempts");
    static string FPanic => Path.Combine(V, "panic.json");
    static string FManifest => Path.Combine(V, "manifest.json");
    static string AppDir => Path.Combine(V, "apps");
    static string Tmp => Path.Combine(V, ".tmp");
    /// <summary>Restore moves the app data you had to here first. It is inside Temp, so the next sign out wipes it.</summary>
    public static string BeforeRestore => Home.Full("AppData/Local/Temp/Amnesia-before-restore");

    public static bool Exists => File.Exists(FPub) && File.Exists(FPriv);
    public static string FolderPrefix => "Folder: ";

    /// <summary>Quits an app before its files are saved or replaced (given by Amnesia.exe; nothing in tests).</summary>
    public static Action<IEnumerable<string>>? QuitApps { get; set; }

    // ---------- what is in the vault ----------
    public static IEnumerable<VaultApp> All()
    {
        foreach (var a in Apps) yield return a;
        foreach (var f in (Conf.Get("VAULT_FOLDERS") ?? "").Split('|', StringSplitOptions.RemoveEmptyEntries))
            yield return new VaultApp(FolderPrefix + f, new[] { f }, null);
    }

    public static string[] Present(VaultApp a) => a.Paths.SelectMany(p => Expand(Home.User, p)).ToArray();

    /// <summary>v0.6: a path may have * in a folder name (Store apps: Packages/Claude_*). Gives the paths (from base,
    /// written with /) that exist.</summary>
    static IEnumerable<string> Expand(string root, string pattern)
    {
        var parts = pattern.Split('/');
        IEnumerable<string> found = new[] { "" };
        foreach (var part in parts)
        {
            var next = new List<string>();
            foreach (var f in found)
            {
                var dir = f.Length == 0 ? root : Path.Combine(root, f.Replace('/', Path.DirectorySeparatorChar));
                if (!part.Contains('*')) { next.Add(f.Length == 0 ? part : f + "/" + part); continue; }
                if (!Directory.Exists(dir)) continue;
                try { next.AddRange(Directory.EnumerateDirectories(dir, part).Select(d => (f.Length == 0 ? "" : f + "/") + Path.GetFileName(d))); } catch { }
            }
            found = next;
        }
        return found.Where(r => File.Exists(Path.Combine(root, r.Replace('/', Path.DirectorySeparatorChar))) || Directory.Exists(Path.Combine(root, r.Replace('/', Path.DirectorySeparatorChar))));
    }

    public static HashSet<string> Chosen()
    {
        var v = Conf.Get("VAULT_APPS");
        var set = new HashSet<string>((v ?? "").Split('|', StringSplitOptions.RemoveEmptyEntries), StringComparer.OrdinalIgnoreCase);
        foreach (var f in All().Where(a => a.Name.StartsWith(FolderPrefix))) set.Add(f.Name); // a folder you added is always in
        return set;
    }

    public static void Choose(string name, bool on)
    {
        var set = Chosen();
        set.RemoveWhere(n => n.StartsWith(FolderPrefix));
        if (on) set.Add(name); else set.Remove(name);
        Conf.Set("VAULT_APPS", string.Join('|', set));
    }

    public static string? AddFolder(string path)
    {
        var rel = KeepList.Norm(path);
        var home = Home.User.Replace('\\', '/');
        var p = path.Replace('\\', '/');
        if (p.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase)) rel = KeepList.Norm(p[(home.Length + 1)..]);
        else if (p.Length > 1 && p[1] == ':') return null; // only folders inside your user folder
        if (rel.Length == 0 || rel.StartsWith(".amnesia", StringComparison.OrdinalIgnoreCase)) return null;
        var list = (Conf.Get("VAULT_FOLDERS") ?? "").Split('|', StringSplitOptions.RemoveEmptyEntries).ToList();
        if (!list.Contains(rel, StringComparer.OrdinalIgnoreCase)) list.Add(rel);
        Conf.Set("VAULT_FOLDERS", string.Join('|', list));
        return rel;
    }

    public static void RemoveFolder(string name)
    {
        var rel = name.StartsWith(FolderPrefix) ? name[FolderPrefix.Length..] : name;
        var list = (Conf.Get("VAULT_FOLDERS") ?? "").Split('|', StringSplitOptions.RemoveEmptyEntries).Where(x => !x.Equals(rel, StringComparison.OrdinalIgnoreCase));
        Conf.Set("VAULT_FOLDERS", string.Join('|', list));
        DeleteSnapshots(new[] { name });
    }

    static string Slug(string name) => new string(name.Select(c => char.IsLetterOrDigit(c) ? char.ToLowerInvariant(c) : '-').ToArray());
    static string Archive(string name) => Path.Combine(AppDir, Slug(name) + ".amv");
    // v0.7: the snapshot before the newest one. A new snapshot never throws the old one away, so an automatic snapshot of a
    // half set up or freshly wiped app can't destroy the good one ("Restore the one before" on the Vault page).
    static string Previous(string name) => Path.Combine(AppDir, Slug(name) + ".prev.amv");

    public static JsonObject Manifest()
    {
        try { return JsonNode.Parse(File.ReadAllText(FManifest)) as JsonObject ?? new JsonObject(); } catch { return new JsonObject(); }
    }
    static void Save(JsonObject m) { Directory.CreateDirectory(V); File.WriteAllText(FManifest, m.ToJsonString()); }

    public static int Attempts => int.TryParse(Read(FAttempts), out var i) ? i : 0;
    static string? Read(string f) { try { return File.ReadAllText(f).Trim(); } catch { return null; } }

    // ---------- create ----------
    public static void Create(string password, string panicWord = "", bool panicFull = false)
    {
        if (password.Length < MinPassword) throw new VaultError("short-password");
        if (panicWord.Length > 0 && panicWord == password) throw new VaultError("panic-same");
        Directory.CreateDirectory(V);
        var (pub, priv) = Crypto.NewKeys(password);
        File.WriteAllBytes(FPub, pub);
        File.WriteAllBytes(FPriv, priv);
        File.WriteAllText(FAttempts, "0");
        SetPanicWord(panicWord, panicFull);
        Home.History("vault", "created");
    }

    static void SetPanicWord(string word, bool full)
    {
        if (word.Length == 0) { try { File.Delete(FPanic); } catch { } return; }
        var salt = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
        File.WriteAllText(FPanic, new JsonObject { ["salt"] = salt, ["hash"] = Crypto.Hash(word, salt), ["full"] = full }.ToJsonString());
    }

    public static bool HasPanicWord => File.Exists(FPanic);

    // ---------- snapshot (no password) ----------
    static DateTime Newest(VaultApp a)
    {
        var t = DateTime.MinValue;
        var opt = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        foreach (var p in Present(a))
        {
            var full = Home.Full(p);
            try
            {
                if (File.Exists(full)) { t = Max(t, File.GetLastWriteTimeUtc(full)); continue; }
                foreach (var f in new DirectoryInfo(full).EnumerateFileSystemInfos("*", opt)) t = Max(t, f.LastWriteTimeUtc);
            }
            catch { }
        }
        return t;
        static DateTime Max(DateTime a, DateTime b) => a > b ? a : b;
    }

    static bool Skip(string rel, bool chromium)
    {
        foreach (var part in rel.Split('/'))
        {
            if (Exclude.Contains(part, StringComparer.OrdinalIgnoreCase)) return true;
            if (chromium && ChromiumLight.Contains(part, StringComparer.OrdinalIgnoreCase)) return true;
        }
        return Exclude.Any(e => e.Contains('/') && rel.Contains(e, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Saves the chosen apps, one locked file per app (replaced only after the new one is complete).
    /// changedOnly (automatic snapshot): apps that did not change since their last snapshot are skipped.
    /// budget: no new app is started after this much time.
    /// running (v0.7.1, the automatic snapshot while you are signed in): no app is closed; an app whose program runs
    /// (again) is skipped, it is saved the next time you close it.</summary>
    public static List<string> Snapshot(IEnumerable<string>? names = null, bool changedOnly = false, TimeSpan? budget = null,
        Action<double, string>? progress = null, CancellationToken cancel = default, Func<string, bool>? running = null)
    {
        if (!Exists) throw new VaultError("no-vault");
        var chosen = names?.ToHashSet(StringComparer.OrdinalIgnoreCase) ?? Chosen();
        var apps = All().Where(a => chosen.Contains(a.Name) && Present(a).Length > 0).ToList();
        var m = Manifest();
        if (changedOnly)
            apps = apps.Where(a => m[a.Name]?["ts"] is not JsonNode ts || !File.Exists(Archive(a.Name)) || Newest(a).Ticks > ts.GetValue<long>()).ToList();
        if (apps.Count == 0)
        {
            if (changedOnly) return new List<string>();
            throw new VaultError("nothing");
        }
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var pub = File.ReadAllBytes(FPub);
        if (!Home.Test && running == null) QuitApps?.Invoke(apps.Where(a => a.Process != null).Select(a => a.Process!));
        Directory.CreateDirectory(AppDir);
        var saved = new List<string>();
        for (int i = 0; i < apps.Count; i++)
        {
            cancel.ThrowIfCancellationRequested();
            if (budget is { } b && watch.Elapsed > b) { Home.Trace("vault", $"time is up, {apps.Count - i} app(s) left for next time"); break; }
            var a = apps[i];
            if (running != null && a.Process != null && running(a.Process)) { Home.Trace("vault", $"{a.Name} runs again, saved next time"); continue; }
            progress?.Invoke((double)i / apps.Count, a.Name);
            var arc = Archive(a.Name);
            var tmp = arc + ".new";
            var started = DateTime.UtcNow;
            int skipped = 0;
            try
            {
                using (var file = File.Create(tmp))
                using (var locked = Crypto.Writer(file, Crypto.KindSnapshot, pub))
                using (var zip = new ZipArchive(locked, ZipArchiveMode.Create))
                {
                    foreach (var p in Present(a)) skipped += AddToZip(zip, p, a.Chromium, cancel);
                }
                if (File.Exists(arc)) File.Move(arc, Previous(a.Name), overwrite: true);
                File.Move(tmp, arc, overwrite: true);
            }
            finally { try { File.Delete(tmp); } catch { } }
            var before = m[a.Name] as JsonObject;
            long size = new FileInfo(arc).Length;
            var entry = new JsonObject
            {
                ["time"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm"),
                ["ts"] = started.Ticks,
                ["size"] = size,
                ["skipped"] = skipped,
            };
            if (before != null && File.Exists(Previous(a.Name)))
            {
                entry["prevTime"] = before["time"]?.GetValue<string>();
                entry["prevSize"] = before["size"]?.GetValue<long>();
                // much smaller than last time: maybe the app was just set up again or wiped; say so (the old one is kept)
                if (before["size"]?.GetValue<long>() is long old && old > 5_000_000 && size < old / 4)
                {
                    entry["shrunk"] = true;
                    Home.Trace("vault", $"{a.Name}: new snapshot is much smaller than the last one, the last one is kept as 'previous'");
                }
            }
            if (a.Chromium && SetupUnfinished(a)) { entry["setup"] = "unfinished"; Home.Trace("vault", $"{a.Name}: first-run setup not finished in this snapshot"); }
            m[a.Name] = entry;
            Save(m);
            saved.Add(a.Name);
        }
        progress?.Invoke(1, "");
        if (saved.Count > 0) Home.History("snapshot", (changedOnly ? "auto:" : "") + string.Join(", ", saved));
        return saved;
    }

    /// <summary>Chromium browsers (Edge, Chrome...): the first-run setup was never finished, so after a restore the
    /// browser shows its welcome pages again. Read from "Local State" (has_user_completed_fre / fre.completed).
    /// v0.7.1: Edge leaves has_user_completed_fre at false when you skip its welcome pages, so the setup also counts as
    /// done when the browser was really used: has_first_visible_browser_session_completed is true, or the Default
    /// profile already has Cookies or History.</summary>
    public static bool SetupUnfinished(VaultApp a)
    {
        try
        {
            foreach (var root in Present(a))
            {
                var dir = Home.Full(root);
                var ls = Path.Combine(dir, "Local State");
                if (!File.Exists(ls)) continue;
                using var fs = new FileStream(ls, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var text = new StreamReader(fs).ReadToEnd();
                if (!System.Text.RegularExpressions.Regex.IsMatch(text, "\"has_user_completed_fre\"\\s*:\\s*false")) continue;
                if (System.Text.RegularExpressions.Regex.IsMatch(text, "\"has_first_visible_browser_session_completed\"\\s*:\\s*true")) continue;
                if (new[] { "Default/Cookies", "Default/Network/Cookies", "Default/History" }.Any(f => File.Exists(Path.Combine(dir, f.Replace('/', Path.DirectorySeparatorChar))))) continue;
                return true;
            }
        }
        catch { }
        return false;
    }

    /// <summary>v0.7.1: a snapshot cut off half way (sign out, power cut) leaves a half written "*.amv.new". The finished
    /// snapshots are never touched by that; the leftover is deleted at start. Returns how many.</summary>
    public static int RemoveUnfinished()
    {
        int n = 0;
        if (!Directory.Exists(AppDir)) return 0;
        foreach (var f in Directory.EnumerateFiles(AppDir, "*.amv.new"))
            try { File.Delete(f); n++; } catch { }
        return n;
    }

    /// <summary>v0.7.1: has the app's data changed since its last snapshot, and stayed untouched for at least quiet?
    /// (For apps without a program of their own, like Claude Code or a folder.)</summary>
    public static bool ChangedAndQuiet(VaultApp a, TimeSpan quiet, DateTime nowUtc)
    {
        var newest = Newest(a);
        if (newest == DateTime.MinValue || nowUtc - newest < quiet) return false;
        return Manifest()[a.Name]?["ts"] is not JsonNode ts || !File.Exists(Archive(a.Name)) || newest.Ticks > ts.GetValue<long>();
    }

    /// <summary>Adds a file or folder (path from the user folder) to the zip. Returns how many files were in use and skipped.</summary>
    static int AddToZip(ZipArchive zip, string rel, bool chromium, CancellationToken cancel)
    {
        int skipped = 0;
        var full = Home.Full(rel);
        IEnumerable<string> files = File.Exists(full) ? new[] { full }
            : Directory.EnumerateFiles(full, "*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint });
        foreach (var f in files)
        {
            cancel.ThrowIfCancellationRequested();
            var name = Path.GetRelativePath(Home.User, f).Replace('\\', '/');
            if (Skip(name, chromium)) continue;
            try
            {
                using var src = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                var e = zip.CreateEntry(name, CompressionLevel.Fastest);
                e.LastWriteTime = File.GetLastWriteTime(f);
                using var dst = e.Open();
                src.CopyTo(dst);
            }
            catch (IOException) { skipped++; }
            catch (UnauthorizedAccessException) { skipped++; }
        }
        return skipped;
    }

    public static void DeleteSnapshots(IEnumerable<string>? names = null)
    {
        var m = Manifest();
        if (names == null)
        {
            try { Directory.Delete(AppDir, true); } catch { }
            m.Clear();
        }
        else foreach (var n in names) { try { File.Delete(Archive(n)); } catch { } try { File.Delete(Previous(n)); } catch { } m.Remove(n); }
        Save(m);
    }

    // ---------- open & restore (password) ----------
    /// <summary>Doomsday: deletes the whole vault. full = the Keep folder is emptied too.</summary>
    public static void Doomsday(bool full, string reason)
    {
        try { Directory.Delete(V, true); } catch { CleanEngine.Delete(V); }
        // v0.6: a new vault starts clean: no apps or folders ticked from the old one
        Conf.Set("VAULT_APPS", null); Conf.Set("VAULT_FOLDERS", null);
        if (full)
        {
            var keep = Conf.KeepDir;
            Home.UseKeep(() => { if (Directory.Exists(keep)) foreach (var c in Directory.EnumerateFileSystemEntries(keep)) CleanEngine.Delete(c); });
        }
        try { File.AppendAllText(Path.Combine(Home.Dir, "doomsday.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} doomsday ({reason}){(full ? " + Keep" : "")}{Environment.NewLine}"); } catch { }
        Home.History("doomsday", full ? "keep" : "");
    }

    /// <summary>Opens the private key with the password. Handles the panic word and the count of wrong tries.</summary>
    public static RSA Unlock(string password)
    {
        if (!Exists) throw new VaultError("no-vault");
        if (File.Exists(FPanic))
        {
            var p = JsonNode.Parse(File.ReadAllText(FPanic))!;
            var salt = p["salt"]!.GetValue<string>();
            if (CryptographicOperations.FixedTimeEquals(Convert.FromHexString(Crypto.Hash(password, salt)), Convert.FromHexString(p["hash"]!.GetValue<string>())))
            {
                Doomsday(p["full"]?.GetValue<bool>() == true, "panic word");
                throw new VaultError("doomsday");
            }
        }
        try
        {
            var rsa = Crypto.Unlock(File.ReadAllBytes(FPriv), password);
            File.WriteAllText(FAttempts, "0");
            return rsa;
        }
        catch (CryptographicException)
        {
            int failed = Attempts + 1;
            bool doom = Conf.Get("DOOMSDAY") != "0";
            if (doom && failed >= MaxAttempts)
            {
                Doomsday(false, $"{failed} wrong passwords");
                throw new VaultError("doomsday");
            }
            File.WriteAllText(FAttempts, failed.ToString());
            throw new VaultError("wrong", doom ? MaxAttempts - failed : -1);
        }
    }

    public static void CheckPassword(string password) { using var _ = Unlock(password); }

    public static void ChangePassword(string old, string @new)
    {
        if (@new.Length < MinPassword) throw new VaultError("short-password");
        using var _ = Unlock(old);
        File.WriteAllBytes(FPriv, Crypto.Relock(File.ReadAllBytes(FPriv), old, @new));
    }

    public static void ChangePanicWord(string password, string word, bool full)
    {
        if (word.Length > 0 && word == password) throw new VaultError("panic-same");
        using var _ = Unlock(password);
        SetPanicWord(word, full);
    }

    /// <summary>Puts every app with a snapshot back. Everything is unpacked first; then each app is swapped in on its own
    /// (your current app data goes to Temp\Amnesia-before-restore, wiped at the next sign out).
    /// v0.5.1: a folder Windows will not let go of (Edge kept "Access denied") is no longer the end: Amnesia asks Windows
    /// which program holds it, closes that app's own helpers, tries again, and in the end swaps it file by file. Files still
    /// in use stay as they were and are counted in LastProblems. One app that fails never stops the others, and the
    /// snapshots in the vault are never touched by a restore.</summary>
    public static List<string> Restore(string password, IEnumerable<string>? only = null, Action<double, string>? progress = null, CancellationToken cancel = default, bool previous = false)
    {
        var m = Manifest();
        string Src(string name) => previous && File.Exists(Previous(name)) ? Previous(name) : Archive(name);
        var apps = All().Where(a => m.ContainsKey(a.Name) && File.Exists(previous ? Previous(a.Name) : Archive(a.Name)) && (only == null || only.Contains(a.Name, StringComparer.OrdinalIgnoreCase))).ToList();
        if (apps.Count == 0) throw new VaultError("no-snapshot");
        using var rsa = Unlock(password);
        var stage = Path.Combine(V, ".stage");
        CleanEngine.Delete(stage); CleanEngine.Delete(Tmp);
        Directory.CreateDirectory(stage); Directory.CreateDirectory(Tmp);
        var done = new List<string>();
        LastProblems = new Dictionary<string, string>();
        try
        {
            for (int i = 0; i < apps.Count; i++)
            {
                var a = apps[i];
                progress?.Invoke(0.9 * i / apps.Count, a.Name);
                var zipFile = Path.Combine(Tmp, Slug(a.Name) + ".zip");
                using (var o = File.Create(zipFile)) Crypto.Open(Src(a.Name), rsa, o, null, cancel);
                ZipFile.ExtractToDirectory(zipFile, Path.Combine(stage, Slug(a.Name)), overwriteFiles: true);
                File.Delete(zipFile);
            }
            progress?.Invoke(0.92, "");
            if (!Home.Test) QuitApps?.Invoke(apps.Where(a => a.Process != null).Select(a => a.Process!));
            CleanEngine.Delete(BeforeRestore);
            foreach (var a in apps)
            {
                try
                {
                    int busy = PutBack(a, Path.Combine(stage, Slug(a.Name)));
                    done.Add(a.Name);
                    if (busy > 0) LastProblems[a.Name] = "in-use:" + busy;
                    Home.Trace("vault", $"restore {a.Name}: ok" + (busy > 0 ? $", {busy} file(s) in use left as they were" : ""));
                }
                catch (Exception e)
                {
                    LastProblems[a.Name] = "failed";
                    Home.Trace("vault", $"restore {a.Name} failed: {e.GetType().Name} 0x{e.HResult:X8}");
                }
            }
        }
        finally { CleanEngine.Delete(stage); CleanEngine.Delete(Tmp); }
        progress?.Invoke(1, "");
        if (done.Count == 0) throw new VaultError("restore-failed");
        Home.History("restore", (previous ? "previous:" : "") + string.Join(", ", done));
        return done;
    }

    /// <summary>What did not go fully right in the last restore: app name -> "in-use:N" or "failed".</summary>
    public static Dictionary<string, string> LastProblems { get; private set; } = new();

    /// <summary>Tests only: paths that act as if a program held them open.</summary>
    public static Func<string, bool>? TestBusy { get; set; }

    static int PutBack(VaultApp a, string src)
    {
        int busy = 0;
        foreach (var p in a.Paths.SelectMany(x => Expand(src, x)))
        {
            var target = Home.Full(p);
            var from = Path.Combine(src, p.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(from) && !Directory.Exists(from)) continue;
            if (File.Exists(target) || Directory.Exists(target))
                MoveAside(a, target, Path.Combine(BeforeRestore, p.Replace('/', Path.DirectorySeparatorChar)));
            busy += Put(from, target);
        }
        return busy;
    }

    static void Move(string from, string to)
    {
        if (TestBusy?.Invoke(from) == true || TestBusy?.Invoke(to) == true) throw new IOException("in use");
        if (Directory.Exists(from)) Directory.Move(from, to); else File.Move(from, to);
    }

    static void Copy(string from, string to)
    {
        if (TestBusy?.Invoke(to) == true) throw new IOException("in use");
        File.Copy(from, to, overwrite: true);
    }

    /// <summary>Moves your current app data out of the way. Whole folder first (a few tries, closing what holds it);
    /// if Windows still says no, piece by piece. Pieces still in use are copied to Temp and stay where they are.</summary>
    static void MoveAside(VaultApp a, string target, string old)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(old)!);
        for (int t = 0; ; t++)
        {
            try { Move(target, old); return; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                if (t == 3) break;
                if (!Home.Test) { CloseHolders(a, target); QuitApps?.Invoke(a.Process != null ? new[] { a.Process } : Array.Empty<string>()); }
                Thread.Sleep(Home.Test ? 10 : 800 * (t + 1));
            }
        }
        Home.Trace("vault", $"restore {a.Name}: folder busy, moving it piece by piece");
        if (File.Exists(target)) { try { File.Copy(target, old, true); } catch { } return; }
        Pieces(target, old);
    }

    static void Pieces(string dir, string old)
    {
        Directory.CreateDirectory(old);
        foreach (var e in Directory.EnumerateFileSystemEntries(dir).ToList())
        {
            var to = Path.Combine(old, Path.GetFileName(e));
            try { Move(e, to); continue; }
            catch (Exception x) when (x is IOException or UnauthorizedAccessException) { }
            if (Directory.Exists(e)) Pieces(e, to);
            else try { File.Copy(e, to, true); } catch { }
        }
    }

    /// <summary>Puts the snapshot in place. Into an empty spot it is one move; next to leftovers that were in use it is
    /// file by file. Returns how many files could not be replaced.</summary>
    static int Put(string from, string target)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        if (!File.Exists(target) && !Directory.Exists(target))
            try { Move(from, target); return 0; } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        if (File.Exists(from)) return TryCopy(from, target) ? 0 : 1;
        int busy = 0;
        foreach (var f in Directory.EnumerateFiles(from, "*", SearchOption.AllDirectories))
        {
            var to = Path.Combine(target, Path.GetRelativePath(from, f));
            Directory.CreateDirectory(Path.GetDirectoryName(to)!);
            if (!TryCopy(f, to)) busy++;
        }
        return busy;
    }

    static bool TryCopy(string from, string to)
    {
        for (int t = 0; t < 3; t++)
        {
            try { Copy(from, to); return true; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Thread.Sleep(Home.Test ? 1 : 300); }
        }
        return false;
    }

    /// <summary>Asks Windows which programs hold files in the folder. Closes the app's own helper programs (msedge*,
    /// chrome*, identity_helper...), never WebView2 (Amnesia's own window and other apps use it) or anything else.
    /// Writes the names of the programs to trace.log, so a "busy" folder can be explained.</summary>
    static void CloseHolders(VaultApp a, string target)
    {
        if (!OperatingSystem.IsWindows() || a.Process == null) return;
        IEnumerable<string> files;
        try
        {
            files = File.Exists(target) ? new[] { target }
                : Directory.EnumerateFiles(target, "*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true }).Take(3000).ToList();
        }
        catch { return; }
        var holders = Locks.Holders(files);
        if (holders.Count == 0) { Home.Trace("vault", $"restore {a.Name}: folder busy, Windows names no program"); return; }
        Home.Trace("vault", $"restore {a.Name}: folder held by " + string.Join(", ", holders.Select(h => h.Name).Distinct()));
        var me = Environment.ProcessId;
        foreach (var (pid, name) in holders)
        {
            if (pid == me || name.StartsWith("msedgewebview2", StringComparison.OrdinalIgnoreCase)) continue;
            var own = name.StartsWith(a.Process, StringComparison.OrdinalIgnoreCase)
                || (a.Chromium && name.Equals("identity_helper", StringComparison.OrdinalIgnoreCase));
            if (!own) continue;
            try { System.Diagnostics.Process.GetProcessById(pid).Kill(true); } catch { }
        }
    }
}
