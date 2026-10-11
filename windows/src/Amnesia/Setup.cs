// Turn On / Turn Off / Uninstall. Turning on copies Amnesia to %LOCALAPPDATA%\Programs\Amnesia (a folder the cleanup
// never touches; a copy in Downloads would be wiped with everything else) and starts it at every sign in.
// v0.4: Setup.exe (Inno Setup) installs to the same folder, so Turn On then needs no copy.
using Microsoft.Win32;

namespace Amnesia;

static class Setup
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    // Windows waits a while before it starts the apps in Run. 0 = start them right away, so the sign in check
    // runs within seconds instead of minutes. Only for this user; put back at Turn Off.
    const string SerializeKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize";

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

    public static void TurnOff()
    {
        Settings.Set("ENABLED", "0");
        using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        k?.DeleteValue("Amnesia", throwOnMissingValue: false);
        try { File.Delete(Settings.PauseFile); } catch { }
        if (Settings.Get("STARTUP_DELAY_SET") == "1")
        {
            using var s = Registry.CurrentUser.OpenSubKey(SerializeKey, writable: true);
            s?.DeleteValue("StartupDelayInMSec", throwOnMissingValue: false);
            Settings.Set("STARTUP_DELAY_SET", "0");
        }
        AppInfo.Trace("turned off");
    }

    public static void Pause(bool on)
    {
        if (on) { Directory.CreateDirectory(AppInfo.Home); File.WriteAllText(Settings.PauseFile, ""); }
        else try { File.Delete(Settings.PauseFile); } catch { }
    }

    /// <summary>v0.4 Uninstall button. Turns off first (so nothing is wiped any more), removes the Keep shortcut and pin,
    /// then removes the app. all = also %USERPROFILE%\.amnesia (settings, Keep List, VAULT). Your Keep folder always stays.</summary>
    public static void Uninstall(bool all)
    {
        TurnOff();
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
