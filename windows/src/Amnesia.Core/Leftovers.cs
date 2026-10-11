// v0.5 "Find leftovers" (Settings → Advanced). Uninstallers often leave folders behind in Program Files and ProgramData,
// and settings in your part of the registry. Idea from Bulk Crap Uninstaller ("orphans", Apache 2.0) and Pearcleaner
// (finding an app's files by its name): a folder whose name matches no installed program is probably left over.
// Nothing is deleted here: the list is shown and you choose. Folders with programs (.exe) in them are marked "careful".
namespace Amnesia.Core;

public sealed record Leftover(string Path, string Name, bool Empty, bool HasExe, long Bytes)
{
    /// <summary>"likely" = empty or no programs inside; "careful" = has .exe files (maybe a portable app you still use).</summary>
    public string Level => HasExe ? "careful" : "likely";
}

public static class Leftovers
{
    // folders Windows (or drivers) make by themselves: never offered
    public static readonly string[] SystemNames =
    {
        "Microsoft", "Windows", "Windows Defender", "Windows Defender Advanced Threat Protection", "Windows Mail", "Windows Media Player",
        "Windows NT", "Windows Photo Viewer", "Windows Portable Devices", "Windows Security", "Windows Sidebar", "WindowsApps",
        "WindowsPowerShell", "Common Files", "Internet Explorer", "ModifiableWindowsApps", "Reference Assemblies", "MSBuild",
        "dotnet", "Uninstall Information", "Packages", "Package Cache", "regid.1991-06.com.microsoft", "SoftwareDistribution",
        "ssh", "USOPrivate", "USOShared", "Comms", "Desktop", "Documents", "Start Menu", "Templates", "Application Data",
        "MicrosoftEdgeUpdate", "Microsoft OneDrive", "Microsoft Update Health Tools", "WindowsHolographicDevices", "PackageManagement",
        "Amnesia", "NVIDIA", "NVIDIA Corporation", "Intel", "AMD", "Realtek", "Qualcomm", "VMware", "Parallels", "UTM", "SPICE Guest Tools",
        "Oracle", "VirtualBox Guest Additions", "Mozilla Maintenance Service", "DriverStore", "Temp", "Logs", "Users", "Public",
        "Wow6432Node", "Classes", "Policies", "Clients", "RegisteredApplications", "AppDataLow", "ODBC", "Khronos", "Chromium",
        "Google", "Partner", "Unknown", "Mozilla",
    };

    /// <summary>"Visual Studio Code" and "VSCode-x64 1.2" → letters and digits only, lower case, no version numbers.</summary>
    public static string Norm(string s)
    {
        var w = s.ToLowerInvariant();
        foreach (var junk in new[] { "(x64)", "(x86)", "x64", "x86", "64-bit", "32-bit", "arm64", ", inc.", " inc.", " inc", " llc", " ltd", " gmbh", " corporation", " corp.", " corp", " software", " technologies", " co." })
            w = w.Replace(junk, " ");
        var chars = w.Where(char.IsLetterOrDigit).ToArray();
        var n = new string(chars).TrimEnd('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
        return n.Length >= 3 ? n : new string(chars);
    }

    /// <summary>Does a folder (or registry) name belong to one of the installed programs / publishers?</summary>
    public static bool Used(string folderName, IReadOnlyCollection<string> normNames)
    {
        var f = Norm(folderName);
        if (f.Length < 3) return true; // too short to judge: leave it
        foreach (var n in normNames)
        {
            if (n.Length < 3) continue;
            if (f == n || (n.Length >= 4 && f.Contains(n)) || (f.Length >= 4 && n.Contains(f))) return true;
        }
        return false;
    }

    /// <summary>
    /// Folders one level below each root that no installed program uses. names: display names + publishers of installed
    /// programs. locations: their install folders (a folder that holds one is used).
    /// </summary>
    public static List<Leftover> Folders(IEnumerable<string> roots, IEnumerable<string> names, IEnumerable<string> locations)
    {
        var norm = names.Where(n => !string.IsNullOrWhiteSpace(n)).Select(Norm).Where(n => n.Length >= 3).Distinct().ToList();
        var locs = locations.Where(l => !string.IsNullOrWhiteSpace(l)).Select(l => l.TrimEnd('\\', '/')).ToList();
        var list = new List<Leftover>();
        foreach (var root in roots.Where(Directory.Exists))
        {
            IEnumerable<DirectoryInfo> dirs;
            try { dirs = new DirectoryInfo(root).EnumerateDirectories().ToList(); } catch { continue; }
            foreach (var d in dirs.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase))
            {
                if (d.Attributes.HasFlag(FileAttributes.ReparsePoint) || d.Attributes.HasFlag(FileAttributes.System)) continue;
                if (SystemNames.Any(s => s.Equals(d.Name, StringComparison.OrdinalIgnoreCase)) || d.Name.StartsWith('{') || d.Name.StartsWith('.')) continue;
                if (Used(d.Name, norm)) continue;
                var full = d.FullName.TrimEnd('\\', '/');
                if (locs.Any(l => l.Equals(full, StringComparison.OrdinalIgnoreCase) || l.StartsWith(full + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))) continue;
                long bytes = 0; bool exe = false, any = false;
                try
                {
                    var opt = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
                    foreach (var f in d.EnumerateFiles("*", opt).Take(20_000))
                    {
                        any = true; bytes += f.Length;
                        if (f.Extension.Equals(".exe", StringComparison.OrdinalIgnoreCase) || f.Extension.Equals(".dll", StringComparison.OrdinalIgnoreCase) || f.Extension.Equals(".sys", StringComparison.OrdinalIgnoreCase)) exe = true;
                    }
                }
                catch { exe = true; }
                list.Add(new Leftover(full, d.Name, !any, exe, bytes));
            }
        }
        return list;
    }

    /// <summary>Is this a folder Folders() could have offered (one level below one of the roots)? Checked again before deleting.</summary>
    public static bool Allowed(string path, IEnumerable<string> roots)
    {
        try
        {
            var full = Path.GetFullPath(path).TrimEnd('\\', '/');
            var parent = Path.GetDirectoryName(full);
            var name = Path.GetFileName(full);
            if (parent == null || name.Length == 0 || SystemNames.Any(s => s.Equals(name, StringComparison.OrdinalIgnoreCase))) return false;
            if (!roots.Any(r => Path.GetFullPath(r).TrimEnd('\\', '/').Equals(parent, StringComparison.OrdinalIgnoreCase))) return false;
            return Directory.Exists(full) && !new DirectoryInfo(full).Attributes.HasFlag(FileAttributes.ReparsePoint);
        }
        catch { return false; }
    }
}

/// <summary>v0.5 "Remove new apps" also removes settings new programs wrote under HKCU\Software (idea from Pearcleaner and
/// Bulk Crap Uninstaller). Names Windows itself uses are never touched.</summary>
public static class RegNew
{
    public static bool Skip(string name) =>
        Leftovers.SystemNames.Any(s => s.Equals(name, StringComparison.OrdinalIgnoreCase)) || name.Equals("Amnesia", StringComparison.OrdinalIgnoreCase);

    /// <summary>Keys in current that were not there at Turn On (and are not Windows' own).</summary>
    public static List<string> Find(IEnumerable<string> baseline, IEnumerable<string> current)
    {
        var b = baseline.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return current.Where(c => !b.Contains(c) && !Skip(c)).OrderBy(c => c, StringComparer.OrdinalIgnoreCase).ToList();
    }
}

/// <summary>v0.5: an uninstall command from the registry, split into program + arguments. MSI installs get "/X" (remove)
/// instead of "/I" (repair), and quiet = no questions (idea from Bulk Crap Uninstaller).</summary>
public static class UninstallCmd
{
    public static (string Exe, string Args) Parse(string cmd, bool quiet = false)
    {
        cmd = cmd.Trim();
        string exe, args;
        if (cmd.StartsWith('"')) { int e = cmd.IndexOf('"', 1); if (e < 0) e = cmd.Length; exe = cmd[1..e]; args = e < cmd.Length ? cmd[(e + 1)..].Trim() : ""; }
        else
        {
            int e = cmd.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            exe = e > 0 ? cmd[..(e + 4)] : cmd; args = e > 0 ? cmd[(e + 4)..].Trim() : "";
        }
        if (Path.GetFileName(exe).Equals("msiexec.exe", StringComparison.OrdinalIgnoreCase) || exe.Equals("msiexec", StringComparison.OrdinalIgnoreCase))
        {
            var guid = System.Text.RegularExpressions.Regex.Match(args, @"\{[0-9A-Fa-f\-]{36}\}");
            if (guid.Success) args = $"/X{guid.Value}" + (quiet ? " /qb /norestart" : "");
        }
        return (exe, args);
    }
}
