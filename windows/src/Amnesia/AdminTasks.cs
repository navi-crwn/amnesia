// v0.4 "Windows protections" (Settings → Advanced). These are Windows' own switches for the whole PC, so they need
// administrator rights: Amnesia starts a copy of itself with "--admin ..." and Windows asks you once (UAC).
//   pagefile  Windows empties the page file (memory swapped to disk) at every shut down
//   hiber     no hibernation file (a copy of the memory on disk)
//   recall    Windows Recall stops saving screenshots of your screen (Copilot+ PCs)
//   activity  Windows stops keeping an activity history (Timeline)
//   v0.5 (values from Win11Debloat, MIT; ideas from privacy.sexy and BleachBit):
//   copilot   Copilot off for every user
//   telemetry Windows sends the least diagnostic data the edition allows
//   sysclean  one time: empty Prefetch (list of programs run), Windows\Temp, crash reports and memory dumps
//   leftovers one time: delete the leftover folders you picked (Find leftovers)
//   v0.7: labon:<folder>  lab lock: copy lab.conf + keep.conf into %ProgramData%\Amnesia\lab (admins only) + HKLM Run
//         laboff          lab lock off: remove that folder and the HKLM Run entry
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace Amnesia;

static class AdminTasks
{
    const string MemKey = @"SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management";
    const string PowerKey = @"SYSTEM\CurrentControlSet\Control\Power";
    const string AiKey = @"SOFTWARE\Policies\Microsoft\Windows\WindowsAI";
    const string SysKey = @"SOFTWARE\Policies\Microsoft\Windows\System";
    const string CopilotKey = @"SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot";
    const string DataKey = @"SOFTWARE\Policies\Microsoft\Windows\DataCollection";

    static int? Read(string key, string name)
    {
        try { using var k = Registry.LocalMachine.OpenSubKey(key); return k?.GetValue(name) as int?; } catch { return null; }
    }

    /// <summary>What is switched on now (readable without admin).</summary>
    public static Dictionary<string, bool> Status() => new()
    {
        ["pagefile"] = Read(MemKey, "ClearPageFileAtShutdown") == 1,
        ["hiber"] = Read(PowerKey, "HibernateEnabled") == 0,
        ["recall"] = Read(AiKey, "DisableAIDataAnalysis") == 1,
        ["activity"] = Read(SysKey, "PublishUserActivities") == 0,
        ["copilot"] = Read(CopilotKey, "TurnOffWindowsCopilot") == 1,
        ["telemetry"] = Read(DataKey, "AllowTelemetry") == 0,
    };

    /// <summary>Asks Windows for admin rights once and applies all four switches. Returns false when you said No.</summary>
    public static bool Apply(Dictionary<string, bool> want)
    {
        return Run(string.Join(',', want.Select(kv => $"{kv.Key}={(kv.Value ? 1 : 0)}")));
    }

    /// <summary>Starts "Amnesia.exe --admin spec" as administrator and waits. False when you said No (or it failed).</summary>
    public static bool Run(string spec)
    {
        try
        {
            var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!, $"--admin \"{spec}\"") { UseShellExecute = true, Verb = "runas" });
            p?.WaitForExit(120_000);
            AppInfo.Trace($"admin switches: {spec} (exit {p?.ExitCode})");
            return p?.ExitCode == 0;
        }
        catch (System.ComponentModel.Win32Exception) { return false; } // "No" in the Windows prompt
    }

    /// <summary>Runs in the elevated copy (Amnesia.exe --admin pagefile=1,hiber=1,...). Returns the exit code.</summary>
    public static int RunElevated(string spec)
    {
        if (spec.StartsWith("labon:")) return LabOn(spec[6..]);
        if (spec == "laboff") return LabOff();
        try
        {
            foreach (var part in spec.Split(',', StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=');
                bool on = kv.Length > 1 && kv[1] == "1";
                switch (kv[0])
                {
                    case "pagefile":
                        using (var k = Registry.LocalMachine.CreateSubKey(MemKey)) k.SetValue("ClearPageFileAtShutdown", on ? 1 : 0, RegistryValueKind.DWord);
                        break;
                    case "hiber":
                        var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("powercfg.exe", on ? "/hibernate off" : "/hibernate on") { CreateNoWindow = true, UseShellExecute = false });
                        p?.WaitForExit(30_000);
                        break;
                    case "recall":
                        using (var k = Registry.LocalMachine.CreateSubKey(AiKey))
                        {
                            // v0.5: also "Recall can't be switched on" and "no snapshots" (Win11Debloat)
                            if (on) { k.SetValue("DisableAIDataAnalysis", 1, RegistryValueKind.DWord); k.SetValue("AllowRecallEnablement", 0, RegistryValueKind.DWord); k.SetValue("TurnOffSavingSnapshots", 1, RegistryValueKind.DWord); }
                            else foreach (var n in new[] { "DisableAIDataAnalysis", "AllowRecallEnablement", "TurnOffSavingSnapshots" }) k.DeleteValue(n, false);
                        }
                        break;
                    case "copilot":
                        using (var k = Registry.LocalMachine.CreateSubKey(CopilotKey))
                        {
                            if (on) k.SetValue("TurnOffWindowsCopilot", 1, RegistryValueKind.DWord); else k.DeleteValue("TurnOffWindowsCopilot", false);
                        }
                        break;
                    case "telemetry":
                        using (var k = Registry.LocalMachine.CreateSubKey(DataKey))
                        {
                            if (on) k.SetValue("AllowTelemetry", 0, RegistryValueKind.DWord); else k.DeleteValue("AllowTelemetry", false);
                        }
                        break;
                    case "sysclean":
                        if (on) SysClean();
                        break;
                    case "leftovers":
                        DeleteLeftovers(part[(part.IndexOf('=') + 1)..]);
                        break;
                    case "activity":
                        using (var k = Registry.LocalMachine.CreateSubKey(SysKey))
                        {
                            foreach (var n in new[] { "PublishUserActivities", "UploadUserActivities", "EnableActivityFeed" })
                                if (on) k.SetValue(n, 0, RegistryValueKind.DWord); else k.DeleteValue(n, false);
                        }
                        break;
                }
            }
            return 0;
        }
        catch { return 1; }
    }

    const string HklmRun = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

    /// <summary>v0.7 lab lock on (elevated copy). The folder is made fresh with permissions only administrators and
    /// SYSTEM can change (normal users can read), so a user can't edit or delete the lock.</summary>
    static int LabOn(string stage)
    {
        try
        {
            var conf = File.ReadAllLines(Path.Combine(stage, "lab.conf"));
            var exe = conf.FirstOrDefault(l => l.StartsWith("EXE="))?[4..];
            var root = Path.GetDirectoryName(Core.Lab.Dir)!; // %ProgramData%\Amnesia
            if (Directory.Exists(root)) Directory.Delete(root, true); // also if a user made it first (then they would own it)
            var sec = new DirectorySecurity();
            sec.SetAccessRuleProtection(true, false);
            var inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            sec.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            sec.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), FileSystemRights.ReadAndExecute, inherit, PropagationFlags.None, AccessControlType.Allow));
            new DirectoryInfo(root).Create(sec);
            Directory.CreateDirectory(Core.Lab.Dir);
            File.Copy(Path.Combine(stage, "keep.conf"), Core.Lab.KeepFile, true);
            File.Copy(Path.Combine(stage, "lab.conf"), Core.Lab.ConfFile, true); // last: this file is what switches the lock on
            if (!string.IsNullOrEmpty(exe))
                using (var k = Registry.LocalMachine.CreateSubKey(HklmRun)) k.SetValue("Amnesia", $"\"{exe}\" --login");
            return 0;
        }
        catch { return 1; }
    }

    static int LabOff()
    {
        try
        {
            var root = Path.GetDirectoryName(Core.Lab.Dir)!;
            if (Directory.Exists(root)) Directory.Delete(root, true);
            using (var k = Registry.LocalMachine.OpenSubKey(HklmRun, writable: true)) k?.DeleteValue("Amnesia", false);
            return 0;
        }
        catch { return 1; }
    }

    /// <summary>Windows' own trace folders outside your user folder (needs admin). Files in use are skipped.</summary>
    static void SysClean()
    {
        var win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var data = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        void Empty(string dir, string pattern = "*")
        {
            if (!Directory.Exists(dir)) return;
            foreach (var f in Directory.EnumerateFileSystemEntries(dir, pattern).ToList())
                try { Core.CleanEngine.Delete(f); } catch { }
        }
        Empty(Path.Combine(win, "Prefetch"), "*.pf");          // which programs ran, and when (Windows rebuilds it)
        Empty(Path.Combine(win, "Temp"));
        Empty(Path.Combine(win, "Minidump"));                  // crash memory dumps
        try { File.Delete(Path.Combine(win, "MEMORY.DMP")); } catch { }
        Empty(Path.Combine(data, @"Microsoft\Windows\WER\ReportArchive"));
        Empty(Path.Combine(data, @"Microsoft\Windows\WER\ReportQueue"));
    }

    /// <summary>The folders you picked in Find leftovers. Checked again here: only folders one level below Program Files
    /// or ProgramData, never Windows' own.</summary>
    static void DeleteLeftovers(string listFile)
    {
        var roots = Apps.LeftoverRoots();
        // v0.8: only the list Amnesia itself writes (.amnesia\leftovers-delete.txt; with another admin account typed in the
        // Windows prompt that is in the other user's folder), never any file named on the command line
        var full = Path.GetFullPath(listFile);
        if (!Path.GetFileName(full).Equals("leftovers-delete.txt", StringComparison.OrdinalIgnoreCase)
            || !string.Equals(Path.GetFileName(Path.GetDirectoryName(full)), ".amnesia", StringComparison.OrdinalIgnoreCase)
            || new FileInfo(full).Attributes.HasFlag(FileAttributes.ReparsePoint) || new FileInfo(full).Length > 1 << 20)
        {
            AppInfo.Trace("admin: leftovers list refused (not Amnesia's own file)");
            return;
        }
        foreach (var f in File.ReadAllLines(full))
            if (Core.Leftovers.Allowed(f, roots))
                try { Core.CleanEngine.Delete(f); } catch { }
    }
}
