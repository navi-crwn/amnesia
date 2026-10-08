// Runs scripts\clean.ps1 with Windows PowerShell (built into every Windows 10/11).
// Only the dry run (show what WOULD be deleted) exists in this early version.
using System.Diagnostics;
using System.Text.Json.Nodes;

namespace Amnesia;

static class Cleaner
{
    static string Script => Path.Combine(AppInfo.BaseDir, "scripts", "clean.ps1");

    public static async Task<JsonNode?> PreviewAsync()
    {
        var psi = new ProcessStartInfo("powershell.exe")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
        };
        foreach (var a in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Script, "-Mode", "now", "-DryRun", "-Json" })
            psi.ArgumentList.Add(a);

        using var p = Process.Start(psi) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var outTask = p.StandardOutput.ReadToEndAsync();
        var errTask = p.StandardError.ReadToEndAsync();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(120));
        try { await p.WaitForExitAsync(cts.Token); }
        catch (OperationCanceledException) { p.Kill(true); throw new TimeoutException("The preview took longer than 2 minutes and was stopped."); }

        var output = await outTask;
        if (p.ExitCode != 0) throw new InvalidOperationException((await errTask).Trim() is { Length: > 0 } e ? e : $"clean.ps1 stopped with code {p.ExitCode}.");
        return JsonNode.Parse(output);
    }
}
