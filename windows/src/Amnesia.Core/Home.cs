// Where Amnesia keeps its things: %USERPROFILE%\.amnesia (same layout as the Mac).
// AMNESIA_HOME (environment variable) replaces the user folder. Only the tests use it; with it set, nothing outside
// that folder (registry, Recycle Bin, clipboard, other programs) is ever touched.
namespace Amnesia.Core;

public static class Home
{
    public static bool Test => !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("AMNESIA_HOME"));

    /// <summary>The user folder (C:\Users\you), or the fake one of the tests.</summary>
    public static string User => (Test ? Environment.GetEnvironmentVariable("AMNESIA_HOME")! : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
        .TrimEnd('\\', '/');

    /// <summary>%USERPROFILE%\.amnesia: settings.conf, keep.conf, vault, logs.</summary>
    public static string Dir => Path.Combine(User, ".amnesia");
    public static string Trash => Path.Combine(User, ".amnesia-trash");

    /// <summary>A path inside the user folder, written with / (as in keep.conf).</summary>
    public static string Full(string rel) => Path.Combine(User, rel.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar));

    public static string Version = "0.0.0";

    /// <summary>One line in trace.log: time + step. Steps only, never file names (a log is a trace too).</summary>
    public static void Trace(string who, string step)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var f = Path.Combine(Dir, "trace.log");
            File.AppendAllText(f, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {who} {Version}: {step}{Environment.NewLine}");
            // keep it short: the last 400 lines once it passes 600
            if (new FileInfo(f).Length > 60_000)
            {
                var lines = File.ReadAllLines(f);
                if (lines.Length > 600) File.WriteAllLines(f, lines[^400..]);
            }
        }
        catch { }
    }

    /// <summary>The History page: "time&lt;TAB&gt;kind&lt;TAB&gt;data", same format as the Mac.</summary>
    public static void History(string kind, string data)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.AppendAllText(Path.Combine(Dir, "history.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\t{kind}\t{data}{Environment.NewLine}");
        }
        catch { }
    }
}
