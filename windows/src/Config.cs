using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Banshell;

public class BanshellConfig
{
    public string PinSaltHex { get; set; } = "";
    public string PinHashHex { get; set; } = "";
    public int ArmHour { get; set; } = 23;
    public int ArmMinute { get; set; } = 0;
    public bool AutoArmDaily { get; set; } = true;
    public double AccelDeltaG { get; set; } = 0.06;
    public int ExitDelaySeconds { get; set; } = 30;
    public int EntryDelaySeconds { get; set; } = 15;
    public bool MotionTrigger { get; set; } = true;
    public bool PowerTrigger { get; set; } = true;
    public bool InputTrigger { get; set; } = true;

    public bool HasPin => PinHashHex.Length > 0;

    public static string SupportDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Banshell");

    private static string ConfigPath => Path.Combine(SupportDir, "config.json");
    private static string StatePath => Path.Combine(SupportDir, "state.json");

    public static BanshellConfig Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
                return JsonSerializer.Deserialize<BanshellConfig>(File.ReadAllText(ConfigPath)) ?? new BanshellConfig();
        }
        catch { }
        return new BanshellConfig();
    }

    public void Save()
    {
        Directory.CreateDirectory(SupportDir);
        File.WriteAllText(ConfigPath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
    }

    public static string HashPin(string pin, string saltHex)
    {
        var salt = Convert.FromHexString(saltHex.Length % 2 == 0 ? saltHex : "");
        var combined = salt.Concat(Encoding.UTF8.GetBytes(pin)).ToArray();
        return Convert.ToHexString(SHA256.HashData(combined)).ToLowerInvariant();
    }

    public bool VerifyPin(string attempt) => HashPin(attempt, PinSaltHex) == PinHashHex;

    public void SetPin(string pin)
    {
        PinSaltHex = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
        PinHashHex = HashPin(pin, PinSaltHex);
    }

    public static BanshellState LoadState()
    {
        try
        {
            if (File.Exists(StatePath))
                return JsonSerializer.Deserialize<BanshellState>(File.ReadAllText(StatePath)) ?? new BanshellState();
        }
        catch { }
        return new BanshellState();
    }

    public static void SaveState(BanshellState state)
    {
        Directory.CreateDirectory(SupportDir);
        File.WriteAllText(StatePath, JsonSerializer.Serialize(state));
    }
}

public class BanshellState
{
    public bool Armed { get; set; }
    public bool Triggered { get; set; }
    public string? LastAutoArmDay { get; set; }
    public string? Reason { get; set; }
}
