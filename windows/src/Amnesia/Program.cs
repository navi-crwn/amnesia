// Amnesia for Windows: starts the tray icon. Only one Amnesia runs at a time; opening it again shows the window.
//   --login        started by Windows at sign in: no window, run the sign in check
//   --login-tray   after an update: tray icon only, no window and no sign in check
//   --quit         closes the running Amnesia (used by Setup.exe before it updates or uninstalls; never a cleanup)
//   --off          Turn Off (used by the uninstaller), then --quit
//   --admin spec   the Windows protections switches (Settings → Advanced), in a copy Windows started as administrator
//   --lab-check    v0.7, used by the uninstaller: when the lab lock is on, asks its PIN and removes it (exit 0 = go ahead)
//   --open-keep    v0.7, the Desktop shortcut while the Keep lock is on: asks the Keep password, then opens Keep
//   --keep-check   v0.8, used by the uninstaller: when Keep is locked, asks the Keep password and opens it for good.
//                  No password: Amnesia is still removed, Keep stays locked and you are told how to open it later.
//                  Exit 0 = Keep is open (or was never locked), 2 = Keep stays locked.
namespace Amnesia;

static class Program
{
    static Mutex? single;
    public static EventWaitHandle ShowSignal = new(false, EventResetMode.AutoReset, @"Local\Amnesia.Show");
    public static EventWaitHandle QuitSignal = new(false, EventResetMode.AutoReset, @"Local\Amnesia.Quit");
    public static EventWaitHandle OpenKeepSignal = new(false, EventResetMode.AutoReset, @"Local\Amnesia.OpenKeep");

    [STAThread]
    static int Main(string[] args)
    {
        Core.Home.Version = AppInfo.Version;
        if (args.Length >= 2 && args[0] == "--admin") return AdminTasks.RunElevated(args[1]);
        if (args.Contains("--lab-check"))
        {
            ApplicationConfiguration.Initialize();
            if (!Amnesia.Core.Lab.Active) return 0;
            // the PIN, then the lab lock is removed for good (one Windows prompt), so nothing stays in HKLM\...\Run
            string? pin = PinPrompt.Ask(null, Text2.LabTitle, Text2.LabAsk, digitsOnly: true, check: Amnesia.Core.Lab.Check);
            try { return pin != null && LabLock.TurnOff(pin) ? 0 : 1; } catch { return 1; }
        }
        if (args.Contains("--keep-check"))
        {
            ApplicationConfiguration.Initialize();
            if (!KeepLock.On) return 0;
            string? pw = PinPrompt.Ask(null, Text2.KeepUninstallTitle, Text2.KeepUninstallAsk, digitsOnly: false,
                check: p => Amnesia.Core.Pin.Verify(p, Settings.Get("KEEP_LOCK_PW")));
            if (pw != null) { try { KeepLock.TurnOff(pw); return 0; } catch { } }
            AppInfo.Trace("uninstall without the Keep password: Keep stays locked");
            MessageBox.Show(Text2.KeepStaysLocked(Settings.KeepDir), "Amnesia", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 2;
        }
        if (args.Contains("--off"))
        {
            Setup.TurnOff(leaveStartup: false);
            Settings.Set("KEEP_SHORTCUT", "0"); Settings.Set("KEEP_PIN", "0");
            KeepLinks.SyncNow();
        }
        if (args.Contains("--quit") || args.Contains("--off"))
        {
            QuitSignal.Set();
            // wait (at most 10 s) until the running Amnesia has closed, so its files are free for the installer
            using var m = new Mutex(false, @"Local\Amnesia.SingleInstance");
            try { if (m.WaitOne(10_000)) m.ReleaseMutex(); } catch (AbandonedMutexException) { }
            return 0;
        }

        single = new Mutex(true, @"Local\Amnesia.SingleInstance", out bool first);
        if (!first)
        {
            if (args.Contains("--open-keep")) OpenKeepSignal.Set();
            else if (!args.Contains("--login")) ShowSignal.Set(); // already running: ask it to show its window
            return 0;
        }

        bool atLogin = args.Contains("--login");
        ApplicationConfiguration.Initialize();
        bool trayOnly = args.Contains("--login-tray") || args.Contains("--open-keep");
        if (args.Contains("--open-keep")) OpenKeepSignal.Set(); // picked up by the tray once it runs
        Application.Run(new TrayApp(showWindow: !atLogin && !trayOnly, cleanAtLogin: atLogin));
        try { single?.ReleaseMutex(); } catch { }
        return 0;
    }

    /// <summary>Lets the copy in the install folder start while this one quits (used once, right after Turn On).</summary>
    public static void HandOver(string exe)
    {
        single?.ReleaseMutex();
        single?.Dispose();
        single = null;
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = true });
    }
}
