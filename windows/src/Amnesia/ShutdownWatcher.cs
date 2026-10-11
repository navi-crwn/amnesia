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
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 /* NOACTIVATE */ | 0x20 /* TRANSPARENT: clicks go through */;
            return cp;
        }
    }

    /// <summary>Called once at start: a visible (but invisible to you) window is what makes Windows wait at sign out.</summary>
    public void Arm() { Show(); Location = new Point(-32000, -32000); Size = new Size(1, 1); }

    static Thread? snapshot;

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
                AppInfo.Trace($"query end session (flags {m.LParam.ToInt64():x}, on {Settings.Enabled})");
                if (Settings.Enabled && (m.LParam.ToInt64() & ENDSESSION_CLOSEAPP) == 0)
                {
                    Native.ShutdownBlockReasonCreate(Handle, Text2.Cleaning);
                    StartSnapshot();
                }
                m.Result = 1;
                return;
            case WM_ENDSESSION when m.WParam == IntPtr.Zero:
                AppInfo.Trace("end session cancelled (another app said no)");
                snapshot = null;
                Native.ShutdownBlockReasonDestroy(Handle);
                break;
            case WM_ENDSESSION:
                AppInfo.Trace($"end session (flags {m.LParam.ToInt64():x})");
                if ((m.LParam.ToInt64() & ENDSESSION_CLOSEAPP) != 0) { AppInfo.Trace("closed by an installer, not a sign out: no cleanup"); }
                else if (Settings.Enabled && !Guard.JustCleaned) SignOutClean();
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
                {
                    usbSeen = false;
                    if (Settings.Enabled) Guard.QuickExit("usb key", shutdown: Settings.Get("USB_ACTION") == "shutdown");
                }
                break;
        }
        base.WndProc(ref m);
    }

    /// <summary>The automatic vault snapshot (apps that changed), started as soon as Windows asks. Saving is harmless
    /// even if the sign out is cancelled after all; nothing is wiped before WM_ENDSESSION.</summary>
    static void StartSnapshot()
    {
        if (snapshot != null || !Vault.Exists || Settings.Get("VAULT_AUTO") == "0" || Settings.Paused) return;
        snapshot = new Thread(() =>
        {
            var t = System.Diagnostics.Stopwatch.StartNew();
            AppInfo.Trace("auto snapshot: start");
            try { var s = Vault.Snapshot(changedOnly: true, budget: TimeSpan.FromSeconds(20)); AppInfo.Trace($"auto snapshot: {s.Count} app(s) in {t.Elapsed.TotalSeconds:0.0} s"); }
            catch (Exception e) { AppInfo.Trace($"auto snapshot failed: {e.GetType().Name}"); }
        }) { IsBackground = true };
        snapshot.Start();
    }

    static void SignOutClean()
    {
        var t = System.Diagnostics.Stopwatch.StartNew();
        // 1. the automatic vault snapshot started at "may I end the session?": wait for it (at most 40 s)
        StartSnapshot();
        if (snapshot != null && !snapshot.Join(TimeSpan.FromSeconds(40))) AppInfo.Trace("auto snapshot still busy, cleaning anyway");
        snapshot = null;
        // 2. the cleanup
        try { var r = Cleaner.Run("logout"); AppInfo.Trace($"logout clean finished in {t.Elapsed.TotalSeconds:0.0} s ({r.Skipped ?? r.Count.ToString()})"); }
        catch (Exception e) { AppInfo.Trace($"logout clean failed after {t.Elapsed.TotalSeconds:0.0} s: {e.GetType().Name}"); }
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
    public static string Blocked(int n) => Id
        ? $"{n} item tidak bisa dibersihkan karena diblok Windows Security atau antivirus. Buka Amnesia untuk caranya."
        : $"{n} items could not be cleaned: Windows Security or an antivirus blocked Amnesia. Open Amnesia to see how to fix it.";
}
