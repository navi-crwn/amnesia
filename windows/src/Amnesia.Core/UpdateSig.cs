// v0.8 signed updates (free, no paid certificate): every Windows release carries SHA256SUMS.txt.sig, an ECDSA P-256
// signature of SHA256SUMS.txt made with a key only the developer has (openssl dgst -sha256 -sign). The app holds the
// public half below. A release without a good signature is never installed from the app: it opens the release page.
using System.Security.Cryptography;

namespace Amnesia.Core;

public static class UpdateSig
{
    /// <summary>Base64 of the public key (DER SubjectPublicKeyInfo). The publish script puts the real one here.</summary>
    public const string PublicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE52jL2iMKP6nxCJ02PXei1luJqVjR7BngXg5FeyHIdlum7BV0b4wXwU5A2b5LvsuexEEQ2WLYuorAu0tqBCghTQ==";

    public static bool HasKey => !PublicKey.StartsWith("AMNESIA_");

    /// <summary>v0.11.1: is candidate a higher version than current? The same, an older one (a replayed old release, even a
    /// correctly signed one) or one that cannot be read is not: nothing is installed from it.</summary>
    public static bool IsNewer(string candidate, string current) =>
        Version.TryParse(candidate, out var v) && Version.TryParse(current, out var c) && v > c;

    /// <summary>Is sig (DER, as openssl writes it) a signature of data by this key? Any problem counts as "no".</summary>
    public static bool Verify(byte[] data, byte[] sig, string publicKey = PublicKey)
    {
        try
        {
            if (publicKey.StartsWith("AMNESIA_") || sig.Length < 8) return false;
            using var ec = ECDsa.Create();
            ec.ImportSubjectPublicKeyInfo(Convert.FromBase64String(publicKey), out _);
            if (ec.KeySize != 256) return false;
            return ec.VerifyData(data, sig, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        }
        catch { return false; }
    }
}
