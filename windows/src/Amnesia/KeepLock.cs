// v0.7 Keep lock (Settings → Advanced → Keep lock). The Keep folder only opens through Amnesia, with its own password.
// How: Windows' folder permissions. Locking adds a "deny" entry for your Windows user to the Keep folder, so Explorer
// and other apps get "Access denied". Opening Keep in Amnesia (tray, Desktop shortcut, Settings) asks the password and
// removes that entry for a while. It locks again when you lock the screen (Win+L), after N minutes, at sign out and
// at sign in. Amnesia opens it for a moment itself for backups, Doomsday and "Collect log".
// Honest limits: the files are not encrypted (use BitLocker for that), and anyone signed in as you who knows how can
// remove the entry in the folder's Properties → Security, because the folder is yours. An administrator can too.
// v0.7.1: the deny entry on the Keep folder itself made Keep\desktop.ini (the Keep icon) unreadable. Keep is pinned in
// Quick access, so Explorer tried again and again (icon cache 1 → 84 MB in 5 minutes, flicker). Now the lock is on what is
// INSIDE Keep: the folder itself can still be listed and its icon read (desktop.ini gets its own "allow read"), the files
// and folders in it can't be opened, changed or deleted, and nothing new can be written into it, by any program. While it
// is locked Keep is also taken out of Quick access (pinned again when you open it), and Explorer is told after each change.
using System.Security.AccessControl;
using System.Security.Principal;
using Amnesia.Core;

namespace Amnesia;

static class KeepLock
{
    // what is inside Keep (files and folders below it, not Keep itself)
    const FileSystemRights Denied = FileSystemRights.ReadData | FileSystemRights.WriteData | FileSystemRights.AppendData
        | FileSystemRights.ExecuteFile | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ReadExtendedAttributes
        | FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes | FileSystemRights.Delete;
    // the Keep folder itself: no new files or folders, nothing deleted from it. Listing it and reading its icon stay.
    const FileSystemRights DeniedSelf = FileSystemRights.CreateFiles | FileSystemRights.CreateDirectories
        | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.WriteExtendedAttributes;
    const FileSystemRights IniRead = FileSystemRights.Read | FileSystemRights.Synchronize;
    static readonly object Gate = new();
    static System.Threading.Timer? relock;
    static int borrowed; // > 0 while Amnesia itself uses the folder (backup...)

    public static bool On => Settings.Get("KEEP_LOCK") == "1" && Settings.Get("KEEP_LOCK_PW") != null;
    public static int Minutes => Conf.Int("KEEP_LOCK_MIN", 15) is var m && m is >= 1 and <= 240 ? m : 15;

    static SecurityIdentifier Me => WindowsIdentity.GetCurrent().User!;
    static FileSystemAccessRule Rule() => new(Me, Denied, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.InheritOnly, AccessControlType.Deny);
    static FileSystemAccessRule RuleSelf() => new(Me, DeniedSelf, InheritanceFlags.None, PropagationFlags.None, AccessControlType.Deny);
    static string Ini => Path.Combine(Settings.KeepDir, "desktop.ini");

    public static bool IsLocked
    {
        get
        {
            try
            {
                var dir = new DirectoryInfo(Settings.KeepDir);
                if (!dir.Exists) return false;
                foreach (FileSystemAccessRule r in dir.GetAccessControl().GetAccessRules(true, false, typeof(SecurityIdentifier)))
                    if (r.AccessControlType == AccessControlType.Deny && r.IdentityReference.Equals(Me) && (r.FileSystemRights & FileSystemRights.ReadData) != 0) return true;
            }
            catch { }
            return false;
        }
    }

    /// <summary>A lock made by v0.7.0: the deny entry is on the Keep folder itself (not "inside only").</summary>
    static bool OldStyle(DirectorySecurity sec)
    {
        foreach (FileSystemAccessRule r in sec.GetAccessRules(true, false, typeof(SecurityIdentifier)))
            if (r.AccessControlType == AccessControlType.Deny && r.IdentityReference.Equals(Me) && (r.FileSystemRights & FileSystemRights.ReadData) != 0
                && (r.PropagationFlags & PropagationFlags.InheritOnly) == 0) return true;
        return false;
    }

    /// <summary>Locks the folder now (when the Keep lock is on). Safe to call often. links: also take Keep out of
    /// Quick access (not at sign out: Windows forgets the pin anyway).</summary>
    public static void Lock(string why, bool links = true)
    {
        if (!On) return;
        bool done;
        lock (Gate)
        {
            if (borrowed > 0) return; // a backup is reading it; it locks again when that is done
            relock?.Dispose(); relock = null;
            done = LockNow(why);
        }
        if (done && links) KeepLinks.SyncPin();
    }

    /// <summary>Adds the deny entries (inside Keep + Keep itself) and the "allow read" on desktop.ini. True when it changed.</summary>
    static bool LockNow(string why)
    {
        try
        {
            var dir = new DirectoryInfo(Settings.KeepDir);
            dir.Create();
            var sec = dir.GetAccessControl();
            if (IsLocked)
            {
                if (!OldStyle(sec)) return false;
                sec.RemoveAccessRuleAll(new FileSystemAccessRule(Me, Denied, AccessControlType.Deny)); // v0.7.0 lock: redone
            }
            // the icon first, while the folder is still open
            if (File.Exists(Ini))
            {
                var fi = new FileInfo(Ini);
                var fs = fi.GetAccessControl();
                fs.AddAccessRule(new FileSystemAccessRule(Me, IniRead, AccessControlType.Allow));
                fi.SetAccessControl(fs);
            }
            sec.AddAccessRule(Rule());
            sec.AddAccessRule(RuleSelf());
            dir.SetAccessControl(sec);
            AppInfo.Trace($"keep locked ({why})");
            KeepLinks.Notify(dir.FullName);
            return true;
        }
        catch (Exception e) { AppInfo.Trace($"keep lock failed: {e.GetType().Name}"); return false; }
    }

    static void Unlock()
    {
        lock (Gate)
        {
            try
            {
                var dir = new DirectoryInfo(Settings.KeepDir);
                if (!dir.Exists) return;
                var sec = dir.GetAccessControl();
                sec.RemoveAccessRuleAll(new FileSystemAccessRule(Me, Denied, AccessControlType.Deny)); // every deny entry of yours
                dir.SetAccessControl(sec);
                if (File.Exists(Ini))
                {
                    var fi = new FileInfo(Ini);
                    var fs = fi.GetAccessControl();
                    fs.RemoveAccessRuleSpecific(new FileSystemAccessRule(Me, IniRead, AccessControlType.Allow));
                    fi.SetAccessControl(fs);
                }
                KeepLinks.Notify(dir.FullName);
            }
            catch (Exception e) { AppInfo.Trace($"keep unlock failed: {e.GetType().Name}"); }
        }
    }

    /// <summary>Opens the folder for you after the password, and locks it again after the chosen minutes.</summary>
    public static bool UnlockFor(string password)
    {
        if (!Pin.Verify(password, Settings.Get("KEEP_LOCK_PW"))) return false;
        Unlock();
        lock (Gate) { relock?.Dispose(); relock = new System.Threading.Timer(_ => Lock("time is up"), null, TimeSpan.FromMinutes(Minutes), Timeout.InfiniteTimeSpan); }
        AppInfo.Trace($"keep opened for {Minutes} min");
        KeepLinks.SyncPin(); // back in Quick access while it is open
        return true;
    }

    /// <summary>Amnesia itself needs the folder for a moment (backup, Doomsday, Collect log).</summary>
    public static T With<T>(Func<T> work)
    {
        bool was;
        lock (Gate) { was = On && IsLocked; borrowed++; }
        if (was) Unlock();
        try { return work(); }
        finally
        {
            // locked again as it was, without touching the Quick access pin (Amnesia only borrowed it)
            lock (Gate) { borrowed--; if (was && borrowed == 0 && On) LockNow("done"); }
        }
    }
    public static void With(Action work) => With(() => { work(); return 0; });

    public static void TurnOn(string password, int minutes)
    {
        if (!Pin.GoodPassword(password)) throw new InvalidOperationException("keeplock-short");
        Settings.Set("KEEP_LOCK_PW", Pin.Hash(password));
        Settings.Set("KEEP_LOCK_MIN", Math.Clamp(minutes, 1, 240).ToString());
        Settings.Set("KEEP_LOCK", "1");
        Lock("turned on");
        KeepLinks.Sync(); // the Desktop shortcut now opens Amnesia, which asks the password
    }

    public static void TurnOff(string password)
    {
        if (!Pin.Verify(password, Settings.Get("KEEP_LOCK_PW"))) throw new InvalidOperationException("keeplock-wrong");
        lock (Gate) { relock?.Dispose(); relock = null; }
        Unlock();
        Settings.Set("KEEP_LOCK", null); Settings.Set("KEEP_LOCK_PW", null);
        AppInfo.Trace("keep lock turned off");
        KeepLinks.Sync();
    }

    /// <summary>Tray, Desktop shortcut, "Open Keep": asks the password when the folder is locked.</summary>
    public static void OpenWithPrompt(IWin32Window? owner = null)
    {
        if (On && IsLocked)
        {
            var pw = PinPrompt.Ask(owner, Text2.KeepLockTitle, Text2.KeepLockAsk, digitsOnly: false, check: UnlockFor);
            if (pw == null) return;
        }
        KeepLinks.OpenKeep();
    }
}
