// v0.9 Care: the Windows-only parts (Core\Care.cs has the rules and the lists). Recycle Bin, programs from the registry,
// restarting Explorer, opening Windows Settings, and memory / battery for the Health check. Nothing here needs admin.
using System.Runtime.InteropServices;
using Amnesia.Core;
using Microsoft.Win32;

namespace Amnesia;

sealed record CareProgram(string Id, string Kind, string Name, string? Publisher, string? Version, long Kb, bool CanUninstall);

static class CareWin
{
    const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall";

    // ---------- Recycle Bin ----------
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref SHFILEOPSTRUCT op);

    [StructLayout(LayoutKind.Sequential)]
    struct SHQUERYRBINFO { public int cbSize; public long i64Size; public long i64NumItems; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHQueryRecycleBin(string? root, ref SHQUERYRBINFO info);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHEmptyRecycleBin(IntPtr hwnd, string? root, uint flags);

    const uint FO_DELETE = 3;
    const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40, FOF_NOERRORUI = 0x400, FOF_WANTNUKEWARNING = 0x4000;

    /// <summary>Moves one file or folder to the Recycle Bin. When Windows can't recycle it (too big for the bin, or a
    /// drive without one), it asks you first instead of deleting for good (FOF_WANTNUKEWARNING). In use = false.</summary>
    public static bool Recycle(string full)
    {
        if (Core.Home.Test) return false; // the tests have their own fake bin
        bool ok = false;
        Sta(() =>
        {
            var op = new SHFILEOPSTRUCT
            {
                wFunc = FO_DELETE,
                pFrom = full.TrimEnd('\\') + "\0\0",
                fFlags = (ushort)(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_WANTNUKEWARNING),
            };
            ok = SHFileOperation(ref op) == 0 && !op.fAnyOperationsAborted;
        });
        return ok && !File.Exists(full) && !Directory.Exists(full);
    }

    /// <summary>Bytes in the Recycle Bin of all drives (-1 = not known).</summary>
    public static long BinSize()
    {
        if (Core.Home.Test) return -1;
        try
        {
            var i = new SHQUERYRBINFO { cbSize = Marshal.SizeOf<SHQUERYRBINFO>() };
            return SHQueryRecycleBin(null, ref i) == 0 ? i.i64Size : -1;
        }
        catch { return -1; }
    }

    /// <summary>Empties the Recycle Bin for good (no question, no progress window, no sound).</summary>
    public static bool EmptyBin()
    {
        if (Core.Home.Test) return false;
        try
        {
            int hr = SHEmptyRecycleBin(IntPtr.Zero, null, 0x1 | 0x2 | 0x4);
            return hr == 0 || BinSize() == 0;
        }
        catch { return false; }
    }

    static void Sta(Action a)
    {
        var t = new Thread(() => { try { a(); } catch { } });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
    }

    /// <summary>The Care rules with the Windows parts plugged in.</summary>
    public static Care NewCare() => new() { Recycle = Recycle, EmptyBin = EmptyBin, BinSize = BinSize, CloudRoots = Cleaner.CloudRoots };

    // ---------- programs ----------
    /// <summary>Installed programs: just for you (Amnesia can run their own uninstaller), for everyone and from the
    /// Microsoft Store (those open Windows Settings, Amnesia never removes them). Amnesia itself is never listed.</summary>
    public static List<CareProgram> Programs()
    {
        var list = new List<CareProgram>();
        void Read(RegistryKey root, string path, string kind)
        {
            try
            {
                using var k = root.OpenSubKey(path);
                foreach (var sub in k?.GetSubKeyNames() ?? Array.Empty<string>())
                {
                    using var s = k!.OpenSubKey(sub);
                    var name = (s?.GetValue("DisplayName") as string)?.Trim();
                    if (string.IsNullOrEmpty(name) || s!.GetValue("SystemComponent") is int sc && sc == 1 || s.GetValue("ParentKeyName") != null) continue;
                    if (name.Contains("Amnesia", StringComparison.OrdinalIgnoreCase)) continue;
                    var un = s.GetValue("UninstallString") as string;
                    long kb = s.GetValue("EstimatedSize") is int e && e > 0 ? e : 0;
                    list.Add(new CareProgram($"{kind}:{sub}", kind, name, s.GetValue("Publisher") as string, s.GetValue("DisplayVersion") as string, kb,
                        kind == "user" && !string.IsNullOrWhiteSpace(un)));
                }
            }
            catch (Exception e) { AppInfo.Trace($"care: program list part failed ({e.GetType().Name})"); }
        }
        Read(Registry.CurrentUser, UninstallKey, "user");
        Read(Registry.LocalMachine, UninstallKey, "machine");
        Read(Registry.LocalMachine, @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", "machine");
        try
        {
            foreach (var p in new Windows.Management.Deployment.PackageManager().FindPackagesForUser(string.Empty))
            {
                if (p.IsFramework || p.IsResourcePackage || p.SignatureKind == Windows.ApplicationModel.PackageSignatureKind.System) continue;
                var fam = p.Id.FamilyName;
                if (CleanEngine.StoreSystem(fam)) continue;
                string name; try { name = p.DisplayName; } catch { name = p.Id.Name; }
                if (string.IsNullOrWhiteSpace(name) || name.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase)) name = p.Id.Name;
                string? pub = null; try { pub = p.PublisherDisplayName; } catch { }
                list.Add(new CareProgram($"store:{fam}", "store", name, pub, $"{p.Id.Version.Major}.{p.Id.Version.Minor}.{p.Id.Version.Build}", 0, false));
            }
        }
        catch (Exception e) { AppInfo.Trace($"care: store app list failed ({e.GetType().Name})"); }
        // the same program listed twice (32 and 64 bit): once
        return list.GroupBy(p => (p.Kind, p.Name.ToLowerInvariant())).Select(g => g.First())
            .OrderBy(p => p.Kind == "user" ? 0 : 1).ThenBy(p => p.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// <summary>Runs the program's own uninstaller (just-for-you programs only, no admin) and waits for it.
    /// gone = the program is no longer listed afterwards.</summary>
    public static (bool gone, CareProgram app) Uninstall(string id)
    {
        if (!id.StartsWith("user:", StringComparison.Ordinal)) throw new InvalidOperationException("care-not-user");
        var app = Programs().FirstOrDefault(p => p.Id == id && p.CanUninstall) ?? throw new InvalidOperationException("care-not-found");
        Apps.RunUninstaller(id);
        bool gone;
        using (var k = Registry.CurrentUser.OpenSubKey($@"{UninstallKey}\{id[5..]}")) gone = k == null;
        AppInfo.Trace($"care: uninstall finished ({(gone ? "gone" : "still listed")})");
        return (gone, app);
    }

    // ---------- tune-ups and links ----------
    /// <summary>Restarts Explorer for this session only (taskbar, Desktop, open folder windows). Windows usually starts it
    /// again by itself; if not, Amnesia does after 5 seconds.</summary>
    public static bool RestartExplorer()
    {
        try
        {
            var me = System.Diagnostics.Process.GetCurrentProcess().SessionId;
            var mine = System.Diagnostics.Process.GetProcessesByName("explorer").Where(p => p.SessionId == me).ToList();
            foreach (var p in mine)
            {
                try { p.Kill(); p.WaitForExit(5000); } catch { }
                p.Dispose();
            }
            for (int i = 0; i < 10; i++)
            {
                Thread.Sleep(500);
                if (System.Diagnostics.Process.GetProcessesByName("explorer").Any(p => p.SessionId == me)) return true;
            }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe") { UseShellExecute = true });
            return true;
        }
        catch (Exception e) { AppInfo.Trace($"care: explorer restart failed ({e.GetType().Name})"); return false; }
    }

    /// <summary>Windows Settings pages Care links to. Only these.</summary>
    public static void Open(string target)
    {
        var uri = target switch
        {
            "appsfeatures" => "ms-settings:appsfeatures",
            "startupapps" => "ms-settings:startupapps",
            "storagesense" => "ms-settings:storagesense",
            _ => throw new InvalidOperationException("unknown link"),
        };
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
    }

    /// <summary>Shows a file or folder in Explorer (selected). Only inside the user folder or Keep, never opens it.</summary>
    public static void Reveal(string rel)
    {
        var full = Path.GetFullPath(Core.Home.Full(rel));
        var r = Care.RelOf(full);
        if (r == null || r.Length == 0 || (!File.Exists(full) && !Directory.Exists(full))) throw new InvalidOperationException("care-gone");
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{full}\"") { UseShellExecute = true });
    }

    // ---------- memory and battery (Health check) ----------
    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);

    /// <summary>Memory in use (percent) and the total (bytes), or null when Windows did not say.</summary>
    public static (int used, ulong total)? Memory()
    {
        try
        {
            var m = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
            return GlobalMemoryStatusEx(ref m) ? ((int)m.dwMemoryLoad, m.ullTotalPhys) : null;
        }
        catch { return null; }
    }

    /// <summary>Battery charge (percent) and whether it is charging; null = no battery; throws when Windows can't tell.</summary>
    public static (int percent, bool charging)? Battery()
    {
        var s = SystemInformation.PowerStatus;
        if (s.BatteryChargeStatus.HasFlag(BatteryChargeStatus.NoSystemBattery)) return null;
        if (s.BatteryChargeStatus.HasFlag(BatteryChargeStatus.Unknown) || s.BatteryLifePercent > 1f) throw new InvalidOperationException("unknown");
        return ((int)Math.Round(s.BatteryLifePercent * 100), s.PowerLineStatus == PowerLineStatus.Online);
    }
}
