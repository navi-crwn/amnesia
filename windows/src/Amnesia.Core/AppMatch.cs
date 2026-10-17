// v0.8: which AppData folders belong to an installed program, so the Keep List can show "Discord" with its icon
// instead of AppData/Roaming/discord, and "Keep an app..." can keep all of an app's folders in one go.
// A guess from names only (the same idea as the leftover finder): it never deletes anything, it only suggests.
namespace Amnesia.Core;

public static class AppMatch
{
    // AppData folders that hold many programs or Windows itself: never offered as "this app's data"
    public static readonly string[] Skip =
    {
        "Microsoft", "Packages", "Temp", "Amnesia", "Programs", "Comms", "ConnectedDevicesPlatform", "CrashDumps", "D3DSCache",
        "PeerDistRepub", "Publishers", "VirtualStore", "PlaceholderTileLogoFolder", "OneDrive", "IsolatedStorage", "CoreAIPlatform.00",
        "Package Cache", "PackageManagement", "Apps", "Intel", "NVIDIA", "NVIDIA Corporation", "AMD", "Realtek", "Windows",
    };

    /// <summary>The AppData folders (home relative, "/" separated) that look like they belong to this program.
    /// candidates: every AppData/{Roaming,Local,LocalLow}/X and, for folders named after a publisher, X/Y.</summary>
    public static List<string> Folders(string name, string? publisher, string? installDir, IEnumerable<string> candidates)
    {
        var found = new List<string>();
        var n = Leftovers.Norm(name);
        var first = Leftovers.Norm(name.Split(' ', '-', '_', '.', '(')[0]);
        var pub = publisher is { Length: > 0 } ? Leftovers.Norm(publisher) : "";
        var inst = installDir is { Length: > 3 } ? Leftovers.Norm(Path.GetFileName(installDir.TrimEnd('\\', '/'))) : "";
        if (n.Length < 3) return found;
        foreach (var rel in candidates)
        {
            var parts = rel.Split('/');
            if (parts.Length < 3) continue;
            var leaf = Leftovers.Norm(parts[^1]);
            if (leaf.Length < 3 || Skip.Contains(parts[2], StringComparer.OrdinalIgnoreCase)) continue;
            bool deep = parts.Length > 3;
            // Vendor/App: the vendor folder must be the publisher, the app folder must be the app
            if (deep && (pub.Length < 3 || !Leftovers.Norm(parts[2]).Equals(pub))) continue;
            bool same = leaf == n || leaf == inst || n.StartsWith(leaf) && leaf.Length >= 4 || first.Length >= 4 && leaf.StartsWith(first)
                        || deep && leaf.Length >= 4 && n.Contains(leaf);
            // a folder named only after the publisher ("Google") is shared by its apps: not this app's own
            if (!deep && pub.Length >= 3 && leaf == pub && leaf != n) continue;
            if (same) found.Add(rel);
        }
        return found;
    }
}
