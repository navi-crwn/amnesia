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
        "collectLog", "updateCheck", "signOut", "panicNow", "cancel", "labUnlock", "keepLockNow",
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
                "turnOff" => await Do(Setup.TurnOff),
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
                // Vault
                "vaultInfo" => await Task.Run(VaultInfo),
                "vaultCreate" => await Task.Run(() => { Vault.Create(S("password"), S("panic"), B("panicFull")); return VaultInfo(); }),
                "vaultChoose" => await Do(() => Vault.Choose(S("name"), B("on")), VaultInfo),
                "vaultAddFolder" => await VaultAddFolder(),
                "vaultRemoveFolder" => await Do(() => Vault.RemoveFolder(S("name")), VaultInfo),
                "vaultSnapshot" => await Job("vault", (p, c) => { Vault.Snapshot(null, false, null, p, c); return VaultInfo(); }),
                "vaultRestore" => await Job("vault", (p, c) => { var n = Vault.Restore(S("password"), null, p, c, B("previous")); var i = VaultInfo(); i["restored"] = new JsonArray(n.Select(x => (JsonNode)x!).ToArray()); var pr = new JsonObject(); foreach (var kv in Vault.LastProblems) pr[kv.Key] = kv.Value; i["problems"] = pr; return i; }),
                "vaultDelete" => await Do(() => Vault.DeleteSnapshots(S("name") is { Length: > 0 } n ? new[] { n } : null), VaultInfo),
                "vaultPassword" => await Task.Run(() => { Vault.ChangePassword(S("old"), S("new")); return VaultInfo(); }),
                "vaultPanic" => await Task.Run(() => { Vault.ChangePanicWord(S("password"), S("word"), B("full")); return VaultInfo(); }),
                // Backup
                "backupInfo" => await Task.Run(BackupInfo),
                "backupFolder" => await BackupFolder(),
                "backupNow" => await Job("backup", (p, c) => { var w = KeepLock.With(() => Backup.Create(p, c)); var i = BackupInfo(); i["where"] = w; return i; }),
                "backupTest" => await Task.Run(() => (JsonNode)new JsonObject { ["error"] = Ssh.Test() }),
                "backupRestore" => await BackupRestore(S("password"), S("file")),
                "backupPick" => await BackupPick(),
                // Advanced
                "advInfo" => await Task.Run(AdvInfo),
                "appsKeep" => await Do(() => Apps.Keep(S("id")), AdvInfo),
                "appsKeepAll" => await Do(Apps.TakeBaseline, AdvInfo),
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
                "uninstall" => await Do(() => { Setup.Uninstall(B("all")); tray.Invoke(() => Task.Delay(1500).ContinueWith(_ => tray.Invoke(tray.Quit))); }),
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
        };
    }

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
            ["items"] = new JsonArray(r.Items.Select(i => (JsonNode)new JsonObject { ["path"] = i.Path, ["kind"] = i.Kind, ["size"] = sizes.GetValueOrDefault(i.Path, -1) }).ToArray()),
            ["kept"] = new JsonArray(r.Kept.Select(k => (JsonNode)k!).ToArray()),
        };
        if (Apps.On)
            o["apps"] = await Task.Run(() => new JsonArray(Apps.New().Where(a => a.Auto).Select(a => (JsonNode)new JsonObject { ["name"] = a.Name, ["kind"] = a.Kind }).ToArray()));
        return o;
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
        var list = new JsonArray(paths.Select(p => (JsonNode)new JsonObject { ["path"] = p, ["exists"] = File.Exists(Core.Home.Full(p)) || Directory.Exists(Core.Home.Full(p)) || p.Contains('*') }).ToArray());
        // suggestions: app data folders found on this PC that are not on the list yet
        var sugg = new JsonArray();
        var skip = new[] { "Microsoft", "Packages", "Temp", "Amnesia", "Programs", "Comms", "ConnectedDevicesPlatform", "CrashDumps", "D3DSCache", "PeerDistRepub", "Publishers", "VirtualStore", "PlaceholderTileLogoFolder", "OneDrive", "IsolatedStorage", "CoreAIPlatform.00", "Intel", "NVIDIA", "AMD", "Mozilla" };
        foreach (var root in new[] { "AppData/Roaming", "AppData/Local" })
        {
            var dir = Core.Home.Full(root);
            if (!Directory.Exists(dir)) continue;
            foreach (var d in new DirectoryInfo(dir).EnumerateDirectories().Where(d => !d.Attributes.HasFlag(FileAttributes.ReparsePoint)).OrderBy(d => d.Name))
            {
                var rel = $"{root}/{d.Name}";
                if (skip.Contains(d.Name, StringComparer.OrdinalIgnoreCase) || paths.Any(p => Wild.Like(rel, p) || Wild.Like(rel, p + "/*"))) continue;
                sugg.Add(new JsonObject { ["name"] = d.Name, ["path"] = rel });
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
        return new JsonObject { ["paths"] = list, ["suggestions"] = sugg, ["keepDir"] = Settings.KeepDir, ["home"] = Core.Home.User };
    }

    async Task<JsonNode> KeepAdd(string path)
    {
        if (path.Length == 0) path = await PickFolder() ?? "";
        if (path.Length == 0) return await Task.Run(KeepInfo);
        if (KeepList.Add(path) == null && !KeepList.Paths().Contains(KeepList.Norm(path), StringComparer.OrdinalIgnoreCase)) throw new InvalidOperationException("outside-home");
        return await Task.Run(KeepInfo);
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
            if (p.StartsWith(home, StringComparison.OrdinalIgnoreCase) && !p.StartsWith(Settings.KeepDir, StringComparison.OrdinalIgnoreCase)
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
            ["apps"] = Apps.On ? new JsonArray(Apps.New().Select(a => (JsonNode)new JsonObject { ["id"] = a.Id, ["name"] = a.Name, ["kind"] = a.Kind, ["auto"] = a.Auto, ["canUninstall"] = a.Kind == "machine" && a.Uninstall != null }).ToArray()) : new JsonArray(),
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
            ["canInstall"] = r?.Setup != null && r.Sums != null && Updater.FromSetup,
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
}
