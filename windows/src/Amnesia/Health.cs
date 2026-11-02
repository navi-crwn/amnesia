// v0.8 "Health check" (home page): one look at whether Amnesia can do its job right now, in plain words.
// Each line is {id, state: ok | warn | bad | info, data}; the page has the text. Only reads, never fixes by itself.
using System.Text.Json.Nodes;
using Amnesia.Core;

namespace Amnesia;

static class Health
{
    public static JsonArray Check()
    {
        var list = new JsonArray();
        void Add(string id, string state, string? data = null) => list.Add(new JsonObject { ["id"] = id, ["state"] = state, ["data"] = data });
        bool on = Settings.Enabled;
        Add("on", !on ? "bad" : Settings.Paused ? "warn" : "ok");
        if (Setup.RunningInstalled) Add("startup", on && Setup.StartupDisabled ? "bad" : "ok");
        else Add("startup", "info");
        // the last cleanup, from history.log
        var last = LastOf("clean");
        Add("lastClean", last == null ? (on ? "warn" : "info") : "ok", last);
        // things Windows held open: tried again at the next sign in
        int left = 0;
        try
        {
            if (Directory.Exists(Core.Home.Trash))
                left = new DirectoryInfo(Core.Home.Trash).EnumerateDirectories().Count(d => !d.Name.EndsWith("-apps", StringComparison.OrdinalIgnoreCase) && DateTime.Now - d.CreationTime > TimeSpan.FromHours(1));
        }
        catch { }
        Add("trash", left > 0 ? "warn" : "ok", left.ToString());
        var blocked = Settings.Get("LAST_BLOCKED");
        Add("blocked", string.IsNullOrEmpty(blocked) ? "ok" : "warn", blocked);
        // cloud folders that stay as they are
        var clouds = new List<string>();
        try { clouds = Cleaner.CloudRoots().Select(p => Path.GetFileName(p.TrimEnd('\\'))).Where(n => n.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList(); } catch { }
        Add("cloud", "info", string.Join(", ", clouds));
        Add("vm", Settings.Get("KEEP_VM") == "0" ? "warn" : "ok");
        // v0.8.1: Keep still locked by an old version while the Keep lock is off
        bool stale = false;
        try { stale = KeepLock.Stale; } catch { }
        Add("keepLock", stale ? "bad" : KeepLock.On ? "ok" : "info");
        // vault: when was the newest snapshot
        if (!Vault.Exists) Add("vault", "info");
        else
        {
            var m = Vault.Manifest();
            var newest = m.Select(kv => kv.Value?["time"]?.GetValue<string>()).Where(t => t != null).OrderByDescending(t => t).FirstOrDefault();
            Add("vault", newest == null ? "warn" : "ok", newest);
        }
        // backup
        var every = Settings.Get("BACKUP_EVERY");
        var bl = Settings.Get("BACKUP_LAST");
        if (!DateTime.TryParse(bl, out var bt)) Add("backup", Vault.Exists ? "warn" : "info");
        else
        {
            var max = every == "day" ? TimeSpan.FromDays(3) : TimeSpan.FromDays(14);
            Add("backup", DateTime.Now - bt > max ? "warn" : "ok", bl);
        }
        Add("hotkey", string.IsNullOrEmpty(Settings.Get("PANIC_HOTKEY")) ? "info" : "ok", Settings.Get("PANIC_HOTKEY"));
        Add("updates", Updater.Signed ? "ok" : "info");
        // v0.9: free space on the drive of the user folder (warn under 10% or 15 GB), memory and battery. Can't tell = info.
        try
        {
            var d = new DriveInfo(Path.GetPathRoot(Core.Home.User)!);
            long free = d.AvailableFreeSpace, total = d.TotalSize;
            Add("disk", total > 0 && (free < total / 10 || free < 15L << 30) ? "warn" : "ok", $"{free} {total}");
        }
        catch { Add("disk", "info"); }
        var mem = CareWin.Memory();
        if (mem is { } mm) Add("memory", mm.used > 90 ? "warn" : "ok", mm.used.ToString());
        else Add("memory", "info");
        try
        {
            if (CareWin.Battery() is { } bat) Add("battery", "info", $"{bat.percent} {(bat.charging ? 1 : 0)}");
        }
        catch { Add("battery", "info"); }
        return list;
    }

    static string? LastOf(string kind)
    {
        var f = Path.Combine(AppInfo.Home, "history.log");
        if (!File.Exists(f)) return null;
        try
        {
            foreach (var l in File.ReadLines(f).Reverse())
            {
                var p = l.Split('\t');
                if (p.Length >= 2 && p[1] == kind) return p[0];
            }
        }
        catch { }
        return null;
    }
}
