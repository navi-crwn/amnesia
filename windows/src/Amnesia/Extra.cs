// v0.5 extras learned from similar programs (Settings → Advanced):
//   Extra cleaning list   Winapp2.ini (community list, also used by BleachBit): downloaded on request, never shipped
//   Throwaway Windows     Windows Sandbox (idea from Sandboxie: run something in a box that is thrown away when closed)
//   Wipe free space       BleachBit's "free disk space" idea, done with Windows' own cipher.exe /w
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

static class Extra
{
    // ---------- Extra cleaning list (Winapp2) ----------
    static W2Plan? cached;
    static DateTime cachedAt;
    static List<W2Entry>? entries;
    static DateTime entriesTime;

    static string? Env(string name) => name.ToLowerInvariant() switch
    {
        "localappdata" => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "appdata" => Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "userprofile" => Core.Home.User,
        "programfiles" => Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        "programdata" or "commonappdata" => Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "windir" => Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        _ => null, // anything else is skipped
    };

    static bool RegExists(string path)
    {
        var p = path.Split('|')[0].TrimEnd('\\');
        int i = p.IndexOf('\\');
        if (i < 0) return false;
        var root = p[..i].ToUpperInvariant() switch
        {
            "HKCU" => Registry.CurrentUser, "HKLM" => Registry.LocalMachine, "HKCR" => Registry.ClassesRoot, _ => null,
        };
        if (root == null) return false;
        using var k = root.OpenSubKey(p[(i + 1)..]);
        return k != null;
    }

    static List<W2Entry>? Entries()
    {
        if (!Winapp2.On || !Winapp2.Exists) return null;
        var t = File.GetLastWriteTimeUtc(Winapp2.FilePath);
        if (entries == null || t != entriesTime) { entries = Winapp2.Parse(File.ReadAllText(Winapp2.FilePath)); entriesTime = t; }
        return entries;
    }

    /// <summary>What the list would clean right now (null when the list is off or not downloaded). One cleanup run
    /// asks twice (files, then registry), so the answer is kept for a few seconds.</summary>
    public static W2Plan? Plan(Func<string, bool>? ok = null)
    {
        try
        {
            var e = Entries();
            if (e == null) return null;
            if (cached != null && (DateTime.Now - cachedAt).TotalSeconds < 20) return cached;
            cached = Winapp2.Plan(e, Env, RegExists, ok ?? new CleanEngine().ExtraOk);
            cachedAt = DateTime.Now;
            return cached;
        }
        catch (Exception x) { AppInfo.Trace($"extra list failed: {x.GetType().Name}"); return null; }
    }

    public static void ClearRegistry(W2Plan plan)
    {
        foreach (var (key, value) in plan.Reg)
        {
            if (!Winapp2.RegAllowed(key)) continue; // checked again, right before deleting
            var sub = key[5..]; // after "HKCU\"
            try
            {
                if (value == null) Registry.CurrentUser.DeleteSubKeyTree(sub, false);
                else { using var k = Registry.CurrentUser.OpenSubKey(sub, writable: true); k?.DeleteValue(value, false); }
            }
            catch { }
        }
        cached = null;
    }

    public static (bool exists, string? version, int entries, string? date) ListInfo()
    {
        if (!Winapp2.Exists) return (false, null, 0, null);
        int n = 0;
        try { n = Entries()?.Count ?? Winapp2.Parse(File.ReadAllText(Winapp2.FilePath)).Count; } catch { }
        return (true, Winapp2.Version(), n, File.GetLastWriteTime(Winapp2.FilePath).ToString("yyyy-MM-dd"));
    }

    /// <summary>Downloads the newest Winapp2.ini from GitHub (only when you press the button).</summary>
    public static async Task DownloadListAsync()
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"Amnesia-Windows/{AppInfo.Version}");
        var text = await http.GetStringAsync(Winapp2.Url);
        if (!Winapp2.LooksValid(text)) throw new InvalidOperationException("list-bad");
        Directory.CreateDirectory(Core.Home.Dir);
        var tmp = Winapp2.FilePath + ".new";
        await File.WriteAllTextAsync(tmp, text);
        File.Move(tmp, Winapp2.FilePath, overwrite: true);
        entries = null; cached = null;
        AppInfo.Trace("extra list downloaded");
    }

    // ---------- Throwaway Windows (Windows Sandbox) ----------
    static string SandboxExe => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsSandbox.exe");
    public static bool SandboxReady => File.Exists(SandboxExe);

    /// <summary>Starts Windows Sandbox: a clean Windows in a window, everything in it is gone when you close it.
    /// shareKeep: your Keep folder is visible inside, read only (nothing in the sandbox can change it).</summary>
    public static void OpenSandbox(bool shareKeep, bool network)
    {
        if (!SandboxReady) throw new InvalidOperationException("sandbox-missing");
        var cfg = new System.Text.StringBuilder("<Configuration>");
        cfg.Append($"<Networking>{(network ? "Default" : "Disable")}</Networking>");
        cfg.Append("<ClipboardRedirection>Enable</ClipboardRedirection><PrinterRedirection>Disable</PrinterRedirection><AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput>");
        if (shareKeep && Directory.Exists(Settings.KeepDir))
            cfg.Append($"<MappedFolders><MappedFolder><HostFolder>{System.Security.SecurityElement.Escape(Settings.KeepDir)}</HostFolder><ReadOnly>true</ReadOnly></MappedFolder></MappedFolders>");
        cfg.Append("</Configuration>");
        var file = Path.Combine(Path.GetTempPath(), "Amnesia-sandbox.wsb"); // Temp is wiped at sign out anyway
        File.WriteAllText(file, cfg.ToString());
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(file) { UseShellExecute = true });
    }

    // ---------- Wipe free space ----------
    /// <summary>Opens a window that runs Windows' own "cipher /w" on the drive of your user folder: it fills the free
    /// space with zeros, then random data, so deleted files cannot be brought back with recovery tools. Slow (can take
    /// an hour), and on an SSD Windows already does most of this by itself (TRIM).</summary>
    public static void WipeFreeSpace()
    {
        var drive = Path.GetPathRoot(Core.Home.User) ?? "C:\\";
        var cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
        var psi = new System.Diagnostics.ProcessStartInfo(cmd) { UseShellExecute = true };
        // /k: the window stays open so you can see when it is done
        psi.Arguments = $"/k title Amnesia: wipe free space && cipher.exe /w:{drive.TrimEnd('\\')}\\";
        System.Diagnostics.Process.Start(psi);
        Core.Home.History("wipe", drive);
    }
}
