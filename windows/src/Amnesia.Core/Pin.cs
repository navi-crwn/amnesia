// v0.7: PINs and passwords that only need to be checked, never read back (lab lock PIN, Keep lock password).
// Stored as "pbkdf2$iterations$salt$hash" (PBKDF2-SHA256), so the file never holds the PIN itself.
using System.Security.Cryptography;

namespace Amnesia.Core;

public static class Pin
{
    const int Iterations = 200_000;

    public static string Hash(string pin)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(pin, salt, Iterations, HashAlgorithmName.SHA256, 32);
        return $"pbkdf2${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
    }

    public static bool Verify(string pin, string? stored)
    {
        try
        {
            var p = stored?.Split('$');
            if (p is not { Length: 4 } || p[0] != "pbkdf2") return false;
            var salt = Convert.FromBase64String(p[2]);
            var want = Convert.FromBase64String(p[3]);
            var got = Rfc2898DeriveBytes.Pbkdf2(pin, salt, int.Parse(p[1]), HashAlgorithmName.SHA256, want.Length);
            return CryptographicOperations.FixedTimeEquals(got, want);
        }
        catch { return false; }
    }

    /// <summary>Lab PIN: at least 6 digits. Keep password: at least 4 characters.</summary>
    public static bool GoodPin(string pin) => pin.Length >= 6 && pin.All(char.IsAsciiDigit);
    public static bool GoodPassword(string pw) => pw.Length >= 4;
}
