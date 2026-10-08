// Amnesia for Windows: starts the tray icon. Only one Amnesia runs at a time.
namespace Amnesia;

static class Program
{
    [STAThread]
    static void Main()
    {
        using var single = new Mutex(true, @"Local\Amnesia.SingleInstance", out bool first);
        if (!first) return; // already running: the tray icon is there

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
    }
}
