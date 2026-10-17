// v0.4 update from the app (Settings → Update). v0.8: SHA256SUMS.txt must carry a good signature (UpdateSig). Looks at the project's GitHub releases for the newest Windows release
// (tag "win-v0.x.y"), downloads Amnesia-Setup-<version>-<x64|arm64>.exe, checks it against SHA256SUMS.txt of that
// release and runs it. Nothing is sent except a normal download request. Portable copies just open the release page.
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Amnesia;

static class Updater
{
    const string Api = "https://api.github.com/repos/navi-crwn/amnesia/releases?per_page=20";
    public const string Releases = "https://github.com/navi-crwn/amnesia/releases";
    static string Arch => RuntimeInformation.OSArchitecture == Architecture.Arm64 ? "arm64" : "x64";
    static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Amnesia", "update");

    static HttpClient Http()
    {
        var h = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        h.DefaultRequestHeaders.UserAgent.ParseAdd($"Amnesia-Windows/{AppInfo.Version}");
        return h;
    }

    public sealed record Release(string Version, string Page, string? Setup, string? Sums, string? Sig = null);

    /// <summary>v0.8: does this copy know the developer's update key? (Without it: never install from the app.)</summary>
    public static bool Signed => Core.UpdateSig.HasKey;

    /// <summary>The newest Windows release, or null when there is none yet.</summary>
    public static async Task<Release?> LatestAsync()
    {
        using var h = Http();
        var list = await h.GetFromJsonAsync<JsonArray>(Api) ?? new JsonArray();
        foreach (var r in list)
        {
            var tag = r?["tag_name"]?.GetValue<string>() ?? "";
            if (!tag.StartsWith("win-v") || r!["draft"]?.GetValue<bool>() == true || r["prerelease"]?.GetValue<bool>() == true) continue;
            var ver = tag[5..];
            string? setup = null, sums = null, sig = null;
            foreach (var a in r["assets"]?.AsArray() ?? new JsonArray())
            {
                var name = a?["name"]?.GetValue<string>() ?? "";
                var url = a?["browser_download_url"]?.GetValue<string>();
                if (name.Equals($"Amnesia-Setup-{ver}-{Arch}.exe", StringComparison.OrdinalIgnoreCase)) setup = url;
                if (name.Equals("SHA256SUMS.txt", StringComparison.OrdinalIgnoreCase)) sums = url;
                if (name.Equals("SHA256SUMS.txt.sig", StringComparison.OrdinalIgnoreCase)) sig = url;
            }
            return new Release(ver, r["html_url"]?.GetValue<string>() ?? Releases, setup, sums, sig);
        }
        return null;
    }

    public static bool Newer(string version) =>
        Version.TryParse(version, out var v) && Version.TryParse(AppInfo.Version, out var cur) && v > cur;

    /// <summary>Downloads and checks the setup, then starts it (it closes Amnesia, updates, and opens it again).</summary>
    public static async Task InstallAsync(Release r, IProgress<double>? progress = null)
    {
        if (r.Setup == null || r.Sums == null) throw new InvalidOperationException("no-setup");
        // v0.8: the list of checksums must be signed by the developer, or a changed release could pass the check
        if (!Signed || r.Sig == null) throw new InvalidOperationException("unsigned");
        Directory.CreateDirectory(Dir);
        foreach (var old in Directory.GetFiles(Dir)) try { File.Delete(old); } catch { }
        using var h = Http();
        var sumsBytes = await h.GetByteArrayAsync(r.Sums);
        var sigBytes = await h.GetByteArrayAsync(r.Sig);
        if (!Core.UpdateSig.Verify(sumsBytes, sigBytes)) { AppInfo.Trace($"update {r.Version}: signature does not match, not installed"); throw new InvalidOperationException("bad-signature"); }
        var sums = System.Text.Encoding.UTF8.GetString(sumsBytes);
        var file = Path.Combine(Dir, Path.GetFileName(new Uri(r.Setup).LocalPath));
        using (var resp = await h.GetAsync(r.Setup, HttpCompletionOption.ResponseHeadersRead))
        {
            resp.EnsureSuccessStatusCode();
            long total = resp.Content.Headers.ContentLength ?? 0, done = 0;
            await using var src = await resp.Content.ReadAsStreamAsync();
            await using var dst = File.Create(file);
            var buf = new byte[1 << 16];
            int n;
            while ((n = await src.ReadAsync(buf)) > 0) { await dst.WriteAsync(buf.AsMemory(0, n)); done += n; if (total > 0) progress?.Report((double)done / total); }
        }
        string hash;
        using (var f = File.OpenRead(file)) hash = Convert.ToHexString(SHA256.HashData(f)).ToLowerInvariant();
        bool ok = sums.Split('\n').Any(l => l.Trim().StartsWith(hash + " ", StringComparison.OrdinalIgnoreCase) && l.Contains(Path.GetFileName(file), StringComparison.OrdinalIgnoreCase));
        if (!ok) { File.Delete(file); throw new InvalidOperationException("checksum"); }
        AppInfo.Trace($"update {r.Version} downloaded and checked, starting setup");
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(file, "/SILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
    }

    /// <summary>Installed with Setup.exe? (Then updates install by themselves; a portable copy opens the release page.)</summary>
    public static bool FromSetup => File.Exists(Path.Combine(Setup.InstallDir, "unins000.exe"));
}
