// Turn On / Turn Off / Uninstall. Turning on copies Amnesia to %LOCALAPPDATA%\Programs\Amnesia (a folder the cleanup
// never touches; a copy in Downloads would be wiped with everything else) and starts it at every sign in.
// v0.4: Setup.exe (Inno Setup) installs to the same folder, so Turn On then needs no copy.
// v0.8: "Open at login" is its own switch (on unless you switch it off): Amnesia starts at sign in also while it is off,
// so its tray icon is there and it can tell you it is off. Off = nothing is cleaned, as before.
using Microsoft.Win32;

namespace Amnesia;

static class Setup
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    // Windows waits a while before it starts the apps in Run. 0 = start them right away, so the sign in check
    // runs within seconds instead of minutes. Only for this user; put back at Turn Off.
    const string SerializeKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize";
    // Task Manager → Startup apps writes here: first byte even = on, odd = switched off
    const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

    /// <summary>v0.8: start at sign in (also while off). OPEN_AT_LOGIN=0 switches it off.</summary>
    public static bool OpenAtLogin => Settings.Get("OPEN_AT_LOGIN") != "0";

    /// <summary>v0.8 (MED-WIN-02): Amnesia was switched off in Task Manager → Startup apps (it then never starts at sign in).</summary>
    public static bool StartupDisabled
    {
        get
        {
            try
            {
                using var run = Registry.CurrentUser.OpenSubKey(RunKey);
                if (run?.GetValue("Amnesia") == null) return false;
                using var k = Registry.CurrentUser.OpenSubKey(ApprovedKey);
                return k?.GetValue("Amnesia") is byte[] b && b.Length > 0 && (b[0] & 1) == 1;
            }
            catch { return false; }
        }
    }

    /// <summary>"Switch it back on" (the button next to the warning): the same as switching it on in Task Manager.</summary>
    public static void EnableStartup()
    {
        using (var k = Registry.CurrentUser.CreateSubKey(ApprovedKey)) k.SetValue("Amnesia", new byte[] { 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, RegistryValueKind.Binary);
        SyncStartup();
        AppInfo.Trace("startup switched back on");
    }

    /// <summary>Writes or removes the "start at sign in" entry: there while Amnesia is on or "Open at login" is on.</summary>
    public static void SyncStartup()
    {
        using var k = Registry.CurrentUser.CreateSubKey(RunKey);
        if (Settings.Enabled || OpenAtLogin)
        {
            var want = $"\"{InstalledExe}\" --login";
            if (k.GetValue("Amnesia") as string != want) k.SetValue("Amnesia", want);
        }
        else k.DeleteValue("Amnesia", throwOnMissingValue: false);
    }

    static void RemoveStartup()
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        k?.DeleteValue("Amnesia", throwOnMissingValue: false);
    }

    public static string InstallDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Amnesia");
    public static string InstalledExe => Path.Combine(InstallDir, "Amnesia.exe");
    public static bool RunningInstalled =>
        string.Equals(Path.GetFullPath(AppInfo.BaseDir).TrimEnd('\\'), Path.GetFullPath(InstallDir).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    /// <summary>Copies Amnesia.exe + ui\ + scripts\ to the install folder. Returns true when a restart from there is needed.</summary>
    public static bool TurnOn()
    {
        bool restart = false;
        if (!RunningInstalled)
        {
            Copy(AppInfo.BaseDir, InstallDir);
            restart = true;
        }
        Settings.Set("APP_PATH", InstalledExe);
        using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
            k.SetValue("Amnesia", $"\"{InstalledExe}\" --login");
        using (var k = Registry.CurrentUser.CreateSubKey(SerializeKey))
        {
            if (k.GetValue("StartupDelayInMSec") == null) { k.SetValue("StartupDelayInMSec", 0, RegistryValueKind.DWord); Settings.Set("STARTUP_DELAY_SET", "1"); }
        }
        Settings.Set("ENABLED", "1");
        // v0.4: what is installed now is the starting point for "Remove new apps"
        if (!Apps.HasBaseline) try { Apps.TakeBaseline(); } catch (Exception e) { AppInfo.Trace($"app list failed: {e.GetType().Name}"); }
        AppInfo.Trace("turned on");
        return restart;
    }

    /// <summary>Turn Off. leaveStartup: false for the uninstaller (nothing may start at sign in afterwards).</summary>
    public static void TurnOff(bool leaveStartup = true)
    {
        Settings.Set("ENABLED", "0");
        if (leaveStartup && RunningInstalled) SyncStartup(); else RemoveStartup();
        try { File.Delete(Settings.PauseFile); } catch { }
        if (Settings.Get("STARTUP_DELAY_SET") == "1")
        {
            using var s = Registry.CurrentUser.OpenSubKey(SerializeKey, writable: true);
            s?.DeleteValue("StartupDelayInMSec", throwOnMissingValue: false);
            Settings.Set("STARTUP_DELAY_SET", "0");
        }
        AppInfo.Trace("turned off");
    }

    /// <summary>Pause = the next sign out and sign in are skipped (pause_once). v0.8: written to trace.log and the History
    /// as a pause (it was easy to mix up with "turned off"), and checked after writing.</summary>
    public static void Pause(bool on)
    {
        if (on) { Directory.CreateDirectory(AppInfo.Home); File.WriteAllText(Settings.PauseFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm")); }
        else try { File.Delete(Settings.PauseFile); } catch { }
        if (Settings.Paused != on) throw new InvalidOperationException("pause-not-saved");
        AppInfo.Trace(on ? "paused for one session (on stays on)" : "pause cancelled");
        Core.Home.History(on ? "pause" : "resume", "1");
    }

    /// <summary>v0.4 Uninstall button. Turns off first (so nothing is wiped any more), removes the Keep shortcut and pin,
    /// then removes the app. all = also %USERPROFILE%\.amnesia (settings, Keep List, VAULT). Your Keep folder always stays.
    /// v0.8 (HIGH-WIN-04): a locked Keep needs its password here and is opened first. Without it nothing happens: the
    /// app's uninstaller runs silently, so there would be no other moment to ask. (Uninstalling from Windows Settings asks
    /// in the Setup uninstaller itself: Program --keep-check.)</summary>
    public static void Uninstall(bool all, string keepPassword = "")
    {
        if (KeepLock.On)
        {
            if (keepPassword.Length == 0) throw new InvalidOperationException("keeplock-uninstall");
            if (!Amnesia.Core.Pin.Verify(keepPassword, Settings.Get("KEEP_LOCK_PW"))) throw new InvalidOperationException("keeplock-wrong");
            KeepLock.TurnOff(keepPassword);
        }
        TurnOff(leaveStartup: false);
        Settings.Set("KEEP_SHORTCUT", "0"); Settings.Set("KEEP_PIN", "0");
        KeepLinks.SyncNow();
        KeepLinks.RemoveIcon();
        AppInfo.Trace($"uninstall (everything: {all})");
        var webData = Path.GetDirectoryName(AppInfo.WebViewData)!;
        var uninstaller = Path.Combine(InstallDir, "unins000.exe");
        if (all) Amnesia.Core.CleanEngine.Delete(AppInfo.Home);
        if (File.Exists(uninstaller))
        {
            // the Setup.exe uninstaller removes the app folder and the Start menu entry; it closes Amnesia itself
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uninstaller, "/SILENT") { UseShellExecute = true });
            return;
        }
        // portable copy: remove the install folder and WebView2's data after Amnesia has closed
        var dirs = new List<string>();
        if (Directory.Exists(InstallDir)) dirs.Add(InstallDir);
        dirs.Add(webData);
        var cmd = "ping 127.0.0.1 -n 4 >nul & " + string.Join(" & ", dirs.Select(d => $"rmdir /s /q \"{d}\""));
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c {cmd}") { CreateNoWindow = true, UseShellExecute = false });
    }

    static void Copy(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var f in new[] { "Amnesia.exe" })
        {
            File.Copy(Path.Combine(from, f), Path.Combine(to, f), overwrite: true);
        }
        foreach (var d in new[] { "ui", "scripts" })
        {
            var src = Path.Combine(from, d);
            if (!Directory.Exists(src)) continue;
            foreach (var f in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                var dest = Path.Combine(to, d, Path.GetRelativePath(src, f));
                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                File.Copy(f, dest, overwrite: true);
            }
        }
        // v0.4: the old sign out helper scripts are gone (cleanup runs inside Amnesia.exe now)
        foreach (var old in new[] { "clean.ps1", "standby.ps1" }) try { File.Delete(Path.Combine(to, "scripts", old)); } catch { }
        Unblock(to);
    }

    /// <summary>The copy keeps Windows' "downloaded from the internet" mark, so Windows asked "Run / Cancel" at every
    /// sign in. You already chose to run it, so the mark is removed from the installed copy (also fixes older installs).</summary>
    public static void Unblock(string dir)
    {
        try
        {
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                try { File.Delete(f + ":Zone.Identifier"); } catch { }
        }
        catch { }
    }
}
