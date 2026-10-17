// Backup (v0.4): your Keep folder, Keep List and vault in one locked file, amnesia_backup_YYYY-MM-DD_HHMMSS.amb.
// Locked with the vault's key, so automatic backups need no password and opening one needs your vault password.
// Goes to a folder (USB drive, or a cloud folder such as OneDrive / Google Drive for desktop) or to your server over SSH.
// Old backups are never deleted by Amnesia. "Move to a new PC" opens a backup there and puts everything back.
// v0.8: files that could not be read (in use) are counted and shown, no more quiet "done" (HIGH-X-02). A restore
// unpacks into .amnesia (never Temp), with a file that deletes itself when closed, and the vault you have is only
// replaced once the one from the backup is completely unpacked (HIGH-WIN-05, HIGH-X-01). Older backups inside Keep
// are left out of a new one, so a backup folder in Keep doesn't grow forever.
using System.IO.Compression;

namespace Amnesia.Core;

public static class Backup
{
    public const string Prefix = "amnesia_backup_", Ext = ".amb";
    // settings that travel with a backup (never ENABLED or APP_PATH: the new PC turns Amnesia on itself)
    static readonly string[] CarrySettings = { "LANG", "VAULT_APPS", "VAULT_FOLDERS", "KEEP_SHORTCUT", "KEEP_PIN", "DOOMSDAY" };

    /// <summary>Uploads a finished file to the SSH server (given by Amnesia.exe: scp.exe, built into Windows).</summary>
    public static Func<string, CancellationToken, string?>? Upload { get; set; }

    public static string Kind => Conf.Get("BACKUP_KIND") ?? "folder";
    public static string? Folder => Conf.Get("BACKUP_DEST");
    /// <summary>v0.8: files the last backup could not read (in use or refused). 0 = everything went in.</summary>
    public static int LastSkipped { get; private set; }

    /// <summary>Makes a backup. Returns where it went.</summary>
    public static string Create(Action<double, string>? progress = null, CancellationToken cancel = default)
    {
        if (!Vault.Exists) throw new VaultError("no-vault");
        bool ssh = Kind == "ssh";
        string dir;
        if (ssh) dir = Path.Combine(Path.GetTempPath(), "Amnesia-backup");
        else
        {
            dir = Folder ?? throw new InvalidOperationException("no-destination");
            if (!Directory.Exists(dir)) throw new DirectoryNotFoundException("destination-missing");
        }
        Directory.CreateDirectory(dir);
        var name = $"{Prefix}{DateTime.Now:yyyy-MM-dd_HHmmss}{Ext}";
        var final = Path.Combine(dir, name);
        var part = final + ".partial";
        var files = Collect();
        long total = Math.Max(1, files.Sum(f => f.size)), done = 0;
        int skipped = 0;
        try
        {
            using (var file = File.Create(part))
            using (var locked = Crypto.Writer(file, Crypto.KindBackup, File.ReadAllBytes(Path.Combine(Home.Dir, "vault", "public.key")),
                       File.ReadAllBytes(Path.Combine(Home.Dir, "vault", "private.key"))))
            using (var zip = new ZipArchive(locked, ZipArchiveMode.Create))
            {
                foreach (var (full, entry, size) in files)
                {
                    cancel.ThrowIfCancellationRequested();
                    progress?.Invoke(0.95 * done / total, entry.StartsWith("Keep/") ? "keep" : "vault");
                    try
                    {
                        using var src = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                        var e = zip.CreateEntry(entry, entry.StartsWith("amnesia/vault/") ? CompressionLevel.NoCompression : CompressionLevel.Fastest);
                        e.LastWriteTime = File.GetLastWriteTime(full);
                        using var dst = e.Open();
                        src.CopyTo(dst);
                    }
                    catch (IOException) { skipped++; }
                    catch (UnauthorizedAccessException) { skipped++; }
                    done += size;
                }
            }
            File.Move(part, final, overwrite: true);
        }
        finally { try { File.Delete(part); } catch { } }

        string where = final;
        if (ssh)
        {
            progress?.Invoke(0.96, "upload");
            try
            {
                var err = Upload?.Invoke(final, cancel) ?? "no-ssh";
                if (err != null) throw new IOException(err);
                where = (Conf.Get("BACKUP_SSH") ?? "") + "/" + name;
            }
            finally { try { File.Delete(final); } catch { } }
        }
        Conf.Set("BACKUP_LAST", DateTime.Now.ToString("yyyy-MM-dd HH:mm"));
        LastSkipped = skipped;
        if (skipped > 0) Home.Trace("backup", $"{skipped} file(s) could not be read (in use) and are not in this backup");
        Home.History("backup", (ssh ? "ssh" : "folder") + (skipped > 0 ? $" {skipped}" : ""));
        progress?.Invoke(1, "");
        return where;
    }

    /// <summary>What goes in: the Keep folder, keep.conf, settings.conf and the vault (not its temp folders).</summary>
    static List<(string full, string entry, long size)> Collect()
    {
        var list = new List<(string, string, long)>();
        var opt = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        var keep = Conf.KeepDir;
        if (Directory.Exists(keep))
            foreach (var f in new DirectoryInfo(keep).EnumerateFiles("*", opt))
            {
                // older backups in Keep would end up inside every new one
                if (f.Name.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) && (f.Name.EndsWith(Ext, StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".partial", StringComparison.OrdinalIgnoreCase))) continue;
                list.Add((f.FullName, "Keep/" + Path.GetRelativePath(keep, f.FullName).Replace('\\', '/'), f.Length));
            }
        foreach (var n in new[] { "keep.conf", "settings.conf" })
        {
            var f = new FileInfo(Path.Combine(Home.Dir, n));
            if (f.Exists) list.Add((f.FullName, "amnesia/" + n, f.Length));
        }
        var v = Path.Combine(Home.Dir, "vault");
        if (Directory.Exists(v))
            foreach (var f in new DirectoryInfo(v).EnumerateFiles("*", opt))
            {
                var rel = Path.GetRelativePath(v, f.FullName).Replace('\\', '/');
                if (rel.StartsWith(".tmp/") || rel.StartsWith(".stage/") || rel.EndsWith(".new")) continue;
                list.Add((f.FullName, "amnesia/vault/" + rel, f.Length));
            }
        // v0.8: the Safe box (still locked) goes along too
        foreach (var n in new[] { "public.key", "private.key", "safe.ams" })
        {
            var f = new FileInfo(Path.Combine(Home.Dir, "safe", n));
            if (f.Exists) list.Add((f.FullName, "amnesia/safe/" + n, f.Length));
        }
        return list;
    }

    /// <summary>Backups in the backup folder, newest first.</summary>
    public static List<FileInfo> List()
    {
        var d = Folder;
        if (Kind != "folder" || d == null || !Directory.Exists(d)) return new List<FileInfo>();
        return new DirectoryInfo(d).EnumerateFiles(Prefix + "*" + Ext).OrderByDescending(f => f.Name).ToList();
    }

    /// <summary>True when an automatic backup is due (BACKUP_EVERY = day / week) and the destination is there.</summary>
    public static bool Due()
    {
        var every = Conf.Get("BACKUP_EVERY");
        if (every is not ("day" or "week") || !Vault.Exists) return false;
        if (Kind == "folder" && (Folder == null || !Directory.Exists(Folder))) return false;
        if (Kind == "ssh" && string.IsNullOrEmpty(Conf.Get("BACKUP_SSH"))) return false;
        if (!DateTime.TryParse(Conf.Get("BACKUP_LAST"), out var last)) return true;
        return DateTime.Now - last >= (every == "day" ? TimeSpan.FromHours(23) : TimeSpan.FromDays(6.9));
    }

    /// <summary>Move to a new PC: opens a backup with the vault password and puts the Keep folder, Keep List, settings and
    /// vault back. Files already in Keep with the same name are replaced by the ones from the backup.</summary>
    public static int Restore(string file, string password, Action<double, string>? progress = null, CancellationToken cancel = default)
    {
        var (kind, lockedPriv) = Crypto.Peek(file);
        if (kind != Crypto.KindBackup || lockedPriv.Length == 0) throw new InvalidDataException("not-a-backup");
        System.Security.Cryptography.RSA rsa;
        try { rsa = Crypto.Unlock(lockedPriv, password); }
        catch (System.Security.Cryptography.CryptographicException) { throw new VaultError("wrong", -1); }
        Directory.CreateDirectory(Home.Dir);
        Sweep();
        var tmpZip = Path.Combine(Home.Dir, ".restore-" + Guid.NewGuid().ToString("N") + ".zip");
        var vaultDir = Path.Combine(Home.Dir, "vault");
        var incoming = vaultDir + ".incoming";
        int count = 0;
        // deleted by Windows as soon as it is closed, also when Amnesia crashes
        using (var o = new FileStream(tmpZip, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None, 1 << 16, FileOptions.DeleteOnClose))
        {
            using (rsa) Crypto.Open(file, rsa, o, p => progress?.Invoke(0.5 * p, "open"), cancel);
            o.Position = 0;
            var keep = Conf.KeepDir;
            using var zip = new ZipArchive(o, ZipArchiveMode.Read, leaveOpen: true);
            bool hasVault = zip.Entries.Any(e => e.FullName.StartsWith("amnesia/vault/"));
            // v0.8: a Safe box from the backup only when this PC has none (never over a newer one)
            var safeDir = Path.Combine(Home.Dir, "safe");
            bool takeSafe = !Safe.Exists;
            CleanEngine.Delete(incoming);
            int i = 0;
            foreach (var e in zip.Entries)
            {
                cancel.ThrowIfCancellationRequested();
                progress?.Invoke(0.5 + 0.5 * i++ / Math.Max(1, zip.Entries.Count), "put back");
                if (e.FullName.EndsWith('/')) continue;
                string? target = null;
                if (e.FullName.StartsWith("Keep/")) target = Path.Combine(keep, e.FullName[5..].Replace('/', Path.DirectorySeparatorChar));
                else if (e.FullName.StartsWith("amnesia/vault/")) target = Path.Combine(incoming, e.FullName[14..].Replace('/', Path.DirectorySeparatorChar));
                else if (e.FullName.StartsWith("amnesia/safe/") && takeSafe) target = Path.Combine(safeDir, e.FullName[13..].Replace('/', Path.DirectorySeparatorChar));
                else if (e.FullName == "amnesia/keep.conf") { MergeKeepList(e); continue; }
                else if (e.FullName == "amnesia/settings.conf") { MergeSettings(e); continue; }
                if (target == null) continue;
                // never outside the Keep / vault folder (a damaged or crafted file can't write elsewhere)
                var root = e.FullName.StartsWith("Keep/") ? keep : e.FullName.StartsWith("amnesia/safe/") ? safeDir : incoming;
                var full = Path.GetFullPath(target);
                if (!full.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;
                Directory.CreateDirectory(Path.GetDirectoryName(full)!);
                e.ExtractToFile(full, overwrite: true);
                count++;
            }
            // the vault from the backup is complete: only now it takes the place of the one you had
            if (hasVault && Directory.Exists(incoming))
            {
                var old = vaultDir + ".old";
                CleanEngine.Delete(old);
                if (Directory.Exists(vaultDir)) Directory.Move(vaultDir, old);
                Directory.Move(incoming, vaultDir);
                CleanEngine.Delete(old);
            }
        }
        Home.History("restore", "backup");
        progress?.Invoke(1, "");
        return count;
    }

    /// <summary>v0.8: leftovers of a restore that was cut off (crash, power cut): the unpacked zip and a half unpacked
    /// vault go; a vault that was half way through being swapped is put back. Also old Temp files of v0.7 and earlier.
    /// Called at start and before every restore. Returns how many things were removed.</summary>
    public static int Sweep()
    {
        int n = 0;
        var vaultDir = Path.Combine(Home.Dir, "vault");
        try
        {
            if (!Directory.Exists(vaultDir) && Directory.Exists(vaultDir + ".old")) Directory.Move(vaultDir + ".old", vaultDir);
            foreach (var d in new[] { vaultDir + ".incoming", vaultDir + ".old" })
                if (Directory.Exists(d) && CleanEngine.Delete(d)) n++;
            if (Directory.Exists(Home.Dir))
                foreach (var f in Directory.EnumerateFiles(Home.Dir, ".restore-*.zip")) if (CleanEngine.Delete(f)) n++;
            if (!Home.Test)
                foreach (var f in Directory.EnumerateFiles(Path.GetTempPath(), "Amnesia-restore-*.zip")) if (CleanEngine.Delete(f)) n++;
        }
        catch { }
        return n;
    }

    static void MergeKeepList(ZipArchiveEntry e)
    {
        using var r = new StreamReader(e.Open());
        var have = File.Exists(KeepList.File) ? File.ReadAllLines(KeepList.File).Select(l => l.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase) : new HashSet<string>();
        var add = new List<string>();
        while (r.ReadLine() is { } l) if (l.Trim().Length > 0 && !have.Contains(l.Trim())) add.Add(l.Trim());
        if (add.Count > 0) { Directory.CreateDirectory(Home.Dir); File.AppendAllLines(KeepList.File, add); }
    }

    static void MergeSettings(ZipArchiveEntry e)
    {
        using var r = new StreamReader(e.Open());
        while (r.ReadLine() is { } l)
        {
            var i = l.IndexOf('=');
            if (i > 0 && CarrySettings.Contains(l[..i])) Conf.Set(l[..i], l[(i + 1)..]);
        }
    }
}
