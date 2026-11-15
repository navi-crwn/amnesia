// v0.8 Safe box (experimental, opt-in): a locked part of Keep. While closed, Keep\Safe exists only as one locked file
// (.amnesia\safe\safe.ams, same format as the vault: AES-256-GCM pieces, key locked with RSA, private key with your
// password). "Open" unpacks it into Keep\Safe; "Close" packs Keep\Safe again and deletes the open copy. Closing needs no
// password (public key), so Amnesia closes it by itself at sign out and when it starts after a crash.
// Honest limits: the open copy is deleted, not overwritten (BitLocker protects that), and the safe is as strong as the password.
// v0.8.1: no full safe.ams.prev copy any more after a close (it doubled the space): the old file is only kept while the
// new one is written and checked. The number of files in the closed safe is written down (SAFE_FILES, no names), so
// uninstalling can warn that the safe still holds files.
using System.IO.Compression;
using System.Security.Cryptography;

namespace Amnesia.Core;

public static class Safe
{
    public const int MinPassword = 12;
    static string D => Path.Combine(Home.Dir, "safe");
    static string FPub => Path.Combine(D, "public.key");
    static string FPriv => Path.Combine(D, "private.key");
    public static string File_ => Path.Combine(D, "safe.ams");
    /// <summary>Where the open safe is (inside Keep, so the cleanup never takes it while it is open).</summary>
    public static string OpenDir => Path.Combine(Conf.KeepDir, "Safe");

    public static bool Exists => File.Exists(FPub) && File.Exists(FPriv) && File.Exists(File_);
    public static bool IsOpen => Exists && Directory.Exists(OpenDir) && !Stray && MarkerState is null or "open";
    static string Prev => File_ + ".prev";
    /// <summary>Tests only: runs right after the open copy was packed and before it is deleted.</summary>
    public static Action? AfterPackTest { get; set; }
    // v0.11.1: Create and Open leave this marker while Keep\Safe is the open copy. Close takes it away. If a close packed
    // fine but could not delete everything, it says "leftover": what remains is a copy of what is already packed.
    static string Marker => Path.Combine(D, "open.marker");
    // the first line is the state; after "leftover" come the files that were left, one per line: path|size|date (see Leftovers)
    // null = no marker (an open safe from v0.11.0, or none). Anything but "open" or "leftover" (empty, cut off, locked and
    // unreadable) is "unknown": the folder is then never packed or deleted, whatever it holds.
    static string? MarkerState
    {
        get
        {
            try
            {
                if (!File.Exists(Marker)) return null;
                var first = (File.ReadLines(Marker).FirstOrDefault() ?? "").Trim();
                return first is "open" or "leftover" ? first : "unknown";
            }
            catch { return "unknown"; }
        }
    }
    static void ClearMarker() { try { File.Delete(Marker); } catch { } }

    /// <summary>v0.11.1: a Keep\Safe that Open did not make and that holds no real file (empty, or only desktop.ini,
    /// Thumbs.db and empty folders: made by hand, a sync tool or Explorer) while the closed safe holds files. It is not an
    /// open safe: closing it would pack nothing over the real safe.</summary>
    static bool Stray
    {
        get
        {
            try
            {
                return Directory.Exists(OpenDir) && !File.Exists(Marker) && Conf.Int("SAFE_FILES", -1) != 0 && !HasRealFile(OpenDir);
            }
            catch { return false; }
        }
    }

    static bool HasRealFile(string dir) =>
        // IgnoreInaccessible = false: a folder that cannot be listed (a locked Keep) throws, so it is never taken for an empty one
        new DirectoryInfo(dir).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = false })
            .Any(f => !f.Name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) && !f.Name.Equals("Thumbs.db", StringComparison.OrdinalIgnoreCase));

    /// <summary>v0.8.1: how many files the safe holds (open: what is in Keep\Safe now). -1 = not known (closed by v0.8.0).</summary>
    public static int Count
    {
        get
        {
            if (!Exists) return 0;
            if (IsOpen)
                try { return new DirectoryInfo(OpenDir).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = false }).Count(); }
                catch { return -1; }
            return Conf.Int("SAFE_FILES", -1);
        }
    }

    public static void Create(string password)
    {
        if (Exists) throw new VaultError("safe-exists");
        if (password.Length < MinPassword) throw new VaultError("short-password");
        Directory.CreateDirectory(D);
        var (pub, priv) = Crypto.NewKeys(password);
        File.WriteAllBytes(FPub, pub);
        File.WriteAllBytes(FPriv, priv);
        // an empty safe, opened right away so you can put files in
        Pack(null);
        Directory.CreateDirectory(OpenDir);
        File.WriteAllText(Marker, "open");
        Home.Trace("safe", "created");
    }

    /// <summary>Unpacks the safe into Keep\Safe. Wrong password: VaultError "wrong".</summary>
    public static int Open(string password)
    {
        if (!Exists) throw new VaultError("no-safe");
        if (MarkerState != null && !Directory.Exists(OpenDir)) ClearMarker(); // Keep\Safe was taken away by hand
        if (IsOpen) return 0;
        RemoveStray();
        RSA rsa;
        try { rsa = Crypto.Unlock(File.ReadAllBytes(FPriv), password); }
        catch (CryptographicException) { throw new VaultError("wrong", -1); }
        using (rsa)
        {
            RemoveLeftover(); // only after the password is right: a wrong guess deletes nothing
            var tmp = Path.Combine(D, $".open-{Guid.NewGuid():N}.zip");
            var stage = OpenDir + ".opening";
            if (Directory.Exists(stage)) CleanEngine.Delete(stage);
            int n = 0;
            try
            {
                using (var o = new FileStream(tmp, FileMode.Create, FileAccess.ReadWrite, FileShare.Delete, 1 << 16, FileOptions.DeleteOnClose))
                {
                    Crypto.Open(File_, rsa, o);
                    o.Position = 0;
                    using var z = new ZipArchive(o, ZipArchiveMode.Read, leaveOpen: true);
                    z.ExtractToDirectory(stage, overwriteFiles: true);
                    n = z.Entries.Count(e => e.Name.Length > 0);
                }
                Directory.CreateDirectory(stage);
                Directory.Move(stage, OpenDir);
            }
            catch
            {
                // v0.11.1: whatever stops it, the unpacked files do not stay behind in Keep
                CleanEngine.Delete(stage);
                throw;
            }
            File.WriteAllText(Marker, "open");
            Home.Trace("safe", $"opened ({n} files)");
            return n;
        }
    }

    /// <summary>Packs Keep\Safe into the locked file and deletes the open copy. Returns the number of files, -1 when it
    /// was not open. If packing fails the open copy stays (nothing is lost) and the old locked file is untouched.</summary>
    public static int Close(string why = "app")
    {
        if (!IsOpen)
        {
            if (MarkerState != null && !Directory.Exists(OpenDir)) ClearMarker(); // Keep\Safe was taken away by hand
            RemoveStray();
            RemoveLeftover();
            return -1;
        }
        int n = Pack(OpenDir);
        AfterPackTest?.Invoke();
        // Links and cloud placeholders are not packed (Pack skips them): deleting the open copy would lose them. It stays open.
        if (HasLinks(OpenDir))
        {
            Home.Trace("safe", "Keep Safe holds links or cloud-only files that cannot be packed: the open copy stays");
            return n;
        }
        // Write down what was packed BEFORE anything is deleted. If that fails, nothing is deleted: the open copy stays whole.
        try { File.WriteAllLines(Marker, new[] { "leftover" }.Concat(packedLines)); }
        catch (Exception e)
        {
            Home.Trace("safe", $"closed ({n} files) but the state could not be written down ({e.GetType().Name}): the open copy stays");
            return n;
        }
        if (CleanEngine.Delete(OpenDir)) ClearMarker();
        else Home.Trace("safe", "the open copy could not be deleted completely (a file in use?); what is left is marked, and is replaced at the next Open");
        Home.Trace("safe", $"closed ({n} files, {why})");
        return n;
    }

    /// <summary>v0.11.1: takes away a stray Keep\Safe (it holds nothing but empty folders and Explorer junk).</summary>
    static void RemoveStray()
    {
        if (!Stray) return;
        try { Directory.Delete(OpenDir, true); Home.Trace("safe", "a Keep\\Safe that was not an open safe was removed; the closed safe was not touched"); } catch { }
    }

    /// <summary>v0.11.1: finishes deleting what a finished close could not delete (it is a copy of what is packed).</summary>
    // What was packed, as read just before each file was read: path|size|date. Written into the marker when a close starts to
    // delete. Only a file that still matches this exactly is the copy of what was packed (dates alone cannot tell: a copied
    // file keeps its old date; and a file saved while the rest is being packed must not match).
    static List<string> packedLines = new();

    static bool HasLinks(string dir)
    {
        foreach (var c in new DirectoryInfo(dir).EnumerateFileSystemInfos())
        {
            if (c.Attributes.HasFlag(FileAttributes.ReparsePoint)) return true;
            if (c is DirectoryInfo d && HasLinks(d.FullName)) return true;
        }
        return false;
    }

    // Every file in the leftover folder that is not exactly what the close left (a new file, a copy with an old date, one that
    // was changed) is moved to "Safe recovered ..." in Keep, never deleted. If one cannot be moved, nothing is deleted at all.
    static void RemoveLeftover()
    {
        if (MarkerState != "leftover" || !Directory.Exists(OpenDir)) return;
        try
        {
            var packed = new Dictionary<string, (long size, long ticks)>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in File.ReadAllLines(Marker).Skip(1))
            {
                var parts = line.Split('|');
                if (parts.Length == 3 && long.TryParse(parts[1], out var size) && long.TryParse(parts[2], out var ticks)) packed[parts[0]] = (size, ticks);
            }
            string? rescue = null;
            foreach (var f in new DirectoryInfo(OpenDir).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = false }).ToList())
            {
                var rel = Path.GetRelativePath(OpenDir, f.FullName);
                if (packed.TryGetValue(rel.Replace(Path.DirectorySeparatorChar, '/'), out var m) && m.size == f.Length && m.ticks == f.LastWriteTimeUtc.Ticks) continue;
                rescue ??= Path.Combine(Conf.KeepDir, "Safe recovered " + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                var dest = Path.Combine(rescue, rel);
                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                f.MoveTo(dest);
            }
            if (rescue != null) Home.Trace("safe", "files in the leftover copy that were not part of the safe were moved to a 'Safe recovered' folder in Keep");
        }
        catch (Exception e) { Home.Trace("safe", $"leftovers of a closed safe were not touched ({e.GetType().Name})"); return; }
        if (CleanEngine.Delete(OpenDir)) ClearMarker();
    }

    static int Pack(string? dir)
    {
        var next = File_ + ".new";
        int n = 0;
        var lines = new List<string>();
        using (var file = File.Create(next))
        using (var locked = Crypto.Writer(file, Crypto.KindSafe, File.ReadAllBytes(FPub)))
        using (var zip = new ZipArchive(locked, ZipArchiveMode.Create))
        {
            if (dir != null && Directory.Exists(dir))
                // IgnoreInaccessible = false: a folder that cannot be listed stops the pack (an empty pack would replace the safe)
                foreach (var f in new DirectoryInfo(dir).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint, IgnoreInaccessible = false }))
                {
                    var relPath = Path.GetRelativePath(dir, f.FullName).Replace('\\', '/');
                    lines.Add($"{relPath}|{f.Length}|{f.LastWriteTimeUtc.Ticks}"); // as listed, before the file is read
                    var e = zip.CreateEntry(relPath, CompressionLevel.Fastest);
                    using var src = f.OpenRead();
                    using var dst = e.Open();
                    src.CopyTo(dst);
                    n++;
                }
        }
        packedLines = lines;
        // the new file must at least be readable as an Amnesia file before it replaces the old one
        if (Crypto.Peek(next).kind != Crypto.KindSafe) throw new InvalidDataException("safe-write");
        // v0.8.1: the old file is only kept while the new one replaces it, then it goes (no second full copy)
        if (File.Exists(File_)) File.Replace(next, File_, Prev); else File.Move(next, File_);
        try { if (File.Exists(Prev) && Crypto.Peek(File_).kind == Crypto.KindSafe) File.Delete(Prev); } catch { }
        Conf.Set("SAFE_FILES", n.ToString());
        return n;
    }

    /// <summary>Removes the safe for good (needs the password).</summary>
    public static void Delete(string password)
    {
        if (!Exists) return;
        try { using var _ = Crypto.Unlock(File.ReadAllBytes(FPriv), password); }
        catch (CryptographicException) { throw new VaultError("wrong", -1); }
        if (Directory.Exists(OpenDir)) CleanEngine.Delete(OpenDir);
        CleanEngine.Delete(D);
        Conf.Set("SAFE_FILES", null);
        Home.Trace("safe", "deleted");
    }
}
