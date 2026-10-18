// Catches sign out / restart / shut down. Windows asks every window "may I end the session?"; we say yes, ask Windows
// to wait a moment (it shows "Amnesia: cleaning up..."), and move everything to .amnesia-trash. Moving is instant;
// the real deleting happens after the next sign in. If Windows does not wait, the sign in check catches up.
// v0.4: the cleanup runs right here inside Amnesia.exe (no PowerShell helper any more), after the automatic vault
// snapshot. This hidden window also receives the panic hotkey and "a drive was removed" (USB key).
// v0.6: sign out / shut down from Start often skipped the cleanup (the sign in check caught up later). Windows only
// waits for apps that have a visible window; this one was fully hidden, so Windows ended Amnesia after a few seconds,
// in the middle of the vault snapshot. Now the window is "visible" but fully transparent, 1x1 and off screen (no
// taskbar, no Alt+Tab, never takes focus), so Windows really shows "Amnesia is cleaning up..." and waits. The
// snapshot also starts earlier (at "may I end the session?", harmless if the sign out is cancelled) and the cleanup
// itself comes right after, with a time limit for the snapshot.
// v0.7.1: sign out still did not clean on a real PC: Windows gave 5 to 7 seconds ("Amnesia.exe is delaying system
// shutdown after 5265 ms", then sign out anyway). The vault snapshot (Edge, 279 MB) ate all of it and the cleanup never
// started. Now the cleanup comes FIRST and alone: no snapshot at sign out any more (it happens while you are signed in,
// right after you close an app, see TrayApp and Core\AutoSnap.cs). "Amnesia is cleaning up..." is set while Windows asks
// and again around the cleanup. Nothing is touched at "may I end the session?": the cleanup only runs in WM_ENDSESSION
// once Windows says the session really ends (a cancelled sign out wipes nothing). That handler is also the last moment
// Windows waits for: Amnesia is ended as soon as it returns.
// v0.8: sign out still sometimes did not clean (only "query end session" in trace.log, then nothing). Now the list of what
// goes is made in the background right at "may I end the session?" (nothing is touched yet), and a running vault
// snapshot is stopped, so WM_ENDSESSION only has to move. Every step writes its time to trace.log. After a panic, the
// sign out that follows does a quick second pass (files apps had open are free then). The USB key waits a moment and
// looks again before it acts (a USB stick can "disappear" for a second when the laptop wakes up).
// v0.8.1: a real Windows 11 test still cleaned only at the next sign in: WM_ENDSESSION gave about 5 seconds, the Safe box
// (165 MB) took 4.4 of them and Windows ended Amnesia right after the wipe started. "Amnesia is cleaning up..." was never
// shown, because Windows only shows it (and waits) for an app that is still answering "may I end the session?". So the
// wipe now runs right there, in WM_QUERYENDSESSION, with the reason set: Windows shows it after a few seconds and waits
// until Amnesia says yes (you can still press "Sign out anyway"). The Safe box is closed after the wipe, and the Keep
// lock after that. WM_ENDSESSION then has nothing left to do. Trade-off: if another app (or you) cancels the sign out
// after Amnesia said yes, the wipe already happened and you stay signed in, like after "Clean now". The window is no
// longer owned by WinForms' hidden taskbar window (an owned window may not count as a top-level window here).
using System.Runtime.InteropServices;
using Amnesia.Core;

namespace Amnesia;

sealed class ShutdownWatcher : Form
{
    const int WM_QUERYENDSESSION = 0x11, WM_ENDSESSION = 0x16, WM_HOTKEY = 0x312, WM_DEVICECHANGE = 0x219;
    const long ENDSESSION_CLOSEAPP = 0x1; // an installer / Restart Manager closes Amnesia: NOT a sign out, never clean
    const int DBT_DEVICEARRIVAL = 0x8000, DBT_DEVICEREMOVECOMPLETE = 0x8004;
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    bool hotkey, usbSeen;
    DateTime awake = DateTime.MinValue;
    readonly System.Windows.Forms.Timer usbCheck = new();
    /// <summary>v0.8: called when Windows asks "may I end the session?" (TrayApp stops the vault snapshot).</summary>
    public Action? SessionEnding;
    /// <summary>v0.8.1: when the wipe ran at "may I end the session?" (WM_ENDSESSION then skips it).</summary>
    DateTime cleanedAtQuery = DateTime.MinValue;

    public ShutdownWatcher()
    {
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(-32000, -32000);
        Size = new Size(1, 1);
        Opacity = 0;
        // be asked (almost) last, after the other apps closed (their files are free then)
        Native.SetProcessShutdownParameters(0x101, 0);
        _ = Handle; // the window exists without ever being shown
        ApplyHotkey();
        usbSeen = Guard.UsbKeyPresent();
        Microsoft.Win32.SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode == Microsoft.Win32.PowerModes.Resume) awake = DateTime.Now;
            else if (e.Mode == Microsoft.Win32.PowerModes.Suspend) awake = DateTime.MaxValue; // asleep: never act until it wakes up
        };
        usbCheck.Tick += (_, _) => UsbCheck();
    }

    /// <summary>v0.8 (MED-WIN-03): the USB key looked gone. Acts only if it is still gone a moment later.</summary>
    void UsbGone()
    {
        bool wokeUp = awake == DateTime.MaxValue || DateTime.Now - awake < TimeSpan.FromSeconds(30);
        usbCheck.Stop();
        usbCheck.Interval = wokeUp ? 8000 : 1500;
        usbCheck.Start();
        AppInfo.Trace($"usb key gone? looking again in {usbCheck.Interval / 1000.0:0.#} s{(wokeUp ? " (just woke up)" : "")}");
    }

    void UsbCheck()
    {
        usbCheck.Stop();
        if (awake == DateTime.MaxValue) { usbCheck.Interval = 8000; usbCheck.Start(); return; } // still asleep
        if (Guard.UsbKeyPresent()) { usbSeen = true; AppInfo.Trace("usb key is back: nothing done"); return; }
        if (!usbSeen || string.IsNullOrEmpty(Settings.Get("USB_KEY"))) return;
        usbSeen = false;
        if (Settings.Enabled) Guard.QuickExit("usb key", shutdown: Settings.Get("USB_ACTION") == "shutdown");
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 /* NOACTIVATE: also keeps it off the taskbar */ | 0x20 /* TRANSPARENT: clicks go through */;
            cp.Parent = IntPtr.Zero; // v0.8.1: a real top-level window, not owned by WinForms' hidden taskbar window
            return cp;
        }
    }

    /// <summary>Called once at start: a visible (but invisible to you) window is what makes Windows wait at sign out.</summary>
    public void Arm() { Show(); Location = new Point(-32000, -32000); Size = new Size(1, 1); }

    /// <summary>(Re)registers the panic hotkey from settings (PANIC_HOTKEY). Returns false when another app already uses it.</summary>
    public bool ApplyHotkey()
    {
        if (hotkey) { UnregisterHotKey(Handle, 1); hotkey = false; }
        var want = Settings.Get("PANIC_HOTKEY");
        var hk = Guard.Hotkeys.FirstOrDefault(h => h.id == want);
        if (hk.id == null) return true;
        hotkey = RegisterHotKey(Handle, 1, hk.mods | 0x4000 /* no repeat */, (uint)hk.key);
        if (!hotkey) AppInfo.Trace("panic hotkey is taken by another app");
        return hotkey;
    }

    /// <summary>The USB key was picked or cleared in Settings.</summary>
    public void UsbChanged() => usbSeen = Guard.UsbKeyPresent();

    protected override void WndProc(ref Message m)
    {
        switch (m.Msg)
        {
            case WM_QUERYENDSESSION:
                AppInfo.Trace($"query end session (flags {m.LParam.ToInt64():x}, on {Settings.Enabled}, paused {Settings.Paused})");
                if ((m.LParam.ToInt64() & ENDSESSION_CLOSEAPP) == 0)
                {
                    // v0.8.1: clean right here. Windows waits (and shows the reason) while this message is not answered.
                    if (Settings.Enabled || Safe.IsOpen)
                    {
                        bool held = Native.ShutdownBlockReasonCreate(Handle, Text2.Cleaning);
                        if (!held) AppInfo.Trace($"sign out reason not set (error {Marshal.GetLastWin32Error()})");
                    }
                    try { SessionEnding?.Invoke(); } catch { }
                    if (Settings.Enabled) SignOutClean(Handle, "query");
                    else Cleaner.CloseSafe("sign out"); // v0.8: the Safe box closes even while Amnesia is off
                    cleanedAtQuery = DateTime.UtcNow;
                }
                m.Result = 1;
                return;
            case WM_ENDSESSION when m.WParam == IntPtr.Zero:
                AppInfo.Trace(DateTime.UtcNow - cleanedAtQuery < TimeSpan.FromMinutes(5)
                    ? "end session cancelled after the cleanup: you stay signed in" : "end session cancelled (another app said no)");
                cleanedAtQuery = DateTime.MinValue;
                Native.ShutdownBlockReasonDestroy(Handle);
                break;
            case WM_ENDSESSION:
                AppInfo.Trace($"end session (flags {m.LParam.ToInt64():x})");
                if ((m.LParam.ToInt64() & ENDSESSION_CLOSEAPP) != 0) { AppInfo.Trace("closed by an installer, not a sign out: no cleanup"); }
                else if (DateTime.UtcNow - cleanedAtQuery < TimeSpan.FromMinutes(5)) { } // v0.8.1: already done while Windows waited
                else if (Settings.Enabled) SignOutClean(Handle, "end"); // no "may I?" first (forced sign out, after a panic)
                else Cleaner.CloseSafe("sign out");
                Native.ShutdownBlockReasonDestroy(Handle);
                m.Result = IntPtr.Zero;
                return;
            case WM_HOTKEY when m.WParam.ToInt32() == 1:
                Guard.QuickExit("hotkey");
                return;
            case WM_DEVICECHANGE:
                int ev = m.WParam.ToInt32();
                if (ev == DBT_DEVICEARRIVAL && !usbSeen) usbSeen = Guard.UsbKeyPresent();
                else if (ev == DBT_DEVICEREMOVECOMPLETE && usbSeen && !string.IsNullOrEmpty(Settings.Get("USB_KEY")) && !Guard.UsbKeyPresent())
                    UsbGone();
                break;
        }
        base.WndProc(ref m);
    }

    /// <summary>The cleanup at sign out / restart / shut down. v0.8.1: runs inside WM_QUERYENDSESSION (Windows waits while
    /// it is not answered and shows "Amnesia is cleaning up..."), or in WM_ENDSESSION when Windows did not ask first.
    /// The wipe first, then the Safe box, then the Keep lock. The cleanup writes "clean logout N bytes" to the History.</summary>
    static void SignOutClean(IntPtr hwnd, string where)
    {
        var t = System.Diagnostics.Stopwatch.StartNew();
        Native.ShutdownBlockReasonCreate(hwnd, Text2.Cleaning);
        if (Guard.JustCleaned) AppInfo.Trace("second pass after a quick exit");
        try { var r = Cleaner.Run("logout", endSession: true); AppInfo.Trace($"logout clean finished in {t.Elapsed.TotalSeconds:0.0} s at {where} ({r.Skipped ?? r.Count.ToString()})"); }
        catch (Exception e) { AppInfo.Trace($"logout clean failed after {t.Elapsed.TotalSeconds:0.0} s: {e.GetType().Name}"); }
        Cleaner.CloseSafe("logout");
        // the Keep folder is locked again after the cleanup (it is quick, but the cleanup comes first)
        KeepLock.Lock("sign out", links: false);
    }
}

/// <summary>The few texts shown outside the page (tray, shutdown screen), in English or Indonesian.</summary>
static class Text2
{
    static bool Id => AppInfo.Id;
    public static string Cleaning => Id ? "Amnesia sedang membersihkan..." : "Amnesia is cleaning up...";
    public static string Open => Id ? "Buka Amnesia" : "Open Amnesia";
    public static string Quit => Id ? "Keluar" : "Quit";
    public static string OpenKeep => Id ? "Buka folder Keep" : "Open Keep folder";
    public static string TurnOn => Id ? "Nyalakan Amnesia" : "Turn On Amnesia";
    public static string TurnOff => Id ? "Matikan Amnesia" : "Turn Off Amnesia";
    public static string Review => Id ? "Cek dulu, lalu sign out..." : "Review and sign out...";
    public static string Panic => Id ? "Sign out darurat sekarang" : "Panic sign out now";
    public static string ConfirmOff => Id
        ? "Matikan Amnesia? Setelah ini tidak ada yang dihapus saat sign out sampai kamu menyalakannya lagi."
        : "Turn off Amnesia? Nothing gets wiped at sign out until you turn it on again.";
    public static string ConfirmPanic => Id
        ? "Kunci layar, bersihkan, lalu sign out sekarang tanpa menunggu app lain? Pekerjaan yang belum disimpan hilang."
        : "Lock the screen, clean up and sign out now without waiting for other apps? Unsaved work is lost.";
    public static string RestoreTitle => Id ? "Vault siap" : "Vault ready";
    public static string RestoreText => Id ? "Klik untuk memulihkan login app kamu dari vault." : "Click to bring your app logins back from the vault.";
    public static string BackupDone => Id ? "Backup selesai" : "Backup done";
    public static string BackupFailed => Id ? "Backup otomatis gagal. Buka Amnesia untuk detailnya." : "Automatic backup failed. Open Amnesia for details.";
    public static string UpdateTitle => Id ? "Update Amnesia tersedia" : "Amnesia update available";
    // v0.7 lab lock + Keep lock
    public static string LabTitle => Id ? "Amnesia dikunci admin" : "Amnesia is locked by the admin";
    public static string LabAsk => Id ? "Masukkan PIN admin untuk lanjut." : "Enter the admin PIN to go on.";
    public static string KeepLockTitle => Id ? "Folder Keep terkunci" : "Keep folder is locked";
    public static string KeepLockAsk => Id ? "Masukkan password Keep untuk membukanya." : "Enter the Keep password to open it.";
    public static string LabNoOff => Id ? "Kunci lab sedang aktif, jadi Amnesia selalu nyala. Untuk mematikannya, lepas dulu kunci lab di Pengaturan → Lanjutan." : "The lab lock is on, so Amnesia always stays on. To turn it off, remove the lab lock first in Settings → Advanced.";
    public static string LockKeep => Id ? "Kunci folder Keep sekarang" : "Lock Keep folder now";
    // v0.8
    public static string StartupOffTitle => Id ? "Amnesia tidak jalan saat sign in" : "Amnesia doesn't start at sign in";
    public static string StartupOffText => Id
        ? "Amnesia dimatikan di Task Manager → Startup apps, jadi tidak ada yang dibersihkan sampai kamu membukanya. Klik untuk menyalakan lagi."
        : "Amnesia is switched off in Task Manager → Startup apps, so nothing gets cleaned until you open it. Click to switch it back on.";
    public static string KeepUninstallTitle => Id ? "Buka kunci folder Keep" : "Unlock the Keep folder";
    public static string KeepUninstallAsk => Id
        ? "Folder Keep masih terkunci. Masukkan password Keep supaya terbuka setelah Amnesia dihapus. Batal = Keep tetap terkunci."
        : "Your Keep folder is still locked. Enter the Keep password so it is open after Amnesia is removed. Cancel = Keep stays locked.";
    public static string KeepStaysLocked(string dir) => Id
        ? $"Folder Keep tetap terkunci. Untuk membukanya nanti: pasang Amnesia lagi dan buka dengan password Keep, atau ketik ini di Command Prompt (akun kamu sendiri):\n\nicacls \"{dir}\" /remove:d \"%USERNAME%\" /T"
        : $"Your Keep folder stays locked. To open it later: install Amnesia again and open it with the Keep password, or type this in Command Prompt (your own account):\n\nicacls \"{dir}\" /remove:d \"%USERNAME%\" /T";
    // v0.8.1
    public static string SafeUninstall(int n) => Id
        ? (n > 0 ? $"Brankas kamu masih berisi {n} file." : "Brankas kamu masih berisi file.") + " Buka dan pindahkan dulu, atau biarkan: brankas bisa dibuka lagi setelah kamu memasang Amnesia lagi (asal data Amnesia tidak ikut dihapus).\n\nTetap uninstall?"
        : (n > 0 ? $"Your safe box still has {n} file(s)." : "Your safe box still has files.") + " Open it and move them first, or keep it: it opens again after you reinstall Amnesia (as long as Amnesia's data is not deleted too).\n\nUninstall anyway?";
    public static string KeepAclTitle => Id ? "Folder Keep masih terkunci" : "Keep is still locked";
    public static string KeepAclText => Id ? "Kunci lama dari versi sebelumnya masih ada. Klik untuk membukanya." : "An old lock from an earlier version is still on it. Click to open it.";
    public static string Blocked(int n) => Id
        ? $"{n} item tidak bisa dibersihkan karena diblok Windows Security atau antivirus. Buka Amnesia untuk caranya."
        : $"{n} items could not be cleaned: Windows Security or an antivirus blocked Amnesia. Open Amnesia to see how to fix it.";
}
