// v0.5.1: which programs hold a file open (Windows Restart Manager, the same thing Windows uses for "files in use").
// Used when a vault restore cannot swap an app's folder, so Amnesia can close the right program and say which one it was.
using System.Runtime.InteropServices;

namespace Amnesia.Core;

public static class Locks
{
    /// <summary>Process ids and names that hold one of these files open. Empty on other systems or when Windows cannot tell.</summary>
    public static List<(int Pid, string Name)> Holders(IEnumerable<string> files)
    {
        var found = new List<(int, string)>();
        if (!OperatingSystem.IsWindows()) return found;
        var list = files.Take(200).ToArray();
        if (list.Length == 0) return found;
        uint session = 0;
        try
        {
            if (RmStartSession(out session, 0, Guid.NewGuid().ToString("N")) != 0) return found;
            if (RmRegisterResources(session, (uint)list.Length, list, 0, null, 0, null) != 0) return found;
            uint need = 0, have = 0, reasons = 0;
            var r = RmGetList(session, out need, ref have, null, ref reasons);
            if (r != 234 || need == 0) return found; // 234 = more data: there is something to read
            var info = new RM_PROCESS_INFO[need];
            have = need;
            if (RmGetList(session, out need, ref have, info, ref reasons) != 0) return found;
            for (int i = 0; i < have; i++)
            {
                var pid = info[i].Process.dwProcessId;
                string name;
                try { name = System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch { name = info[i].strAppName; }
                if (!found.Any(f => f.Item1 == pid)) found.Add((pid, name));
            }
        }
        catch { }
        finally { if (session != 0) try { RmEndSession(session); } catch { } }
        return found;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO
    {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
        public int ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications,
        RM_UNIQUE_PROCESS[]? rgApplications, uint nServices, string[]? rgsServiceNames);
    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo,
        [In, Out] RM_PROCESS_INFO[]? rgAffectedApps, ref uint lpdwRebootReasons);
}
