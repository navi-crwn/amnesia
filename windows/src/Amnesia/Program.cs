// Amnesia for Windows: starts the tray icon. Only one Amnesia runs at a time; opening it again shows the window.
//   --login        started by Windows at sign in: no window, run the sign in check
//   --login-tray   after an update: tray icon only, no window and no sign in check
//   --quit         closes the running Amnesia (used by Setup.exe before it updates or uninstalls; never a cleanup)
//   --off          Turn Off (used by the uninstaller), then --quit
//   --admin spec   the Windows protections switches (Settings → Advanced), in a copy Windows started as administrator
namespace Amnesia;

static class Program
{
    static Mutex? single;
    public static EventWaitHandle ShowSignal = new(false, EventResetMode.AutoReset, @"Local\Amnesia.Show");
    public static EventWaitHandle QuitSignal = new(false, EventResetMode.AutoReset, @"Local\Amnesia.Quit");

    [STAThread]
    static int Main(string[] args)
    {
        Core.Home.Version = AppInfo.Version;
        if (args.Length >= 2 && args[0] == "--admin") return AdminTasks.RunElevated(args[1]);
        if (args.Contains("--off"))
        {
            Setup.TurnOff();
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
            ShowSignal.Set(); // already running: ask it to show its window
            return 0;
        }

        bool atLogin = args.Contains("--login");
        ApplicationConfiguration.Initialize();
        bool trayOnly = args.Contains("--login-tray");
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
