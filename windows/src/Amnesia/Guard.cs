// v0.4 quick exits (Settings → Advanced): panic hotkey, USB key, sign out when idle. All three end the same way:
// lock the screen right away, clean up, then sign out without waiting for other apps (unsaved work is lost on purpose).
using System.Runtime.InteropServices;
using Amnesia.Core;

namespace Amnesia;

static class Guard
{
    const uint EWX_LOGOFF = 0x0, EWX_SHUTDOWN = 0x1, EWX_FORCE = 0x4, EWX_POWEROFF = 0x8;
    [DllImport("user32.dll", SetLastError = true)] static extern bool ExitWindowsEx(uint flags, uint reason);
    [DllImport("user32.dll")] static extern bool LockWorkStation();
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool GetVolumeInformation(string root, IntPtr name, int nameSize, out uint serial, out uint maxLen, out uint flags, IntPtr fs, int fsSize);
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    static int busy;
    /// <summary>True right after a panic/idle cleanup, so the sign out that follows does not clean twice.</summary>
    public static bool JustCleaned;

    /// <summary>Normal sign out (the "Review and sign out" button). Windows asks every app; Amnesia cleans in WM_ENDSESSION.</summary>
    public static void SignOut() => ExitWindowsEx(EWX_LOGOFF, 0);

    // v0.5 (idea from Tails: pulling the USB stick shuts the computer down at once): shutting down needs this privilege
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValue(string? system, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TOKEN_PRIVILEGES state, int len, IntPtr prev, IntPtr retLen);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [StructLayout(LayoutKind.Sequential, Pack = 4)] struct TOKEN_PRIVILEGES { public int Count; public long Luid; public int Attributes; }
    static void ShutdownPrivilege()
    {
        if (!OpenProcessToken(GetCurrentProcess(), 0x20 | 0x8, out var token)) return; // ADJUST_PRIVILEGES | QUERY
        if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out var luid)) return;
        var tp = new TOKEN_PRIVILEGES { Count = 1, Luid = luid, Attributes = 0x2 };
        AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }

    [DllImport("wtsapi32.dll", SetLastError = true)] static extern bool WTSLogoffSession(IntPtr server, int session, bool wait);

    /// <summary>Panic / USB key / idle: lock now, (snapshot,) clean, sign out by force. shutdown: turn the PC off instead
    /// (Settings → Advanced → "When the USB key is pulled out").
    /// v0.8 (HIGH-WIN-01): a panic always cleans, also while Amnesia is paused for one session (the pause is cancelled).
    /// Faster: no sizes counted, Explorer's caches go while it is closed, and the sign out is asked again if Windows
    /// has not ended the session after 8 seconds (signing in during that time took you back into the old session).</summary>
    public static void QuickExit(string why, bool snapshot = false, bool shutdown = false)
    {
        if (Interlocked.Exchange(ref busy, 1) == 1) return;
        AppInfo.Trace($"quick exit: {why}");
        Core.Home.History("quick", why);
        LockWorkStation();
        var t = new Thread(() =>
        {
            var w = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                // browsers keep their profile open; close them so their files can move
                foreach (var name in new[] { "msedge", "chrome", "firefox", "brave", "opera", "vivaldi" })
                    foreach (var p in System.Diagnostics.Process.GetProcessesByName(name)) try { p.Kill(); } catch { }
                if (snapshot && Vault.Exists && Settings.Get("VAULT_AUTO") != "0")
                    try { Vault.Snapshot(changedOnly: true, budget: TimeSpan.FromSeconds(45)); } catch (Exception e) { AppInfo.Trace($"auto snapshot failed: {e.GetType().Name}"); }
                if (Settings.Enabled)
                {
                    if (Settings.Paused) { try { File.Delete(Settings.PauseFile); } catch { } AppInfo.Trace("quick exit cancels the pause"); }
                    int caches = Cleaner.StopExplorerAndWipeCaches();
                    var r = Cleaner.Run("logout");
                    JustCleaned = r.Skipped == null;
                    AppInfo.Trace($"quick exit clean: {r.Skipped ?? r.Count.ToString()} (+{caches} Explorer caches) in {w.Elapsed.TotalSeconds:0.0} s");
                }
            }
            catch (Exception e) { AppInfo.Trace($"quick exit clean failed: {e.GetType().Name}"); }
            if (shutdown) { ShutdownPrivilege(); if (ExitWindowsEx(EWX_SHUTDOWN | EWX_POWEROFF | EWX_FORCE, 0)) return; }
            bool ok = ExitWindowsEx(EWX_LOGOFF | EWX_FORCE, 0);
            AppInfo.Trace($"sign out asked after {w.Elapsed.TotalSeconds:0.0} s ({(ok ? "ok" : "error " + Marshal.GetLastWin32Error())})");
            // still here 8 s later: ask once more, the other way
            Thread.Sleep(8000);
            AppInfo.Trace("still signed in after 8 s: asking again");
            try { WTSLogoffSession(IntPtr.Zero, -1 /* this session */, false); } catch { }
            ExitWindowsEx(EWX_LOGOFF | EWX_FORCE, 0);
        }) { IsBackground = false };
        t.Start();
    }

    /// <summary>Seconds since the last key press or mouse move (any app).</summary>
    public static double IdleSeconds()
    {
        var i = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!GetLastInputInfo(ref i)) return 0;
        return unchecked((uint)Environment.TickCount - i.dwTime) / 1000.0;
    }

    // ---------- panic hotkey ----------
    public static readonly (string id, uint mods, Keys key)[] Hotkeys =
    {
        ("ctrl+alt+shift+x", 0x2 | 0x1 | 0x4, Keys.X),
        ("ctrl+alt+shift+q", 0x2 | 0x1 | 0x4, Keys.Q),
        ("ctrl+alt+shift+f12", 0x2 | 0x1 | 0x4, Keys.F12),
    };

    // ---------- USB key ----------
    /// <summary>Drives you can pick as a USB key: removable drives that are plugged in now.</summary>
    public static List<(string root, string label, string serial)> UsbDrives()
    {
        var list = new List<(string, string, string)>();
        foreach (var d in DriveInfo.GetDrives())
        {
            try
            {
                if (d.DriveType != DriveType.Removable || !d.IsReady) continue;
                var s = Serial(d.RootDirectory.FullName);
                if (s != null) list.Add((d.RootDirectory.FullName, string.IsNullOrEmpty(d.VolumeLabel) ? d.Name : d.VolumeLabel, s));
            }
            catch { }
        }
        return list;
    }

    static string? Serial(string root) =>
        GetVolumeInformation(root, IntPtr.Zero, 0, out var serial, out _, out _, IntPtr.Zero, 0) ? serial.ToString("X8") : null;

    /// <summary>Is the chosen USB key plugged in?</summary>
    public static bool UsbKeyPresent()
    {
        var want = Settings.Get("USB_KEY");
        if (string.IsNullOrEmpty(want)) return false;
        foreach (var d in DriveInfo.GetDrives())
            try { if (d.IsReady && d.DriveType is DriveType.Removable or DriveType.Fixed && Serial(d.RootDirectory.FullName) == want) return true; } catch { }
        return false;
    }
}

/// <summary>"Signing out in 60 s" before an idle sign out. Any key press or mouse move (or Cancel) stops it.</summary>
sealed class IdleCountdown : Form
{
    readonly System.Windows.Forms.Timer timer = new() { Interval = 500 };
    readonly Label text = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI", 11f) };
    readonly DateTime end = DateTime.Now.AddSeconds(60);
    readonly double idleAtStart = Guard.IdleSeconds();

    public IdleCountdown()
    {
        Text = "Amnesia";
        Icon = AppInfo.Icon;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        TopMost = true;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(420, 150);
        var cancel = new Button { Text = AppInfo.Id ? "Batal" : "Cancel", Dock = DockStyle.Bottom, Height = 40 };
        cancel.Click += (_, _) => Close();
        Controls.Add(text);
        Controls.Add(cancel);
        timer.Tick += (_, _) => Tick();
        Shown += (_, _) => { timer.Start(); Tick(); };
        FormClosed += (_, _) => timer.Dispose();
    }

    void Tick()
    {
        if (Guard.IdleSeconds() < idleAtStart - 1) { Close(); return; } // you are back
        int left = (int)Math.Ceiling((end - DateTime.Now).TotalSeconds);
        if (left <= 0) { timer.Stop(); Close(); Guard.QuickExit("idle", snapshot: true); return; }
        text.Text = AppInfo.Id
            ? $"Tidak ada aktivitas. Sign out otomatis dalam {left} detik.\nGerakkan mouse atau tekan tombol untuk batal."
            : $"No activity. Signing out in {left} seconds.\nMove the mouse or press a key to cancel.";
    }
}
