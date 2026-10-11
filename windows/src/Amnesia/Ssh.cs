// v0.4 backup to your own server: scp.exe (OpenSSH, built into Windows 10/11) with your SSH key, no password prompts.
// Your key lives in %USERPROFILE%\.ssh, which Amnesia adds to the Keep List when you set up an SSH backup.
using Amnesia.Core;

namespace Amnesia;

static class Ssh
{
    static string Scp => Path.Combine(Environment.SystemDirectory, "OpenSSH", "scp.exe");
    static string SshExe => Path.Combine(Environment.SystemDirectory, "OpenSSH", "ssh.exe");
    public static bool Available => File.Exists(Scp);

    static (string host, string path) Split(string target)
    {
        int i = target.IndexOf(':');
        return i > 0 ? (target[..i], target[(i + 1)..]) : (target, ".");
    }

    static string[] Common() => new[] { "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new" };

    /// <summary>Uploads one file. Returns null when it worked, else what went wrong.</summary>
    public static string? Upload(string file, CancellationToken cancel)
    {
        var target = Conf.Get("BACKUP_SSH");
        if (string.IsNullOrEmpty(target)) return "no-ssh";
        if (!Available) return "OpenSSH is not installed (Settings → System → Optional features → OpenSSH Client)";
        var port = Conf.Get("BACKUP_PORT") ?? "22";
        var args = new List<string>(Common()) { "-P", port, file, target.TrimEnd('/') + "/" };
        return Run(Scp, args, TimeSpan.FromHours(6), cancel);
    }

    /// <summary>"Test connection": logs in once and checks the folder exists.</summary>
    public static string? Test()
    {
        var target = Conf.Get("BACKUP_SSH");
        if (string.IsNullOrEmpty(target)) return "no-ssh";
        if (!Available) return "OpenSSH is not installed (Settings → System → Optional features → OpenSSH Client)";
        var (host, path) = Split(target);
        var args = new List<string>(Common()) { "-p", Conf.Get("BACKUP_PORT") ?? "22", host, $"test -d '{path.Replace("'", "")}' && echo ok" };
        return Run(SshExe, args, TimeSpan.FromSeconds(30), default);
    }

    static string? Run(string exe, List<string> args, TimeSpan timeout, CancellationToken cancel)
    {
        var psi = new System.Diagnostics.ProcessStartInfo(exe) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var a in args) psi.ArgumentList.Add(a);
        using var p = System.Diagnostics.Process.Start(psi)!;
        var err = p.StandardError.ReadToEndAsync();
        _ = p.StandardOutput.ReadToEndAsync();
        var until = DateTime.Now + timeout;
        while (!p.WaitForExit(500))
        {
            if (cancel.IsCancellationRequested || DateTime.Now > until) { try { p.Kill(true); } catch { } return "stopped"; }
        }
        return p.ExitCode == 0 ? null : (err.Result.Trim() is { Length: > 0 } e ? e.Split('\n')[^1].Trim() : $"exit {p.ExitCode}");
    }
}
