// What the page can ask C# to do. The page sends {"id":1,"cmd":"preview","arg":{...}}, C# answers
// {"id":1,"ok":true,"data":...}. Unknown commands get ok:false. Long jobs (vault, backup, update) also send
// {"event":"progress","op":"vault","pct":0.4,"step":"Chrome"} while they run; "cancel" stops them.
using System.Text.Json.Nodes;
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

sealed class Bridge(TrayApp tray, Action<JsonNode> post, Func<Func<IWin32Window, string?>, Task<string?>> dialog)
{
    CancellationTokenSource? job;

    // v0.7 lab lock: what the page may still do while it is locked (look, sign out, open things, enter the PIN)
    static readonly HashSet<string> WhileLocked = new()
    {
        "info", "preview", "history", "encryption", "keepList", "vaultInfo", "backupInfo", "advInfo", "open", "openKeep",
        "collectLog", "updateCheck", "signOut", "panicNow", "cancel", "labUnlock", "keepLockNow", "health", "safeInfo", "safeClose", "startupState",
        "modeInfo", "aiReport", "aiParse", // v0.10: only look (modeInfo writes nothing while the lab lock is on)
    };

    public async Task<string> HandleAsync(string json)
    {
        JsonNode? id = null;
        try
        {
            var msg = JsonNode.Parse(json)!;
            id = msg["id"]?.DeepClone();
            var cmd = msg["cmd"]?.GetValue<string>() ?? "";
            var arg = msg["arg"];
            string S(string k) => arg?[k]?.GetValue<string>() ?? "";
            bool B(string k) => arg?[k]?.GetValue<bool>() == true;
            if (LabLock.Closed && !WhileLocked.Contains(cmd)) throw new InvalidOperationException("lab-locked");
            JsonNode? data = cmd switch
            {
                "info" => Info(),
                "preview" => await Preview(),
                "turnOn" => await Task.Run(TurnOn),
                "turnOff" => await Do(() => Setup.TurnOff()),
                "pause" => await Do(() => Setup.Pause(true)),
                "resume" => await Do(() => Setup.Pause(false)),
                "history" => await Task.Run(History),
                "encryption" => await Task.Run(Encryption),
                "set" => await Task.Run(() => Set(S("key"), arg?["value"])),
                "openKeep" => await OpenKeep(S("password")),
                "collectLog" => await Task.Run(CollectLog),
                "open" => await Do(() => OpenLink(S("target"))),
                // Keep List
                "keepList" => await Task.Run(KeepInfo),
                "keepAdd" => await KeepAdd(S("path")),
                "keepRemove" => await Do(() => KeepList.Remove(S("path")), KeepInfo),
                "keepAddApp" => await Task.Run(() => KeepAddMany(arg?["paths"]?.AsArray().Select(x => x!.GetValue<string>()) ?? Array.Empty<string>())),
                // v0.8
                "health" => await Task.Run(() => (JsonNode)Health.Check()),
                "safeInfo" => await Task.Run(SafeInfo),
                "safeCreate" => await Task.Run(() => { KeepLock.With(() => Safe.Create(S("password"))); return SafeInfo(); }),
                "safeOpen" => await Job("safe", (p, c) => { var n = KeepLock.With(() => Safe.Open(S("password"))); var i = SafeInfo(); i["files"] = n; return i; }),
                "safeClose" => await Job("safe", (p, c) => { var n = KeepLock.With(() => Safe.Close("app")); var i = SafeInfo(); i["files"] = n; return i; }),
                "safeShow" => await Do(() => { if (Safe.IsOpen) System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"\"{Safe.OpenDir}\"") { UseShellExecute = true }); }),
                "safeDelete" => await Task.Run(() => { KeepLock.With(() => Safe.Delete(S("password"))); return SafeInfo(); }),
                "enableStartup" => await Do(Setup.EnableStartup, Info),
                "keepStaleOpen" => await Do(() => KeepLock.ClearStale(S("password")), Info),
                // v0.8.1: the open window looks again (focus, every 30 s): Task Manager may switch startup off meanwhile
                "startupState" => await Task.Run(() => (JsonNode)new JsonObject { ["startupDisabled"] = Setup.RunningInstalled && Setup.CheckStartupOff(out _) }),
                // Vault
                "vaultInfo" => await Task.Run(VaultInfo),
                "vaultCreate" => await Task.Run(() => { Vault.Create(S("password"), S("panic"), B("panicFull")); return VaultInfo(); }),
                "vaultChoose" => await Do(() => Vault.Choose(S("name"), B("on")), VaultInfo),
                "vaultAddFolder" => S("path").Length > 0 ? await Task.Run(() => { if (Vault.AddFolder(Core.Home.Full(S("path"))) == null) throw new InvalidOperationException("outside-home"); return VaultInfo(); }) : await VaultAddFolder(),
                "vaultRemoveFolder" => await Do(() => Vault.RemoveFolder(S("name")), VaultInfo),
                "vaultSnapshot" => await Job("vault", (p, c) => { Vault.Snapshot(null, false, null, p, c); return VaultInfo(); }),
                "vaultRestore" => await Job("vault", (p, c) => { var only = VaultProfiles.AppsFor(S("profile")); var n = RestoreSome(S("password"), S("profile"), only, p, c, B("previous")); var i = VaultInfo(); i["ignored"] = new JsonArray((only == null ? new List<string>() : VaultProfiles.Ignored(only)).Select(x => (JsonNode)x!).ToArray()); i["restored"] = new JsonArray(n.Select(x => (JsonNode)x!).ToArray()); var pr = new JsonObject(); foreach (var kv in Vault.LastProblems) pr[kv.Key] = kv.Value; i["problems"] = pr; return i; }),
                "vaultDelete" => await Do(() => Vault.DeleteSnapshots(S("name") is { Length: > 0 } n ? new[] { n } : null), VaultInfo),
                "vaultPassword" => await Task.Run(() => { Vault.ChangePassword(S("old"), S("new")); return VaultInfo(); }),
                "vaultPanic" => await Task.Run(() => { Vault.ChangePanicWord(S("password"), S("word"), B("full")); return VaultInfo(); }),
                // v0.10 vault profiles: named groups of vault apps, so a restore brings back only what you need
                "profiles" => await Task.Run(ProfilesInfo),
                "profileSave" => await Task.Run(() => { var sp = VaultProfiles.Save(S("id"), S("name"), arg?["apps"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() ?? new List<string>()); var i = ProfilesObj(); i["saved"] = sp.Id; return (JsonNode)i; }),
                "profileDelete" => await Do(() => VaultProfiles.Delete(S("id")), ProfilesInfo),
                // Backup
                "backupInfo" => await Task.Run(BackupInfo),
                "backupFolder" => await BackupFolder(),
                "backupNow" => await Job("backup", (p, c) => { var w = KeepLock.With(() => Backup.Create(p, c)); var i = BackupInfo(); i["where"] = w; i["skipped"] = Backup.LastSkipped; return i; }),
                "backupTest" => await Task.Run(() => (JsonNode)new JsonObject { ["error"] = Ssh.Test() }),
                "backupRestore" => await BackupRestore(S("password"), S("file")),
                "backupPick" => await BackupPick(),
                // Advanced
                "advInfo" => await Task.Run(AdvInfo),
                // v0.8.1: one line per app, so Keep gets every row of it (ids); Keep also adds its folders to the Keep List
                "appsKeep" => await Do(() => Apps.Keep(arg?["ids"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() is { Count: > 0 } ids ? ids : new List<string> { S("id") }), AdvInfo),
                "appsKeepAll" => await Do(Apps.KeepAll, AdvInfo),
                "appsUninstall" => await Do(() => Apps.RunUninstaller(S("id")), AdvInfo), // v0.7.1: waits, then the list is fresh
                "usbSet" => await Do(() => { Settings.Set("USB_KEY", S("serial").Length > 0 ? S("serial") : null); Settings.Set("USB_KEY_NAME", S("name").Length > 0 ? S("name") : null); tray.Invoke(tray.Watcher.UsbChanged); }, AdvInfo),
                "adminApply" => await AdminApply(arg),
                "dynamicLock" => await Do(() => DynamicLock(B("on")), AdvInfo),
                // v0.5 (learned from BleachBit, Winapp2, Bulk Crap Uninstaller, privacy.sexy, Win11Debloat, Pearcleaner, Sandboxie, Tails)
                "privacyApply" => await Do(() => Privacy.Apply(arg?["groups"]?.AsArray().Select(x => x!.GetValue<string>()) ?? Array.Empty<string>()), AdvInfo),
                "privacyUndo" => await Do(Privacy.UndoAll, AdvInfo),
                "listDownload" => await ListDownload(),
                "leftScan" => await Task.Run(LeftScan),
                "leftDelete" => await LeftDelete(arg),
                "sandbox" => await Do(() => Extra.OpenSandbox(B("shareKeep"), B("network"))),
                // v0.7 lab lock + Keep lock
                "labOn" => await Task.Run(() => { if (!LabLock.TurnOn(S("pin"))) throw new InvalidOperationException("admin-no"); return AdvInfo(); }),
                "labOff" => await Task.Run(() => { if (!LabLock.TurnOff(S("pin"))) throw new InvalidOperationException("admin-no"); return AdvInfo(); }),
                "labUnlock" => await Task.Run(() => { if (!LabLock.Unlock(S("pin"))) throw new InvalidOperationException("lab-pin-wrong"); return AdvInfo(); }),
                "labClose" => await Do(LabLock.Close, AdvInfo),
                "keepLockOn" => await Do(() => KeepLock.TurnOn(S("password"), int.TryParse(S("minutes"), out var km) ? km : 15), AdvInfo),
                "keepLockOff" => await Do(() => KeepLock.TurnOff(S("password")), AdvInfo),
                "keepLockNow" => await Do(() => KeepLock.Lock("app"), AdvInfo),
                "keepLockMin" => await Do(() => Settings.Set("KEEP_LOCK_MIN", int.TryParse(S("minutes"), out var mm) ? Math.Clamp(mm, 1, 240).ToString() : "15"), AdvInfo),
                "wipeFree" => await Do(Extra.WipeFreeSpace),
                "sysClean" => await SysClean(),
                "signOut" => await Do(Guard.SignOut),
                "panicNow" => await Do(() => Guard.QuickExit("app")),
                // Update + uninstall
                "updateCheck" => await UpdateCheck(),
                "updateInstall" => await UpdateInstall(),
                "uninstall" => await Do(() => { Setup.Uninstall(B("all"), S("password")); tray.Invoke(() => Task.Delay(1500).ContinueWith(_ => tray.Invoke(tray.Quit))); }),
                // v0.9 Care
                "careOverview" => await Job("care", (p, c) => CareOverview(c)),
                "careScan" => await Job("care", (p, c) => CareScan(S("feature"), c)),
                "careAct" => await Job("care", (p, c) => CareAct(S("feature"), arg, c)),
                "carePrograms" => await Task.Run(CarePrograms),
                "careUninstall" => await Job("care", (p, c) => CareUninstall(S("id"), c)),
                "careTune" => await Task.Run(() => CareTune(arg)),
                "careOpen" => await Do(() => CareWin.Open(S("target"))),
                "careReveal" => await Do(() => CareWin.Reveal(S("path"))),
                // v0.10 Amnesia modes + Ask an AI (no network: the page copies or saves, the user pastes)
                "modeInfo" => await Task.Run(ModeInfo),
                "modePreview" => await Job("mode", (p, c) => ModePreviewJob(S("mode"), Strs(arg?["add"]), Strs(arg?["remove"]))),
                "modeCommit" => await Task.Run(() => ModeCommit(S("mode"))),
                "aiReport" => await Job("ai", (p, c) => AiReportJob(B("hideNames"), S("lang"))),
                "aiSave" => await Job("ai", (p, c) => AiSaveJob(B("hideNames"), S("lang"))),
                "aiParse" => await Task.Run(() => (JsonNode)AiReport.Parse(S("text"))),
                "cancel" => await Do(() => job?.Cancel()),
                _ => throw new InvalidOperationException($"Unknown command: {cmd}"),
            };
            return new JsonObject { ["id"] = id, ["ok"] = true, ["data"] = data }.ToJsonString();
        }
        catch (Exception ex)
        {
            var err = ex switch
            {
                VaultError v => $"vault:{v.Code}:{v.Left}",
                OperationCanceledException => "cancelled",
                AggregateException { InnerException: VaultError v } => $"vault:{v.Code}:{v.Left}",
                _ => ex.Message,
            };
            return new JsonObject { ["id"] = id, ["ok"] = false, ["error"] = err }.ToJsonString();
        }
    }

    JsonNode Info()
    {
        var view = tray.PendingView;
        tray.PendingView = null;
        return new JsonObject
        {
            ["version"] = AppInfo.Version,
            ["windows"] = Environment.OSVersion.VersionString,
            ["arch"] = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant(),
            ["lang"] = AppInfo.Id ? "id" : "en",
            ["langSetting"] = Settings.Get("LANG") ?? "auto",
            ["home"] = AppInfo.Home,
            ["enabled"] = Settings.Enabled,
            ["paused"] = Settings.Paused,
            ["installed"] = Setup.RunningInstalled,
            ["fromSetup"] = Updater.FromSetup,
            ["keepDir"] = Settings.KeepDir,
            ["keepShortcut"] = Settings.KeepShortcut,
            ["keepPin"] = Settings.KeepPin,
            ["welcomeDone"] = Settings.Get("WELCOME_DONE") == "1",
            ["view"] = view,
            ["vault"] = Vault.Exists,
            ["vaultAuto"] = Settings.Get("VAULT_AUTO") != "0",
            ["restoreRemind"] = Settings.Get("RESTORE_REMIND") != "0",
            ["updateDays"] = Settings.UpdateDays,
            ["labOn"] = LabLock.Active,
            ["labOpen"] = LabLock.Active && !LabLock.Closed,
            ["doomsday"] = Settings.Get("DOOMSDAY") != "0",
            ["idleMin"] = Conf.Int("IDLE_MIN"),
            ["removeNewApps"] = Apps.On,
            ["panicHotkey"] = Settings.Get("PANIC_HOTKEY") ?? "",
            ["usbKey"] = Settings.Get("USB_KEY_NAME") ?? "",
            ["lastBlocked"] = Settings.Get("LAST_BLOCKED") ?? "",
            ["extraList"] = Winapp2.On,
            ["usbAction"] = Settings.Get("USB_ACTION") ?? "signout",
            // v0.8
            ["openAtLogin"] = Setup.OpenAtLogin,
            ["startupDisabled"] = Setup.RunningInstalled && Setup.CheckStartupOff(out _),
            ["keepVm"] = Settings.Get("KEEP_VM") != "0",
            ["wipeStore"] = Settings.Get("WIPE_STORE") == "1",
            ["wipeCreds"] = Creds.On,
            ["keepLocked"] = KeepLock.On,
            // v0.8.1: Keep still locked by an old version (the Keep lock itself is off)
            ["keepStale"] = KeepStale(),
            ["keepStalePw"] = KeepLock.StaleNeedsPassword,
            ["signedUpdates"] = Updater.Signed,
        };
    }

    static bool KeepStale() { try { return KeepLock.Stale; } catch { return false; } }

    // ---------- settings switches (only these keys) ----------
    JsonNode Set(string key, JsonNode? value)
    {
        string? On(bool defaultOn) => value?.GetValue<bool>() == true ? "1" : "0";
        string? V() => value?.ToString();
        switch (key)
        {
            case "keepShortcut": Settings.Set("KEEP_SHORTCUT", On(true)); KeepLinks.Sync(); break;
            case "keepPin": Settings.Set("KEEP_PIN", On(true)); KeepLinks.Sync(); break;
            case "lang": Settings.Set("LANG", V() is "en" or "id" ? V() : null); break;
            case "welcomeDone": Settings.Set("WELCOME_DONE", "1"); break;
            case "vaultAuto": Settings.Set("VAULT_AUTO", On(true)); break;
            case "restoreRemind": Settings.Set("RESTORE_REMIND", On(true)); break;
            case "updateDays": Settings.Set("UPDATE_DAYS", V() is "0" or "7" or "14" or "30" ? V() : "7"); break;
            case "doomsday": Settings.Set("DOOMSDAY", On(true)); break;
            case "idleMin": Settings.Set("IDLE_MIN", int.TryParse(V(), out var m) && m is > 0 and <= 240 ? m.ToString() : "0"); break;
            case "removeNewApps":
                Settings.Set("REMOVE_NEW_APPS", On(false));
                if (Apps.On && !Apps.HasBaseline) Apps.TakeBaseline();
                break;
            case "panicHotkey":
                Settings.Set("PANIC_HOTKEY", Guard.Hotkeys.Any(h => h.id == V()) ? V() : null);
                var ok = true;
                var done = new ManualResetEventSlim();
                tray.Invoke(() => { ok = tray.Watcher.ApplyHotkey(); done.Set(); });
                done.Wait(3000);
                if (!ok) { Settings.Set("PANIC_HOTKEY", null); throw new InvalidOperationException("hotkey-taken"); }
                break;
            case "extraList": Settings.Set("EXTRA_LIST", On(false)); break;
            // v0.8
            case "openAtLogin": Settings.Set("OPEN_AT_LOGIN", On(true)); if (Setup.RunningInstalled) Setup.SyncStartup(); break;
            case "keepVm": Settings.Set("KEEP_VM", On(true)); break;
            case "wipeStore": Settings.Set("WIPE_STORE", On(false) == "1" ? "1" : null); break;
            case "wipeCreds": Settings.Set("WIPE_CREDS", On(false) == "1" ? "1" : null); break;
            case "usbAction": Settings.Set("USB_ACTION", V() == "shutdown" ? "shutdown" : null); break;
            case "backupEvery": Settings.Set("BACKUP_EVERY", V() is "day" or "week" ? V() : null); break;
            case "backupKind": Settings.Set("BACKUP_KIND", V() == "ssh" ? "ssh" : "folder"); break;
            case "backupSsh":
                var t = V()?.Trim();
                Settings.Set("BACKUP_SSH", string.IsNullOrEmpty(t) ? null : t);
                if (!string.IsNullOrEmpty(t)) KeepList.Add(".ssh"); // your SSH key must survive the sign out
                break;
            case "backupPort": Settings.Set("BACKUP_PORT", int.TryParse(V(), out var p) && p is > 0 and < 65536 ? p.ToString() : null); break;
            default: throw new InvalidOperationException($"Unknown setting: {key}");
        }
        return Info();
    }

    // v0.6: everything runs off the window's thread, so the window never freezes ("Not Responding") while Amnesia
    // writes the registry, scans programs or waits for Windows.
    static Task<JsonNode> Do(Action a) => Task.Run(() => { a(); return (JsonNode)new JsonObject(); });
    static Task<JsonNode> Do(Action a, Func<JsonNode> then) => Task.Run(() => { a(); return then(); });
    static Task<JsonNode> Do(Func<bool> a, Func<JsonNode> then) => Task.Run(() => { a(); return then(); });

    JsonNode TurnOn()
    {
        if (Setup.TurnOn())
        {
            // first time: Amnesia now lives in the install folder; start that copy and close this one
            var exe = Setup.InstalledExe;
            Task.Delay(800).ContinueWith(_ => tray.Invoke(() => { Program.HandOver(exe); tray.Quit(); }));
            var i = (JsonObject)Info();
            i["restarting"] = true;
            return i;
        }
        KeepLinks.Sync();
        return Info();
    }

    /// <summary>Preview + (v0.4) the programs "Remove new apps" would take away. Also used by "Review and sign out".
    /// v0.7.1: with the size of each file and folder (the page sorts and filters by it).</summary>
    static async Task<JsonNode> Preview()
    {
        var r = await Cleaner.PreviewAsync();
        var sizes = await Task.Run(() =>
        {
            var d = new Dictionary<string, long>();
            Parallel.ForEach(r.Items.Where(i => i.Kind is "file" or "folder" || i.Kind == "trace" && i.Path.StartsWith("AppData\\", StringComparison.OrdinalIgnoreCase)),
                new ParallelOptions { MaxDegreeOfParallelism = 4 },
                i => { var n = CleanEngine.SizeOf(Core.Home.Full(i.Path)); lock (d) d[i.Path] = n; });
            return d;
        });
        var o = new JsonObject
        {
            ["count"] = r.Count,
            ["items"] = new JsonArray(r.Items.Select(i => (JsonNode)new JsonObject { ["path"] = i.Path, ["kind"] = i.Kind, ["size"] = sizes.GetValueOrDefault(i.Path, -1), ["app"] = AppOf(i.Path) }).ToArray()),
            ["kept"] = new JsonArray(r.Kept.Select(k => (JsonNode)k!).ToArray()),
            ["skipped"] = r.Skipped,   // v0.9: "keeplist-missing|keeplist-unreadable" when the Keep List stops the run
        };
        if (Apps.On)
            o["apps"] = await Task.Run(() => new JsonArray(Apps.NewGroups().Where(g => g.Items.Any(a => a.Auto)).Select(g => (JsonNode)new JsonObject { ["name"] = g.Name, ["kind"] = g.Items.First(a => a.Auto).Kind }).ToArray()));
        return o;
    }

    static JsonObject SafeInfo() => new()
    {
        ["exists"] = Safe.Exists,
        ["open"] = Safe.IsOpen,
        ["dir"] = Safe.OpenDir,
        ["size"] = Safe.Exists ? new FileInfo(Safe.File_).Length : 0,
        ["min"] = Safe.MinPassword,
        ["count"] = Safe.Count, // v0.8.1: the uninstall warning (-1 = not known yet)
    };

    /// <summary>v0.8: the app an item in "What gets wiped" belongs to (the review groups by it).</summary>
    static string? AppOf(string path)
    {
        if (!path.StartsWith("AppData\\", StringComparison.OrdinalIgnoreCase)) return null;
        try { return AppCatalog.For(path.Replace('\\', '/'))?.Name; } catch { return null; }
    }

    /// <summary>A long job on a worker thread, with progress events to the page.</summary>
    async Task<JsonNode> Job(string op, Func<Action<double, string>, CancellationToken, JsonNode> work)
    {
        if (job != null) throw new InvalidOperationException("busy");
        job = new CancellationTokenSource();
        var last = DateTime.MinValue;
        void Progress(double pct, string step)
        {
            if ((DateTime.Now - last).TotalMilliseconds < 150 && pct < 1) return;
            last = DateTime.Now;
            post(new JsonObject { ["event"] = "progress", ["op"] = op, ["pct"] = pct, ["step"] = step });
        }
        try { return await Task.Run(() => work(Progress, job.Token)); }
        finally { job.Dispose(); job = null; }
    }

    // ---------- Keep List ----------
    static JsonNode KeepInfo()
    {
        var paths = KeepList.Paths();
        // v0.8: each line shows the app it belongs to (name + icon) when Amnesia can tell
        List<CatalogApp> catalog;
        try { catalog = AppCatalog.Get(); } catch (Exception e) { AppInfo.Trace($"app list failed: {e.GetType().Name}"); catalog = new(); }
        CatalogApp? Owner(string p) => catalog.FirstOrDefault(a => a.Paths.Any(x => x.Equals(p, StringComparison.OrdinalIgnoreCase) || p.StartsWith(x + "/", StringComparison.OrdinalIgnoreCase)));
        bool Kept(string rel) => paths.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*"));
        var list = new JsonArray(paths.Select(p =>
        {
            var app = Owner(p);
            return (JsonNode)new JsonObject { ["path"] = p, ["exists"] = File.Exists(Core.Home.Full(p)) || Directory.Exists(Core.Home.Full(p)) || p.Contains('*'), ["app"] = app?.Name, ["icon"] = app?.Icon };
        }).ToArray());
        // "Keep an app...": installed apps with the folders they keep their data in
        var apps = new JsonArray(catalog.Select(a => (JsonNode)new JsonObject
        {
            ["name"] = a.Name, ["icon"] = a.Icon, ["store"] = a.Store, ["kept"] = a.Paths.All(Kept),
            ["paths"] = new JsonArray(a.Paths.Select(x => (JsonNode)x!).ToArray()),
        }).ToArray());
        // suggestions: app data folders found on this PC that are not on the list yet
        var sugg = new JsonArray();
        var skip = AppMatch.Skip.Concat(new[] { "Mozilla" }).ToArray();
        foreach (var root in new[] { "AppData/Roaming", "AppData/Local" })
        {
            var dir = Core.Home.Full(root);
            if (!Directory.Exists(dir)) continue;
            foreach (var d in new DirectoryInfo(dir).EnumerateDirectories().Where(d => !d.Attributes.HasFlag(FileAttributes.ReparsePoint)).OrderBy(d => d.Name))
            {
                var rel = $"{root}/{d.Name}";
                if (skip.Contains(d.Name, StringComparer.OrdinalIgnoreCase) || paths.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*"))) continue;
                var app = Owner(rel);
                if (app == null && AppMatch.Technical(d.Name)) continue; // v0.8.1: Sentry, AMD_Common... are not apps
                // v0.8.1: the same app in Local and Roaming is one chip that keeps both
                if (sugg.OfType<JsonObject>().FirstOrDefault(o => string.Equals(o["name"]?.GetValue<string>(), app?.Name ?? d.Name, StringComparison.OrdinalIgnoreCase)) is { } same)
                {
                    same["paths"]!.AsArray().Add(rel);
                    continue;
                }
                sugg.Add(new JsonObject { ["name"] = app?.Name ?? d.Name, ["path"] = rel, ["paths"] = new JsonArray(rel), ["icon"] = app?.Icon });
            }
        }
        // v0.7.1: Claude from the Microsoft Store keeps its data inside Packages (skipped above), not in Roaming\Claude
        foreach (var store in Directory.Exists(Core.Home.Full("AppData/Local/Packages")) ? new DirectoryInfo(Core.Home.Full("AppData/Local/Packages")).EnumerateDirectories("Claude_*") : Enumerable.Empty<DirectoryInfo>())
        {
            var rel = $"AppData/Local/Packages/{store.Name}/LocalCache/Roaming/Claude";
            if (Directory.Exists(Core.Home.Full(rel)) && !paths.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*")))
                sugg.Add(new JsonObject { ["name"] = "Claude (Microsoft Store)", ["path"] = rel });
        }
        foreach (var dot in new[] { ".ssh", ".gitconfig", ".vscode", ".npmrc" })
            if ((File.Exists(Core.Home.Full(dot)) || Directory.Exists(Core.Home.Full(dot))) && !paths.Contains(dot, StringComparer.OrdinalIgnoreCase))
                sugg.Insert(0, new JsonObject { ["name"] = dot, ["path"] = dot });
        return new JsonObject { ["paths"] = list, ["suggestions"] = sugg, ["apps"] = apps, ["keepDir"] = Settings.KeepDir, ["home"] = Core.Home.User };
    }

    async Task<JsonNode> KeepAdd(string path)
    {
        if (path.Length == 0) path = await PickFolder() ?? "";
        if (path.Length == 0) return await Task.Run(KeepInfo);
        await Task.Run(() => AddChecked(path));
        return await Task.Run(KeepInfo);
    }

    /// <summary>v0.8: adds a line and reads keep.conf back, so a line that did not land (seen in the Windows test with a
    /// path inside Packages) is an error on the page instead of a silent "done".</summary>
    static void AddChecked(string path)
    {
        var line = KeepList.Add(path);
        var norm = line ?? KeepList.Norm(path);
        if (line == null && !KeepList.Paths().Contains(norm, StringComparer.OrdinalIgnoreCase)) throw new InvalidOperationException("outside-home");
        if (!KeepList.Paths().Contains(line ?? norm, StringComparer.OrdinalIgnoreCase))
        {
            AppInfo.Trace("keep list: a new line was not saved");
            throw new InvalidOperationException("keep-not-saved");
        }
    }

    static JsonNode KeepAddMany(IEnumerable<string> paths)
    {
        foreach (var p in paths) AddChecked(p);
        return KeepInfo();
    }

    Task<string?> PickFolder(string? start = null) => dialog(owner =>
    {
        using var d = new FolderBrowserDialog { UseDescriptionForTitle = true, Description = "Amnesia", SelectedPath = start ?? Core.Home.User, ShowNewFolderButton = true };
        return d.ShowDialog(owner) == DialogResult.OK ? d.SelectedPath : null;
    });

    // ---------- Vault ----------
    static JsonNode VaultInfo()
    {
        var m = Vault.Manifest();
        var chosen = Vault.Chosen();
        var apps = new JsonArray();
        foreach (var a in Vault.All())
        {
            bool present = Vault.Present(a).Length > 0;
            if (!present && !m.ContainsKey(a.Name) && !a.Name.StartsWith(Vault.FolderPrefix)) continue; // not on this PC
            apps.Add(new JsonObject
            {
                ["name"] = a.Name,
                ["folder"] = a.Name.StartsWith(Vault.FolderPrefix),
                ["present"] = present,
                ["chosen"] = chosen.Contains(a.Name),
                ["time"] = m[a.Name]?["time"]?.GetValue<string>(),
                ["size"] = m[a.Name]?["size"]?.GetValue<long>(),
                ["prevTime"] = m[a.Name]?["prevTime"]?.GetValue<string>(),
                ["shrunk"] = m[a.Name]?["shrunk"]?.GetValue<bool>() ?? false,
                ["setup"] = m[a.Name]?["setup"]?.GetValue<string>(),
            });
        }
        return new JsonObject
        {
            ["exists"] = Vault.Exists,
            ["panic"] = Vault.HasPanicWord,
            ["attempts"] = Vault.Attempts,
            ["max"] = Vault.MaxAttempts,
            ["min"] = Vault.MinPassword,
            ["doomsday"] = Settings.Get("DOOMSDAY") != "0",
            ["auto"] = Settings.Get("VAULT_AUTO") != "0",
            ["apps"] = apps,
            ["suggest"] = VaultSuggest(),
        };
    }

    /// <summary>v0.8: installed apps whose data the vault does not know yet (they can be added as a folder).</summary>
    static JsonArray VaultSuggest()
    {
        var arr = new JsonArray();
        try
        {
            var known = Vault.All().SelectMany(Vault.Present).Select(p => p.Replace('\\', '/')).ToList();
            var home = Core.Home.User.Replace('\\', '/');
            foreach (var a in AppCatalog.Get())
            {
                var p = a.Paths.FirstOrDefault();
                if (p == null || a.Store) continue;
                var full = home + "/" + p;
                if (known.Any(k => k.Equals(full, StringComparison.OrdinalIgnoreCase) || k.StartsWith(full + "/", StringComparison.OrdinalIgnoreCase) || full.StartsWith(k + "/", StringComparison.OrdinalIgnoreCase))) continue;
                arr.Add(new JsonObject { ["name"] = a.Name, ["icon"] = a.Icon, ["path"] = p });
                if (arr.Count >= 12) break;
            }
        }
        catch { }
        return arr;
    }

    // ---------- v0.10 vault profiles ----------
    /// <summary>Restores everything (no profile) or only the apps of one profile. The choice is remembered for next time.
    /// A profile with no snapshot gets its own error, so the page can say "none of these apps has a snapshot yet".</summary>
    static List<string> RestoreSome(string password, string profile, List<string>? only, Action<double, string> p, CancellationToken c, bool previous)
    {
        VaultProfiles.Last = profile.Length == 0 ? VaultProfiles.AllId : profile;
        try { return Vault.Restore(password, only, p, c, previous); }
        catch (VaultError e) when (e.Code == "no-snapshot" && only != null) { throw new VaultError("no-snapshot-profile"); }
    }

    static JsonNode ProfilesInfo() => ProfilesObj();

    /// <summary>{profiles:[{id,name,apps,builtin,missing,snapshots}], last, shared:{app:[ids]}, apps:[{name,present,snapshot}], mode}</summary>
    static JsonObject ProfilesObj()
    {
        VaultProfiles.Indonesian ??= () => AppInfo.Id;
        var m = Vault.Manifest();
        var here = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var apps = new JsonArray();
        foreach (var a in Vault.All())
        {
            bool present = Vault.Present(a).Length > 0, snap = m.ContainsKey(a.Name);
            if (present) here.Add(a.Name);
            if (!present && !snap && !a.Name.StartsWith(Vault.FolderPrefix)) continue; // not on this PC
            apps.Add(new JsonObject { ["name"] = a.Name, ["present"] = present, ["snapshot"] = snap });
        }
        static JsonArray Arr(IEnumerable<string> xs) => new(xs.Select(x => (JsonNode)x!).ToArray());
        var list = new JsonArray();
        foreach (var pr in VaultProfiles.All())
        {
            var own = pr.Id == VaultProfiles.AllId ? pr.Apps.Where(a => m.ContainsKey(a) || here.Contains(a)).ToList() : pr.Apps;
            list.Add(new JsonObject
            {
                ["id"] = pr.Id,
                ["name"] = pr.Name,
                ["apps"] = Arr(own),
                ["builtin"] = pr.BuiltIn,
                ["missing"] = Arr(own.Where(a => !here.Contains(a))),
                ["snapshots"] = Arr(own.Where(m.ContainsKey)),
            });
        }
        var shared = new JsonObject();
        foreach (var kv in VaultProfiles.Shared()) shared[kv.Key] = Arr(kv.Value);
        return new JsonObject
        {
            ["profiles"] = list,
            ["last"] = VaultProfiles.Last,
            ["shared"] = shared,
            ["apps"] = apps,
            ["mode"] = Settings.Get("AMNESIA_MODE") ?? "",
        };
    }

    async Task<JsonNode> VaultAddFolder()
    {
        var p = await PickFolder();
        if (p != null && Vault.AddFolder(p) == null) throw new InvalidOperationException("outside-home");
        return await Task.Run(VaultInfo);
    }

    // ---------- Backup ----------
    static JsonNode BackupInfo() => new JsonObject
    {
        ["kind"] = Backup.Kind,
        ["folder"] = Backup.Folder,
        ["folderThere"] = Backup.Folder != null && Directory.Exists(Backup.Folder),
        ["ssh"] = Settings.Get("BACKUP_SSH"),
        ["port"] = Settings.Get("BACKUP_PORT") ?? "22",
        ["sshReady"] = Ssh.Available,
        ["every"] = Settings.Get("BACKUP_EVERY") ?? "off",
        ["last"] = Settings.Get("BACKUP_LAST"),
        ["vault"] = Vault.Exists,
        ["list"] = new JsonArray(Backup.List().Take(20).Select(f => (JsonNode)new JsonObject { ["name"] = f.Name, ["path"] = f.FullName, ["size"] = f.Length }).ToArray()),
    };

    async Task<JsonNode> BackupFolder()
    {
        var p = await PickFolder(Backup.Folder);
        if (p != null)
        {
            // a backup folder inside the user folder would be wiped at sign out (unless it is in Keep)
            var home = Core.Home.User + "\\";
            // v0.8: and a backup inside Keep would be packed into every next backup (each one twice as big)
            var keep = Settings.KeepDir.TrimEnd('\\');
            if (p.Equals(keep, StringComparison.OrdinalIgnoreCase) || p.StartsWith(keep + "\\", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("backup-in-keep");
            if (p.StartsWith(home, StringComparison.OrdinalIgnoreCase)
                && !p.Contains("OneDrive", StringComparison.OrdinalIgnoreCase) && !p.Contains("Google Drive", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("backup-in-home");
            Settings.Set("BACKUP_DEST", p);
            Settings.Set("BACKUP_KIND", "folder");
        }
        return BackupInfo();
    }

    async Task<JsonNode> BackupPick()
    {
        var f = await dialog(owner =>
        {
            using var d = new OpenFileDialog { Filter = "Amnesia backup (*.amb)|*.amb", InitialDirectory = Backup.Folder ?? "" };
            return d.ShowDialog(owner) == DialogResult.OK ? d.FileName : null;
        });
        return new JsonObject { ["file"] = f };
    }

    async Task<JsonNode> BackupRestore(string password, string file)
    {
        if (!File.Exists(file)) throw new InvalidOperationException("no-file");
        return await Job("restore", (p, c) => { var n = KeepLock.With(() => Backup.Restore(file, password, p, c)); return new JsonObject { ["count"] = n }; });
    }

    // ---------- Advanced ----------
    static JsonNode AdvInfo()
    {
        var adm = AdminTasks.Status();
        return new JsonObject
        {
            // v0.8.1: one line per app (its uninstall entry, Start menu shortcut and registry key together)
            ["apps"] = Apps.On ? new JsonArray(Apps.NewGroups().Select(g => (JsonNode)new JsonObject
            {
                ["id"] = g.Id, ["name"] = g.Name, ["kind"] = g.Items[0].Kind, ["auto"] = g.Items.Any(a => a.Auto),
                ["ids"] = new JsonArray(g.Items.Select(a => (JsonNode)a.Id!).ToArray()),
                ["kinds"] = new JsonArray(g.Items.Select(a => a.Kind).Distinct().Select(k => (JsonNode)k!).ToArray()),
                ["canUninstall"] = g.Uninstaller != null, ["uninstallId"] = g.Uninstaller?.Id,
            }).ToArray()) : new JsonArray(),
            ["usb"] = new JsonArray(Guard.UsbDrives().Select(d => (JsonNode)new JsonObject { ["root"] = d.root, ["label"] = d.label, ["serial"] = d.serial }).ToArray()),
            ["usbKey"] = Settings.Get("USB_KEY_NAME") ?? "",
            ["usbPresent"] = Guard.UsbKeyPresent(),
            ["admin"] = new JsonObject(adm.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)kv.Value))),
            ["dynamicLock"] = DynamicLockOn(),
            ["cfa"] = ControlledFolderAccess(),
            ["privacy"] = new JsonObject(Privacy.Status().Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)kv.Value))),
            ["list"] = ListInfo(),
            ["sandbox"] = Extra.SandboxReady,
            ["lab"] = new JsonObject
            {
                ["on"] = LabLock.Active,
                ["open"] = LabLock.Active && !LabLock.Closed,
                ["since"] = Lab.Get("LOCKED"),
            },
            ["keepLock"] = new JsonObject
            {
                ["on"] = KeepLock.On,
                ["locked"] = KeepLock.On && KeepLock.IsLocked,
                ["minutes"] = KeepLock.Minutes,
            },
        };
    }

    /// <summary>v0.7: "Open Keep" in the page. A locked Keep needs the Keep password (asked in the page).</summary>
    static async Task<JsonNode> OpenKeep(string password)
    {
        return await Task.Run(() =>
        {
            if (KeepLock.On && KeepLock.IsLocked)
            {
                if (password.Length == 0) throw new InvalidOperationException("keeplock-ask");
                if (!KeepLock.UnlockFor(password)) throw new InvalidOperationException("keeplock-wrong");
            }
            KeepLinks.OpenKeep();
            return (JsonNode)new JsonObject();
        });
    }

    static JsonNode ListInfo()
    {
        var (exists, version, entries, date) = Extra.ListInfo();
        return new JsonObject { ["exists"] = exists, ["version"] = version, ["entries"] = entries, ["date"] = date, ["on"] = Winapp2.On };
    }

    static async Task<JsonNode> ListDownload()
    {
        try { await Extra.DownloadListAsync(); }
        catch (HttpRequestException) { throw new InvalidOperationException("offline"); }
        catch (TaskCanceledException) { throw new InvalidOperationException("offline"); }
        return await Task.Run(AdvInfo);
    }

    static JsonNode LeftScan()
    {
        var (folders, keys) = Apps.FindLeftovers();
        return new JsonObject
        {
            ["folders"] = new JsonArray(folders.Select(f => (JsonNode)new JsonObject { ["path"] = f.Path, ["name"] = f.Name, ["level"] = f.Level, ["empty"] = f.Empty, ["size"] = f.Bytes }).ToArray()),
            ["keys"] = new JsonArray(keys.Select(k => (JsonNode)k!).ToArray()),
        };
    }

    static async Task<JsonNode> LeftDelete(JsonNode? arg)
    {
        var folders = arg?["folders"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() ?? new List<string>();
        var keys = arg?["keys"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() ?? new List<string>();
        bool ok = await Task.Run(() => Apps.DeleteLeftovers(folders, keys));
        if (!ok) throw new InvalidOperationException("admin-no");
        Core.Home.History("leftovers", (folders.Count + keys.Count).ToString());
        return await Task.Run(LeftScan);
    }

    static async Task<JsonNode> SysClean()
    {
        bool ok = await Task.Run(() => AdminTasks.Run("sysclean=1"));
        if (!ok) throw new InvalidOperationException("admin-no");
        Core.Home.History("sysclean", "1");
        return new JsonObject();
    }

    static async Task<JsonNode> AdminApply(JsonNode? arg)
    {
        var want = new[] { "pagefile", "hiber", "recall", "activity", "copilot", "telemetry" }.ToDictionary(k => k, k => arg?[k]?.GetValue<bool>() == true);
        bool ok = await Task.Run(() => AdminTasks.Apply(want));
        if (!ok) throw new InvalidOperationException("admin-no");
        return await Task.Run(AdvInfo);
    }

    const string Winlogon = @"Software\Microsoft\Windows NT\CurrentVersion\Winlogon";
    static bool DynamicLockOn() { using var k = Registry.CurrentUser.OpenSubKey(Winlogon); return k?.GetValue("EnableGoodbye") is int i && i == 1; }
    /// <summary>Dynamic Lock: Windows locks itself when your paired phone walks away (Bluetooth). Windows' own switch.</summary>
    static void DynamicLock(bool on) { using var k = Registry.CurrentUser.CreateSubKey(Winlogon); k.SetValue("EnableGoodbye", on ? 1 : 0, RegistryValueKind.DWord); }

    /// <summary>Windows Security "Controlled folder access" (blocks unknown apps from changing Documents, Desktop...).</summary>
    static string ControlledFolderAccess()
    {
        try
        {
            using var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access");
            return k?.GetValue("EnableControlledFolderAccess") switch { 1 => "on", 2 => "audit", 0 => "off", _ => "unknown" };
        }
        catch { return "unknown"; }
    }

    /// <summary>Opens a Windows settings page or the website. Only these targets.</summary>
    static void OpenLink(string target)
    {
        var uri = target switch
        {
            "security" => "windowsdefender://ransomwareprotection",
            "bluetooth" => "ms-settings:bluetooth",
            "dynamicLock" => "ms-settings:signinoptions-dynamiclock",
            "encryption" => "ms-settings:deviceencryption",
            "recall" => "ms-settings:privacy-recall",
            "wifi" => "ms-settings:network-wifi",          // v0.5 (Tails idea): "Random hardware addresses"
            "features" => "optionalfeatures.exe",          // v0.5: switch on Windows Sandbox
            "winapp2" => "https://github.com/MoscaDotTo/Winapp2",
            "releases" => Updater.Releases,
            "site" => "https://navi-crwn.github.io/amnesia/win/",
            "falsePositive" => "https://www.microsoft.com/en-us/wdsi/filesubmission",
            _ => throw new InvalidOperationException("unknown link"),
        };
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
    }

    // ---------- Update ----------
    static async Task<JsonNode> UpdateCheck()
    {
        var r = await Updater.LatestAsync();
        return new JsonObject
        {
            ["current"] = AppInfo.Version,
            ["latest"] = r?.Version,
            ["newer"] = r != null && Updater.Newer(r.Version),
            ["canInstall"] = r?.Setup != null && r.Sums != null && r.Sig != null && Updater.Signed && Updater.FromSetup,
            ["page"] = r?.Page ?? Updater.Releases,
        };
    }

    async Task<JsonNode> UpdateInstall()
    {
        var r = await Updater.LatestAsync() ?? throw new InvalidOperationException("no-release");
        await Job("update", (p, c) => { Updater.InstallAsync(r, new Progress<double>(x => p(x, ""))).GetAwaiter().GetResult(); return new JsonObject(); });
        // the setup closes and reopens Amnesia; quit now so it can replace Amnesia.exe
        tray.Invoke(() => Task.Delay(1000).ContinueWith(_ => tray.Invoke(tray.Quit)));
        return new JsonObject();
    }

    // ---------- History, encryption, log ----------
    /// <summary>history.log: "time<TAB>kind<TAB>data", newest first, at most 50.</summary>
    static JsonNode History()
    {
        var f = Path.Combine(AppInfo.Home, "history.log");
        var arr = new JsonArray();
        if (!File.Exists(f)) return arr;
        foreach (var l in File.ReadAllLines(f).Reverse().Take(50))
        {
            var p = l.Split('\t');
            if (p.Length < 3) continue;
            arr.Add(new JsonObject { ["time"] = p[0], ["kind"] = p[1], ["data"] = p[2] });
        }
        return arr;
    }

    /// <summary>"Collect log" (scripts\collect-log.ps1, only when you press the button): writes amnesia-log.txt in
    /// the Keep folder and opens it in Notepad. v0.7.1: answers with where the file is (the page shows it).</summary>
    static JsonNode CollectLog()
    {
        var psi = new System.Diagnostics.ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true };
        foreach (var a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(AppInfo.BaseDir, "scripts", "collect-log.ps1"), "-Dir", Settings.KeepDir })
            psi.ArgumentList.Add(a);
        // v0.7: the log goes into Keep, so a locked Keep is opened for the moment it takes
        var file = Path.Combine(Settings.KeepDir, "amnesia-log.txt");
        bool ok = KeepLock.With(() => { using var proc = System.Diagnostics.Process.Start(psi); proc?.WaitForExit(60_000); return File.Exists(file); });
        return new JsonObject { ["path"] = file, ["ok"] = ok };
    }

    /// <summary>BitLocker / device encryption on the Windows drive. Read without admin rights through Explorer's own
    /// property (v0.4: straight from C#, no PowerShell).</summary>
    static JsonNode Encryption()
    {
        var drive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:").TrimEnd('\\');
        object? v = null;
        var t = new Thread(() =>
        {
            try
            {
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application")!)!;
                v = shell.NameSpace(drive + "\\").Self.ExtendedProperty("System.Volume.BitLockerProtection");
            }
            catch { }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join(20_000);
        // 1 on, 2 off, 3 encrypting, 4 decrypting, 5 suspended, 6 on (locked); nothing = not available on this PC
        var state = v?.ToString() switch { "1" or "3" or "6" => "on", "5" => "paused", "2" or "4" => "off", _ => "unknown" };
        return new JsonObject { ["state"] = state, ["drive"] = drive };
    }

    // ---------- v0.9 Care ----------
    // The last list of each feature. The page sends back only ids: paths never come from the page.
    static readonly Dictionary<string, List<CareItem>> careLists = new();
    // what the uninstall itself did, counted in the History line written after its leftovers
    static (int items, long kb, int failed) careBase;

    static JsonObject CareJson(CareItem i) => new()
    {
        ["id"] = i.Id, ["cat"] = i.Cat, ["name"] = i.Name, ["rel"] = i.Rel, ["group"] = i.Group, ["bytes"] = i.Bytes, ["cut"] = i.SizeCut,
        ["reason"] = i.Reason, ["selected"] = i.Selected, ["disabled"] = i.Disabled, ["where"] = i.Where,
        ["newest"] = i.Newest == default ? null : i.Newest.ToLocalTime().ToString("yyyy-MM-dd"),
    };

    static JsonArray CareArr(IEnumerable<CareItem> list) => new(list.Select(i => (JsonNode)CareJson(i)).ToArray());

    static JsonNode CareOverview(CancellationToken c)
    {
        var o = CareWin.NewCare().Overview(new CareBudget(c));
        JsonObject E(CareEntry e) => new() { ["rel"] = e.Rel, ["bytes"] = e.Bytes, ["cut"] = e.Cut };
        var sizes = new JsonObject();
        foreach (var kv in o.Sizes) sizes[kv.Key] = E(kv.Value);
        return new JsonObject
        {
            ["total"] = o.DiskTotal, ["free"] = o.DiskFree, ["sizes"] = sizes, ["cut"] = o.Cut,
            ["folders"] = new JsonArray(o.Folders.Select(f => (JsonNode)E(f)).ToArray()),
            ["files"] = new JsonArray(o.Files.Select(f => (JsonNode)E(f)).ToArray()),
            ["oldCount"] = o.OldDownloads, ["oldBytes"] = o.OldDownloadsBytes,
        };
    }

    static JsonNode CareScan(string feature, CancellationToken c)
    {
        var care = CareWin.NewCare();
        var b = new CareBudget(c);
        var list = feature switch
        {
            "quick" => care.ScanQuick(b),
            "projects" => care.ScanProjects(b),
            "installers" => care.ScanInstallers(b),
            _ => throw new InvalidOperationException("unknown care feature"),
        };
        lock (careLists) careLists[feature] = list;
        return new JsonObject { ["feature"] = feature, ["items"] = CareArr(list), ["cut"] = b.Cut };
    }

    static JsonNode CareAct(string feature, JsonNode? arg, CancellationToken c)
    {
        var ids = arg?["ids"]?.AsArray().Select(x => x!.GetValue<string>()).ToHashSet() ?? new HashSet<string>();
        List<CareItem>? list;
        lock (careLists) if (!careLists.Remove(feature, out list)) throw new InvalidOperationException("care-rescan");
        var chosen = list.Where(i => ids.Contains(i.Id) && !i.Disabled).ToList();
        (int items, long kb, int failed) bs = feature == "apps" ? careBase : (0, 0L, 0);
        if (feature == "apps") careBase = (0, 0, 0);
        var r = CareWin.NewCare().Act(feature, chosen, c, bs.items, bs.kb, bs.failed);
        return new JsonObject
        {
            ["feature"] = feature, ["done"] = r.Done + bs.items, ["failed"] = r.Failed + bs.failed, ["changed"] = r.Changed,
            ["bytes"] = r.Bytes + bs.kb * 1024,
            ["cats"] = new JsonArray(r.Cats.Select(k => (JsonNode)new JsonObject { ["cat"] = k.Cat, ["done"] = k.Done, ["failed"] = k.Failed, ["bytes"] = k.Bytes }).ToArray()),
        };
    }

    static JsonNode CarePrograms() => new JsonArray(CareWin.Programs().Select(p => (JsonNode)new JsonObject
    {
        ["id"] = p.Id, ["kind"] = p.Kind, ["name"] = p.Name, ["publisher"] = p.Publisher, ["version"] = p.Version, ["bytes"] = p.Kb * 1024, ["canUninstall"] = p.CanUninstall,
    }).ToArray());

    /// <summary>Runs a just-for-you program's own uninstaller, then looks for what it left in AppData.</summary>
    static JsonNode CareUninstall(string id, CancellationToken c)
    {
        var (gone, app) = CareWin.Uninstall(id);
        var o = new JsonObject { ["gone"] = gone, ["name"] = app.Name, ["bytes"] = app.Kb * 1024 };
        if (!gone)
        {
            Care.History("apps", 0, 0, 1);
            o["items"] = new JsonArray();
            return o;
        }
        List<CareItem> list;
        // the uninstall itself happened: it is in History even when the leftovers can't be looked for (v0.9: Keep List
        // missing or unreadable, Cancel)
        try { list = CareWin.NewCare().ScanLeftovers(app.Name, app.Publisher, new CareBudget(c)); }
        catch { Care.History("apps", 1, app.Kb, 0); throw; }
        if (list.Count == 0) Care.History("apps", 1, app.Kb, 0);
        else
        {
            lock (careLists) careLists["apps"] = list;
            careBase = (1, app.Kb, 0);
        }
        o["items"] = CareArr(list);
        return o;
    }

    static JsonNode CareTune(JsonNode? arg)
    {
        var tasks = arg?["tasks"]?.AsArray().Select(x => x!.GetValue<string>()).ToList() ?? new List<string>();
        var res = new JsonArray();
        int done = 0, failed = 0;
        foreach (var t in tasks.Distinct())
        {
            bool ok = t switch { "explorer" => CareWin.RestartExplorer(), _ => false };
            if (ok) done++; else failed++;
            res.Add(new JsonObject { ["task"] = t, ["ok"] = ok });
        }
        Care.History("tune", done, 0, failed);
        AppInfo.Trace($"care: tune-ups {done} done, {failed} skipped");
        return new JsonObject { ["results"] = res, ["done"] = done, ["failed"] = failed };
    }
    // ---------- v0.10 Amnesia modes + Ask an AI ----------
    // The last preview: "Switch mode" commits exactly what the page showed (Modes.Commit refuses when the Keep List
    // changed since). The page never sends Keep List text, only the mode and the lines it ticked.
    ModePreview? modePending;
    // the last report, so "Save to Keep folder" saves what the page shows without counting everything again
    (string key, string text)? aiLast;

    static List<string> Strs(JsonNode? n) => n is JsonArray a
        ? a.Select(x => x is JsonValue v && v.TryGetValue<string>(out var s) ? s : null).Where(x => x != null).Select(x => x!).Take(AiReport.MaxList).ToList()
        : new List<string>();

    static JsonArray Arr(IEnumerable<string> l, int cap = 300) => new(l.Take(cap).Select(x => (JsonNode)JsonValue.Create(x)!).ToArray());

    static JsonNode ModeInfo()
    {
        var mode = Modes.Sync(); // what the Keep List really is (v0.10: read only, item 189)
        var presets = new JsonObject();
        foreach (var id in Modes.Ids) presets[id] = Modes.PresetLines(id) is { } l ? Arr(l) : null;
        return new JsonObject
        {
            ["mode"] = mode, ["blockOk"] = Modes.BlockOk(), ["presets"] = presets, ["own"] = Arr(Modes.Own(), 1000),
            ["lab"] = LabLock.Active, ["vaultAuto"] = Settings.Get("VAULT_AUTO") != "0",
        };
    }

    static JsonObject ModeJson(ModePreview p)
    {
        var set = new JsonObject();
        foreach (var kv in p.Settings) set[kv.Key] = kv.Value;
        return new JsonObject
        {
            ["asked"] = p.Asked, ["mode"] = p.Mode, ["from"] = p.From, ["problem"] = p.Problem, ["note"] = p.Note,
            ["added"] = Arr(p.Added), ["removed"] = Arr(p.Removed), ["removedIdle"] = Arr(p.RemovedIdle), ["outside"] = Arr(p.Outside, 1000),
            ["newlyWiped"] = Arr(p.NewlyWiped), ["newlyWipedCount"] = p.NewlyWiped.Count,
            ["newlyKept"] = Arr(p.NewlyKept), ["newlyKeptCount"] = p.NewlyKept.Count,
            ["wipeBefore"] = p.WipeBefore, ["wipeAfter"] = p.WipeAfter, ["wipesMore"] = p.WipesMore, ["settings"] = set,
        };
    }

    JsonNode ModePreviewJob(string mode, List<string> add, List<string> remove)
    {
        Modes.NewEngine = Cleaner.Rules; // the dry runs know the cloud folders, like the real cleanup
        modePending = null;
        var p = Modes.Preview(mode, add, remove);
        if (p.Problem == null) modePending = p;
        AppInfo.Trace($"mode preview: {p.From} -> {p.Mode}{(p.Problem != null ? " (" + p.Problem + ")" : "")}");
        return ModeJson(p);
    }

    JsonNode ModeCommit(string mode)
    {
        var p = modePending;
        if (p == null || p.Asked != mode) throw new InvalidOperationException("mode-rescan");
        modePending = null;
        if (!Modes.Commit(p)) throw new InvalidOperationException(p.Problem ?? "mode-write");
        return ModeInfo();
    }

    JsonNode AiReportJob(bool hideNames, string lang)
    {
        lang = lang == "id" ? "id" : "en";
        Modes.NewEngine = Cleaner.Rules;
        AiReport.CareProvider = () => CareWin.NewCare().Overview(new CareBudget());
        AiReport.NewAppsCount = () => Apps.On ? Apps.NewGroups().Count(g => g.Items.Any(a => a.Auto)) : 0;
        var r = AiReport.Build(hideNames, () => CareWin.Programs().Select(x => x.Name));
        var md = AiReport.Markdown(r);
        var full = AiReport.WithPrompt(lang, md);
        aiLast = ((hideNames ? "1" : "0") + lang, full);
        AppInfo.Trace($"ask an ai: report made (names {(hideNames ? "hidden" : "shown")})");
        return new JsonObject { ["markdown"] = md, ["prompt"] = AiReport.Prompt(lang), ["full"] = full, ["json"] = r };
    }

    JsonNode AiSaveJob(bool hideNames, string lang)
    {
        lang = lang == "id" ? "id" : "en";
        var key = (hideNames ? "1" : "0") + lang;
        var text = aiLast is { } last && last.key == key ? last.text : null;
        if (text == null) { AiReportJob(hideNames, lang); text = aiLast!.Value.text; }
        // the Keep lock: Keep is opened for the moment it takes
        var path = KeepLock.With(() => AiReport.Save(text));
        return new JsonObject { ["path"] = path };
    }
}
