// v0.8 Safe box (experimental, opt-in): a locked part of Keep. While closed, Keep\Safe exists only as one locked file
// (.amnesia\safe\safe.ams, same format as the vault: AES-256-GCM pieces, key locked with RSA, private key with your
// password). "Open" unpacks it into Keep\Safe; "Close" packs Keep\Safe again and deletes the open copy. Closing needs no
// password (public key), so Amnesia closes it by itself at sign out and when it starts after a crash.
// Honest limits: the open copy is deleted, not overwritten (BitLocker protects that), and the safe is as strong as the password.
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
    public static bool IsOpen => Exists && Directory.Exists(OpenDir);

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
        Home.Trace("safe", "created");
    }

    /// <summary>Unpacks the safe into Keep\Safe. Wrong password: VaultError "wrong".</summary>
    public static int Open(string password)
    {
        if (!Exists) throw new VaultError("no-safe");
        if (IsOpen) return 0;
        RSA rsa;
        try { rsa = Crypto.Unlock(File.ReadAllBytes(FPriv), password); }
        catch (CryptographicException) { throw new VaultError("wrong", -1); }
        using (rsa)
        {
            var tmp = Path.Combine(D, $".open-{Guid.NewGuid():N}.zip");
            var stage = OpenDir + ".opening";
            if (Directory.Exists(stage)) CleanEngine.Delete(stage);
            int n = 0;
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
            Home.Trace("safe", $"opened ({n} files)");
            return n;
        }
    }

    /// <summary>Packs Keep\Safe into the locked file and deletes the open copy. Returns the number of files, -1 when it
    /// was not open. If packing fails the open copy stays (nothing is lost) and the old locked file is untouched.</summary>
    public static int Close(string why = "app")
    {
        if (!IsOpen) return -1;
        int n = Pack(OpenDir);
        if (!CleanEngine.Delete(OpenDir)) Home.Trace("safe", "the open copy could not be deleted completely (a file in use?)");
        Home.Trace("safe", $"closed ({n} files, {why})");
        return n;
    }

    static int Pack(string? dir)
    {
        var next = File_ + ".new";
        int n = 0;
        using (var file = File.Create(next))
        using (var locked = Crypto.Writer(file, Crypto.KindSafe, File.ReadAllBytes(FPub)))
        using (var zip = new ZipArchive(locked, ZipArchiveMode.Create))
        {
            if (dir != null && Directory.Exists(dir))
                foreach (var f in new DirectoryInfo(dir).EnumerateFiles("*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint }))
                {
                    var e = zip.CreateEntry(Path.GetRelativePath(dir, f.FullName).Replace('\\', '/'), CompressionLevel.Fastest);
                    using var src = f.OpenRead();
                    using var dst = e.Open();
                    src.CopyTo(dst);
                    n++;
                }
        }
        // the new file must at least be readable as an Amnesia file before it replaces the old one
        if (Crypto.Peek(next).kind != Crypto.KindSafe) throw new InvalidDataException("safe-write");
        if (File.Exists(File_)) File.Replace(next, File_, File_ + ".prev"); else File.Move(next, File_);
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
        Home.Trace("safe", "deleted");
    }
}
