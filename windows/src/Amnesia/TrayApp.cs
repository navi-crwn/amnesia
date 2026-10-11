// The tray icon (next to the clock) and its menu. The window is only created while it is open,
// so when it is closed Amnesia is just this small icon. At sign in it starts here, without a window.
// v0.4: also runs the timers for "sign out when idle", automatic backups and the daily update check.
using Amnesia.Core;

namespace Amnesia;

sealed class TrayApp : ApplicationContext
{
    readonly NotifyIcon icon;
    public readonly ShutdownWatcher Watcher = new();
    readonly SynchronizationContext ui;
    MainWindow? window;
    readonly ToolStripMenuItem power;
    readonly System.Windows.Forms.Timer tick = new() { Interval = 15_000 };
    IdleCountdown? countdown;
    string? balloonView;
    int backupBusy;
    DateTime nextSlowCheck = DateTime.Now.AddMinutes(2);
    /// <summary>Page the window should open on (set by the tray menu / notifications, read by the page).</summary>
    public string? PendingView;

    public TrayApp(bool showWindow, bool cleanAtLogin)
    {
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        var menu = new ContextMenuStrip();
        menu.Items.Add(Text2.Open, null, (_, _) => Open());
        menu.Items.Add(Text2.OpenKeep, null, (_, _) => { try { KeepLinks.OpenKeep(); } catch { } });
        menu.Items.Add(new ToolStripSeparator());
        var review = menu.Items.Add(Text2.Review, null, (_, _) => Open("review"));
        var panic = menu.Items.Add(Text2.Panic, null, (_, _) =>
        {
            if (MessageBox.Show(Text2.ConfirmPanic, "Amnesia", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes) Guard.QuickExit("tray");
        });
        menu.Items.Add(new ToolStripSeparator());
        power = new ToolStripMenuItem("", null, (_, _) => TogglePower());
        menu.Items.Add(power);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Text2.Quit, null, (_, _) => Quit());
        menu.Opening += (_, _) =>
        {
            power.Text = Settings.Enabled ? Text2.TurnOff : Text2.TurnOn;
            review.Visible = panic.Visible = Settings.Enabled;
        };

        icon = new NotifyIcon
        {
            Icon = AppInfo.Icon,
            Text = $"Amnesia {AppInfo.Version}",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) Open(); };
        icon.BalloonTipClicked += (_, _) => Open(balloonView);

        // a second Amnesia.exe was opened: show this window instead. Setup.exe asks us to close: quit (no cleanup).
        new Thread(() => { while (Program.ShowSignal.WaitOne()) ui.Post(_ => Open(), null); }) { IsBackground = true }.Start();
        new Thread(() => { if (Program.QuitSignal.WaitOne()) ui.Post(_ => { AppInfo.Trace("asked to quit (installer)"); Quit(); }, null); }) { IsBackground = true }.Start();

        if (Setup.RunningInstalled) Setup.Unblock(Setup.InstallDir);
        Watcher.Arm();
        Vault.QuitApps = QuitApps;
        Backup.Upload = Ssh.Upload;
        AppInfo.Trace($"started (sign in: {cleanAtLogin}, on: {Settings.Enabled}, uptime {Environment.TickCount64 / 1000} s)");
        if (cleanAtLogin && Settings.Enabled) Task.Run(() =>
        {
            var t = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                var r = Cleaner.Run("login");
                AppInfo.Trace($"sign in check finished in {t.Elapsed.TotalSeconds:0.0} s");
                if (r.Blocked > 0) Balloon("Amnesia", Text2.Blocked(r.Blocked), ToolTipIcon.Warning, "home");
            }
            catch (Exception e) { AppInfo.Trace($"sign in check failed after {t.Elapsed.TotalSeconds:0.0} s: {e.GetType().Name}"); }
            KeepLinks.Sync(); // the Desktop shortcut and the side bar pin were wiped with everything else
            // v0.4: the vault has snapshots: offer to bring the logins back
            if (Vault.Exists && Vault.Manifest().Count > 0 && Settings.Get("RESTORE_REMIND") != "0")
                Balloon(Text2.RestoreTitle, Text2.RestoreText, ToolTipIcon.Info, "vault");
        });
        else if (Settings.Enabled) KeepLinks.Sync();
        tick.Tick += (_, _) => Tick();
        tick.Start();
        if (showWindow) Open();
    }

    void Balloon(string title, string text, ToolTipIcon kind, string? view) => ui.Post(_ =>
    {
        balloonView = view;
        icon.ShowBalloonTip(10_000, title, text, kind);
    }, null);

    void Tick()
    {
        // sign out when idle (Settings → Advanced)
        int min = Conf.Int("IDLE_MIN");
        if (min > 0 && Settings.Enabled && countdown == null && Guard.IdleSeconds() >= min * 60 - 60)
        {
            countdown = new IdleCountdown();
            countdown.FormClosed += (_, _) => countdown = null;
            countdown.Show();
        }
        if (DateTime.Now < nextSlowCheck) return;
        nextSlowCheck = DateTime.Now.AddMinutes(30);
        // automatic backup (Backup page)
        if (Backup.Due() && Interlocked.Exchange(ref backupBusy, 1) == 0)
            Task.Run(() =>
            {
                try { Backup.Create(); AppInfo.Trace("automatic backup done"); }
                catch (Exception e) { AppInfo.Trace($"automatic backup failed: {e.GetType().Name}"); Balloon("Amnesia", Text2.BackupFailed, ToolTipIcon.Warning, "backup"); }
                finally { backupBusy = 0; }
            });
        // daily update check (Settings → Update)
        if (Settings.Get("UPDATE_CHECK") != "0" && Settings.Get("UPDATE_LAST_CHECK") != DateTime.Now.ToString("yyyy-MM-dd"))
        {
            Settings.Set("UPDATE_LAST_CHECK", DateTime.Now.ToString("yyyy-MM-dd"));
            Task.Run(async () =>
            {
                try { var r = await Updater.LatestAsync(); if (r != null && Updater.Newer(r.Version)) Balloon(Text2.UpdateTitle, $"Amnesia {r.Version}", ToolTipIcon.Info, "settings"); }
                catch { }
            });
        }
    }

    /// <summary>Closes apps before their data is saved or replaced in the vault: politely first, then for sure.</summary>
    static void QuitApps(IEnumerable<string> names)
    {
        var procs = names.SelectMany(n => System.Diagnostics.Process.GetProcessesByName(n)).ToList();
        if (procs.Count == 0) return;
        foreach (var p in procs) try { p.CloseMainWindow(); } catch { }
        var until = DateTime.Now.AddSeconds(5);
        while (DateTime.Now < until && procs.Any(p => { try { return !p.HasExited; } catch { return false; } })) Thread.Sleep(200);
        foreach (var p in procs) try { if (!p.HasExited) p.Kill(true); } catch { }
        Thread.Sleep(500);
    }

    public void Open(string? view = null)
    {
        if (view != null) PendingView = view;
        if (window is { IsDisposed: false })
        {
            if (window.WindowState == FormWindowState.Minimized) window.WindowState = FormWindowState.Normal;
            window.Show();
            window.Activate();
            if (view != null) window.ShowView(view);
            return;
        }
        window = new MainWindow(this);
        window.FormClosed += (_, _) => window = null;
        window.Show();
        window.Activate();
    }

    /// <summary>Turn On / Turn Off from the tray menu. The first Turn On happens in the window (it asks you to agree first).</summary>
    void TogglePower()
    {
        if (Settings.Enabled)
        {
            if (MessageBox.Show(Text2.ConfirmOff, "Amnesia", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            Setup.TurnOff();
        }
        else if (Setup.RunningInstalled && Settings.Get("APP_PATH") != null)
        {
            Setup.TurnOn();
            KeepLinks.Sync();
        }
        else { Open(); return; }
        window?.Reload();
    }

    /// <summary>Runs something on the window thread (the bridge answers on other threads).</summary>
    public void Invoke(Action a) => ui.Post(_ => a(), null);

    public void Quit()
    {
        tick.Stop();
        countdown?.Close();
        window?.Close();
        Watcher.Dispose();
        icon.Visible = false;
        icon.Dispose();
        ExitThread();
    }
}
