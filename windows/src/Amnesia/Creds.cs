// v0.8 (opt-in, Settings > "Also wipe saved web and app passwords"): the passwords apps saved in Windows' Credential
// Manager (git, VS Code, some chat apps). Off by default: wiping them can sign you out of things you meant to keep.
// What Windows needs for your own sign in, OneDrive and Office is never touched.
using System.Runtime.InteropServices;

namespace Amnesia;

static class Creds
{
    public static bool On => Settings.Get("WIPE_CREDS") == "1";

    // never these (your Microsoft account, OneDrive, Office, Windows Hello, device sign in)
    static readonly string[] Never =
    {
        "MicrosoftAccount", "WindowsLive", "OneDrive", "MicrosoftOffice", "virtualapp/didlogical", "SSO_POP_Device",
        "SSO_POP_User", "MicrosoftAccount:", "Microsoft_OC", "msteams", "AzureAD", "XboxLive", "WindowsHello", "Amnesia",
    };

    const int CRED_TYPE_GENERIC = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL
    {
        public int Flags, Type;
        public string TargetName, Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist, AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias, UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredEnumerate(string? filter, int flags, out int count, out IntPtr creds);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredDelete(string target, int type, int flags);
    [DllImport("advapi32.dll")] static extern void CredFree(IntPtr p);

    /// <summary>The saved app passwords that would go (names only, never the passwords).</summary>
    public static List<string> List()
    {
        var list = new List<string>();
        if (!CredEnumerate(null, 0, out var n, out var p)) return list;
        try
        {
            for (int i = 0; i < n; i++)
            {
                var c = Marshal.PtrToStructure<CREDENTIAL>(Marshal.ReadIntPtr(p, i * IntPtr.Size));
                if (c.Type != CRED_TYPE_GENERIC || string.IsNullOrEmpty(c.TargetName)) continue;
                if (Never.Any(x => c.TargetName.Contains(x, StringComparison.OrdinalIgnoreCase))) continue;
                list.Add(c.TargetName);
            }
        }
        finally { CredFree(p); }
        return list;
    }

    public static int Wipe()
    {
        int n = 0;
        foreach (var t in List()) if (CredDelete(t, CRED_TYPE_GENERIC, 0)) n++;
        return n;
    }
}
