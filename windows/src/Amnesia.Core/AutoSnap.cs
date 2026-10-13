// v0.7.1: the automatic vault snapshot happens while you are signed in, no longer at sign out. At sign out Windows gave
// Amnesia only 5 to 7 seconds: a big browser snapshot (Edge, 279 MB) was cut off half way and the cleanup after it never
// started. Now an app is saved in the background right after you close it (all of its programs are gone) and its data
// changed since the last snapshot. An app is never saved while it runs. Apps without a program of their own (Claude Code,
// Git, a folder you added) are saved once their data changed and nothing touched it for a few minutes.
namespace Amnesia.Core;

public sealed class AutoSnap(TimeSpan quiet, TimeSpan checkQuietEvery)
{
    readonly HashSet<string> open = new(StringComparer.OrdinalIgnoreCase);
    DateTime nextQuiet = DateTime.MinValue;

    /// <summary>The chosen apps to save now. running: is a program with this name running? Call it every minute or so.</summary>
    public List<string> Due(Func<string, bool> running, DateTime nowUtc)
    {
        var due = new List<string>();
        var chosen = Vault.Chosen();
        bool quietCheck = nowUtc >= nextQuiet;
        if (quietCheck) nextQuiet = nowUtc + checkQuietEvery;
        foreach (var a in Vault.All())
        {
            if (!chosen.Contains(a.Name) || Vault.Present(a).Length == 0) continue;
            if (a.Process == null)
            {
                if (quietCheck && Vault.ChangedAndQuiet(a, quiet, nowUtc)) due.Add(a.Name);
                continue;
            }
            if (running(a.Process)) { open.Add(a.Name); continue; }
            // it was open the last time we looked, now all of its programs are gone: you closed it
            if (open.Remove(a.Name)) due.Add(a.Name);
        }
        return due;
    }
}
