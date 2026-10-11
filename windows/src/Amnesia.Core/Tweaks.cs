// v0.5 "Stop Windows remembering" (Settings → Advanced). Windows' own privacy switches in your part of the registry
// (no admin). The list of switches comes from Win11Debloat (MIT, see THIRD-PARTY-NOTICES.md) and privacy.sexy (ideas).
// Before Amnesia changes a value it writes down the old one (.amnesia\privacy-undo.txt), so "Undo" puts back exactly
// what was there.
namespace Amnesia.Core;

/// <summary>One registry value: key under HKCU, value name, the DWORD Amnesia sets.</summary>
public sealed record Tweak(string Group, string Key, string Name, int Value);

/// <summary>Reads and writes DWORD values (HKCU in the app, a dictionary in the tests).</summary>
public interface IRegStore
{
    int? Get(string key, string name);
    void Set(string key, string name, int value);
    void Delete(string key, string name);
}

public static class Tweaks
{
    public static string UndoFile => Path.Combine(Home.Dir, "privacy-undo.txt");

    static Dictionary<string, string> ReadUndo()
    {
        var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var l in File.ReadAllLines(UndoFile))
            {
                int i = l.LastIndexOf('\t');
                if (i > 0) d[l[..i]] = l[(i + 1)..];
            }
        }
        catch { }
        return d;
    }

    static void WriteUndo(Dictionary<string, string> d)
    {
        Directory.CreateDirectory(Home.Dir);
        if (d.Count == 0) { try { File.Delete(UndoFile); } catch { } return; }
        File.WriteAllLines(UndoFile, d.Select(kv => $"{kv.Key}\t{kv.Value}"));
    }

    static string Id(Tweak t) => $"{t.Key}\t{t.Name}";

    /// <summary>All values of a group are set the Amnesia way.</summary>
    public static bool IsOn(IRegStore s, IEnumerable<Tweak> group) => group.All(t => s.Get(t.Key, t.Name) == t.Value);

    public static void Apply(IRegStore s, IEnumerable<Tweak> tweaks)
    {
        var undo = ReadUndo();
        foreach (var t in tweaks)
        {
            // the first time only: a second Apply must not overwrite the real old value with Amnesia's own
            if (!undo.ContainsKey(Id(t))) undo[Id(t)] = s.Get(t.Key, t.Name)?.ToString() ?? "-";
            WriteUndo(undo); // written before the change, so a crash halfway can still be undone
            s.Set(t.Key, t.Name, t.Value);
        }
        WriteUndo(undo);
    }

    public static void Undo(IRegStore s, IEnumerable<Tweak> tweaks)
    {
        var undo = ReadUndo();
        foreach (var t in tweaks)
        {
            if (!undo.TryGetValue(Id(t), out var old)) continue; // Amnesia never changed this one
            if (old == "-") s.Delete(t.Key, t.Name);
            else if (int.TryParse(old, out var v)) s.Set(t.Key, t.Name, v);
            undo.Remove(Id(t));
        }
        WriteUndo(undo);
    }
}
