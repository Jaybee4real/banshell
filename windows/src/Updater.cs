using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;

namespace Banshell;

public static class Updater
{
    private const string Repo = "Jaybee4real/banshell";
    private const string InstallerAsset = "Banshell-Setup.exe";
    private static bool checking;

    public static string CurrentVersion
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version == null ? "0.0.0" : $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }

    public static int[] ParseVersion(string text)
    {
        return text.TrimStart('v', ' ').Split('.')
            .Select(part => int.TryParse(new string(part.TakeWhile(char.IsDigit).ToArray()), out var value) ? value : 0)
            .ToArray();
    }

    public static bool IsNewer(string candidate, string current)
    {
        var left = ParseVersion(candidate);
        var right = ParseVersion(current);
        for (int index = 0; index < Math.Max(left.Length, right.Length); index++)
        {
            int a = index < left.Length ? left[index] : 0;
            int b = index < right.Length ? right[index] : 0;
            if (a != b) return a > b;
        }
        return false;
    }

    private record ReleaseInfo(string Version, string AssetUrl, string Notes);

    private static async Task<ReleaseInfo?> FetchLatestAsync()
    {
        using var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("BANSHELL-Updater", "1.0"));
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        client.Timeout = TimeSpan.FromSeconds(15);
        var json = await client.GetStringAsync($"https://api.github.com/repos/{Repo}/releases/latest");
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var version = tag.StartsWith('v') ? tag[1..] : tag;
        var notes = root.TryGetProperty("body", out var bodyElement) ? bodyElement.GetString() ?? "" : "";
        if (!root.TryGetProperty("assets", out var assets)) return null;
        foreach (var asset in assets.EnumerateArray())
        {
            if (asset.GetProperty("name").GetString() == InstallerAsset)
                return new ReleaseInfo(version, asset.GetProperty("browser_download_url").GetString() ?? "", notes);
        }
        return null;
    }

    public static async Task CheckAsync(bool silent)
    {
        if (checking) return;
        checking = true;
        try
        {
            ReleaseInfo? info;
            try
            {
                info = await FetchLatestAsync();
            }
            catch (Exception error)
            {
                if (!silent) MessageBox.Show($"Couldn't check for updates: {error.Message}", "BANSHELL");
                return;
            }
            if (info == null)
            {
                if (!silent) MessageBox.Show("No Windows installer found in the latest release.", "BANSHELL");
                return;
            }
            if (!IsNewer(info.Version, CurrentVersion))
            {
                if (!silent) MessageBox.Show($"BANSHELL is up to date (v{CurrentVersion}).", "BANSHELL");
                return;
            }
            var config = BanshellConfig.Load();
            if (silent)
            {
                if (!config.AutoDownload)
                {
                    readyRelease = info;
                    StatusChanged?.Invoke();
                    return;
                }
                await DownloadSilent(info, config.AutoInstall);
                return;
            }
            var notesPreview = string.IsNullOrWhiteSpace(info.Notes) ? "" : "\n\nWhat's new:\n" + Truncate(info.Notes, 500);
            var choice = MessageBox.Show(
                $"Update available: v{CurrentVersion} → v{info.Version}\n\nDownload and install now? BANSHELL will restart.{notesPreview}",
                "BANSHELL Update", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (choice == DialogResult.Yes) await DownloadSilent(info, true);
        }
        finally
        {
            checking = false;
        }
    }

    private static string? downloadingVersion;
    private static int downloadPercent;
    private static ReleaseInfo? readyRelease;
    private static (string Path, string Version)? readyInstaller;

    public static event Action? StatusChanged;

    public static string? StatusText =>
        readyInstaller is { } ready ? $"Install v{ready.Version} & Restart"
        : readyRelease is { } release ? $"Download & Install v{release.Version}"
        : downloadingVersion is { } version ? $"Downloading v{version}… {downloadPercent}%"
        : null;

    public static async void ActOnStatus()
    {
        if (readyInstaller is { } ready)
        {
            RunInstaller(ready.Path);
        }
        else if (readyRelease is { } release)
        {
            readyRelease = null;
            await DownloadSilent(release, true);
        }
    }

    private static async Task DownloadSilent(ReleaseInfo info, bool autoInstall)
    {
        var target = Path.Combine(Path.GetTempPath(), $"Banshell-Setup-{info.Version}.exe");
        downloadingVersion = info.Version;
        downloadPercent = 0;
        readyRelease = null;
        readyInstaller = null;
        StatusChanged?.Invoke();
        try
        {
            using var client = new HttpClient();
            client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("BANSHELL-Updater", "1.0"));
            client.Timeout = TimeSpan.FromMinutes(10);
            using var response = await client.GetAsync(info.AssetUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength ?? -1;
            using var source = await response.Content.ReadAsStreamAsync();
            using var file = File.Create(target);
            var buffer = new byte[81920];
            long readTotal = 0;
            int lastPercent = -1;
            int read;
            while ((read = await source.ReadAsync(buffer)) > 0)
            {
                await file.WriteAsync(buffer.AsMemory(0, read));
                readTotal += read;
                if (total <= 0) continue;
                int percent = (int)(readTotal * 100 / total);
                if (percent == lastPercent) continue;
                lastPercent = percent;
                downloadPercent = percent;
                StatusChanged?.Invoke();
            }
        }
        catch
        {
            downloadingVersion = null;
            StatusChanged?.Invoke();
            return;
        }
        downloadingVersion = null;
        if (autoInstall)
        {
            RunInstaller(target);
        }
        else
        {
            readyInstaller = (target, info.Version);
            StatusChanged?.Invoke();
        }
    }

    private static void RunInstaller(string setupPath)
    {
        Process.Start(new ProcessStartInfo(setupPath, "/SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS")
        {
            UseShellExecute = true,
        });
        Application.Exit();
    }

    private static string Truncate(string text, int max) =>
        text.Length <= max ? text : text[..max];
}
