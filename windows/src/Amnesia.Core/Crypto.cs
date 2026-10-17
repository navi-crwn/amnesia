// The locked files of the vault and of backups. Plain .NET crypto, no 7-Zip needed on Windows.
//
//   AMNESIA1, kind (1 = snapshot, 2 = backup), [backup: the password-locked private key], the random file key locked with
//   the vault's public key (RSA-OAEP-SHA256), then the zip in 1 MB pieces, each locked with AES-256-GCM.
//   Every piece carries its number and a "last piece" mark, so a cut or reordered file never opens.
//
// Same idea as the Mac vault: making a snapshot needs no password (public key), opening one does (private key).
using System.Buffers.Binary;
using System.Security.Cryptography;

namespace Amnesia.Core;

public static class Crypto
{
    static readonly byte[] Magic = "AMNESIA1"u8.ToArray();
    public const byte KindSnapshot = 1, KindBackup = 2, KindSafe = 3;
    const int Piece = 1 << 20;

    /// <summary>The vault's key pair: the private key locked with your password (PBKDF2-SHA256, 600 000 rounds, AES-256).</summary>
    public static (byte[] pub, byte[] lockedPriv) NewKeys(string password)
    {
        using var rsa = RSA.Create(3072);
        return (rsa.ExportSubjectPublicKeyInfo(),
                rsa.ExportEncryptedPkcs8PrivateKey(password, new PbeParameters(PbeEncryptionAlgorithm.Aes256Cbc, HashAlgorithmName.SHA256, 600_000)));
    }

    /// <summary>Opens the private key. Wrong password: CryptographicException.</summary>
    public static RSA Unlock(byte[] lockedPriv, string password)
    {
        var rsa = RSA.Create();
        try { rsa.ImportEncryptedPkcs8PrivateKey(password, lockedPriv, out _); return rsa; }
        catch { rsa.Dispose(); throw; }
    }

    public static byte[] Relock(byte[] lockedPriv, string oldPw, string newPw)
    {
        using var rsa = Unlock(lockedPriv, oldPw);
        return rsa.ExportEncryptedPkcs8PrivateKey(newPw, new PbeParameters(PbeEncryptionAlgorithm.Aes256Cbc, HashAlgorithmName.SHA256, 600_000));
    }

    /// <summary>A stream that locks everything written to it into <paramref name="output"/>. Dispose finishes the file.</summary>
    public static Stream Writer(Stream output, byte kind, byte[] pub, byte[]? lockedPriv = null)
    {
        var key = RandomNumberGenerator.GetBytes(32);
        byte[] wrapped;
        using (var rsa = RSA.Create()) { rsa.ImportSubjectPublicKeyInfo(pub, out _); wrapped = rsa.Encrypt(key, RSAEncryptionPadding.OaepSHA256); }
        output.Write(Magic);
        output.WriteByte(kind);
        Span<byte> n = stackalloc byte[4];
        var priv = lockedPriv ?? Array.Empty<byte>();
        BinaryPrimitives.WriteInt32LittleEndian(n, priv.Length); output.Write(n); output.Write(priv);
        BinaryPrimitives.WriteInt32LittleEndian(n, wrapped.Length); output.Write(n); output.Write(wrapped);
        var prefix = RandomNumberGenerator.GetBytes(4);
        output.Write(prefix);
        return new GcmWriter(output, key, prefix);
    }

    /// <summary>Reads the header: kind and (backups) the locked private key inside it.</summary>
    public static (byte kind, byte[] lockedPriv) Peek(string file)
    {
        using var f = File.OpenRead(file);
        var (kind, priv, _, _) = Header(f);
        return (kind, priv);
    }

    static (byte kind, byte[] priv, byte[] wrapped, byte[] prefix) Header(Stream f)
    {
        var magic = Read(f, Magic.Length);
        if (!magic.AsSpan().SequenceEqual(Magic)) throw new InvalidDataException("Not an Amnesia file.");
        int kind = f.ReadByte();
        var priv = Read(f, BinaryPrimitives.ReadInt32LittleEndian(Read(f, 4)));
        var wrapped = Read(f, BinaryPrimitives.ReadInt32LittleEndian(Read(f, 4)));
        return ((byte)kind, priv, wrapped, Read(f, 4));
    }

    /// <summary>Opens a locked file into <paramref name="output"/> with the vault's private key.</summary>
    public static void Open(string file, RSA priv, Stream output, Action<double>? progress = null, CancellationToken cancel = default)
    {
        using var f = File.OpenRead(file);
        var (_, _, wrapped, prefix) = Header(f);
        var key = priv.Decrypt(wrapped, RSAEncryptionPadding.OaepSHA256);
        using var gcm = new AesGcm(key, 16);
        long index = 0;
        var len = new byte[4];
        while (true)
        {
            cancel.ThrowIfCancellationRequested();
            if (f.Read(len, 0, 4) < 4) throw new InvalidDataException("The file is cut short.");
            int size = BinaryPrimitives.ReadInt32LittleEndian(len);
            bool last = (size & int.MinValue) != 0;
            size &= int.MaxValue;
            if (size > Piece + 16) throw new InvalidDataException("The file is damaged.");
            var data = Read(f, size);
            var plain = new byte[size - 16];
            gcm.Decrypt(Nonce(prefix, index), data.AsSpan(0, size - 16), data.AsSpan(size - 16), plain, Aad(index, last));
            output.Write(plain);
            index++;
            progress?.Invoke(f.Length > 0 ? (double)f.Position / f.Length : 1);
            if (last) break;
        }
    }

    static byte[] Read(Stream s, int n)
    {
        if (n < 0 || n > 64 << 20) throw new InvalidDataException("The file is damaged.");
        var b = new byte[n];
        s.ReadExactly(b);
        return b;
    }

    static byte[] Nonce(byte[] prefix, long index)
    {
        var n = new byte[12];
        prefix.CopyTo(n, 0);
        BinaryPrimitives.WriteInt64LittleEndian(n.AsSpan(4), index);
        return n;
    }

    static byte[] Aad(long index, bool last)
    {
        var a = new byte[9];
        BinaryPrimitives.WriteInt64LittleEndian(a, index);
        a[8] = last ? (byte)1 : (byte)0;
        return a;
    }

    sealed class GcmWriter(Stream output, byte[] key, byte[] prefix) : Stream
    {
        readonly AesGcm gcm = new(key, 16);
        readonly byte[] buf = new byte[Piece];
        int fill;
        long index, written;
        bool done;

        public override void Write(byte[] buffer, int offset, int count) => Write(buffer.AsSpan(offset, count));
        public override void Write(ReadOnlySpan<byte> data)
        {
            while (data.Length > 0)
            {
                if (fill == Piece) Flush(false);
                int n = Math.Min(Piece - fill, data.Length);
                data[..n].CopyTo(buf.AsSpan(fill));
                fill += n; written += n;
                data = data[n..];
            }
        }

        void Flush(bool last)
        {
            var cipher = new byte[fill + 16];
            gcm.Encrypt(Nonce(prefix, index), buf.AsSpan(0, fill), cipher.AsSpan(0, fill), cipher.AsSpan(fill), Aad(index, last));
            Span<byte> len = stackalloc byte[4];
            BinaryPrimitives.WriteInt32LittleEndian(len, cipher.Length | (last ? int.MinValue : 0));
            output.Write(len);
            output.Write(cipher);
            index++; fill = 0;
        }

        protected override void Dispose(bool disposing)
        {
            if (!done && disposing) { done = true; Flush(true); output.Flush(); gcm.Dispose(); CryptographicOperations.ZeroMemory(key); }
            base.Dispose(disposing);
        }

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => written;
        public override long Position { get => written; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }

    /// <summary>A salted hash for the panic word (never stored as text).</summary>
    public static string Hash(string word, string salt) =>
        Convert.ToHexString(Rfc2898DeriveBytes.Pbkdf2(word, Convert.FromHexString(salt), 200_000, HashAlgorithmName.SHA256, 32));
}
