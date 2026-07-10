using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

namespace Banshell;

public class Watcher : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LastInputInfo
    {
        public uint Size;
        public uint Time;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LastInputInfo info);

    public BanshellConfig Config { get; private set; }
    private BanshellState state;
    private readonly System.Windows.Forms.Timer tick;
    private readonly AccelerometerMonitor accelerometer = new();
    private readonly InputHooks hooks = new();
    private MicLevelWin? mic;
    private bool? wifiBaselineConnected;
    private (double X, double Y, double Z)? accelBaseline;
    private bool? powerBaselineOnline;
    private DateTime? monitoringStartsAt;
    private int tickCounter;

    public event Action<string>? AlarmRequested;
    public event Action? StateChanged;

    public bool Armed => state.Armed;
    public bool Triggered => state.Triggered;
    public bool AccelerometerAvailable => accelerometer.Available;
    public (double X, double Y, double Z)? AccelerometerReading => accelerometer.Read();

    public Watcher(BanshellConfig config)
    {
        Config = config;
        state = BanshellConfig.LoadState();
        hooks.InputDetected += OnInput;
        hooks.Start();
        tick = new System.Windows.Forms.Timer { Interval = 50 };
        tick.Tick += (_, _) => Tick();
        tick.Start();
        if (state.Triggered)
        {
            state.Armed = true;
            AlarmRequested?.Invoke(state.Reason ?? "resumed after restart");
        }
        else if (state.Armed)
        {
            monitoringStartsAt = DateTime.Now.AddSeconds(5);
        }
    }

    public void ReloadConfig(BanshellConfig newConfig) => Config = newConfig;

    public void Arm()
    {
        if (state.Armed) return;
        state.Armed = true;
        state.Triggered = false;
        state.Reason = null;
        accelBaseline = null;
        powerBaselineOnline = null;
        monitoringStartsAt = DateTime.Now.AddSeconds(Config.ExitDelaySeconds);
        BanshellConfig.SaveState(state);
        KeepAwake.Enable();
        StateChanged?.Invoke();
    }

    public void Disarm()
    {
        state.Armed = false;
        state.Triggered = false;
        state.Reason = null;
        accelBaseline = null;
        powerBaselineOnline = null;
        wifiBaselineConnected = null;
        monitoringStartsAt = null;
        StopMic();
        BanshellConfig.SaveState(state);
        KeepAwake.Disable();
        StateChanged?.Invoke();
    }

    public void Drill()
    {
        state.Armed = true;
        Trigger("drill");
    }

    private void Trigger(string reason)
    {
        if (state.Triggered) return;
        state.Triggered = true;
        state.Reason = reason;
        wifiBaselineConnected = null;
        StopMic();
        BanshellConfig.SaveState(state);
        StateChanged?.Invoke();
        AlarmRequested?.Invoke(reason);
    }

    private void OnInput()
    {
        if (!Config.InputTrigger || !state.Armed || state.Triggered) return;
        if (monitoringStartsAt == null || DateTime.Now < monitoringStartsAt) return;
        Trigger("keyboard or mouse touched");
    }

    private void Tick()
    {
        tickCounter++;
        CheckAutoArm();
        if (!state.Armed || state.Triggered) return;
        if (monitoringStartsAt == null || DateTime.Now < monitoringStartsAt) return;

        if (tickCounter % 20 == 0)
        {
            EvaluateMic();
            CheckWifi();
        }

        var accelerometerAllowed = Config.MotionTrigger && MotionSensingAllowedNow();
        if (accelerometerAllowed && accelBaseline == null)
            accelBaseline = accelerometer.Read();
        if (Config.PowerTrigger && powerBaselineOnline == null)
            powerBaselineOnline = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Online;

        if (accelerometerAllowed && accelBaseline is { } baseline && accelerometer.Read() is { } reading)
        {
            var delta = AccelerometerMonitor.Delta(baseline, reading);
            if (delta >= Config.AccelDeltaG)
            {
                Trigger($"device moved ({delta:F2}g shift)");
                return;
            }
        }

        if (Config.PowerTrigger && powerBaselineOnline == true
            && SystemInformation.PowerStatus.PowerLineStatus != PowerLineStatus.Online)
        {
            Trigger("power cable disconnected");
        }
    }

    private void CheckAutoArm()
    {
        if (!Config.AutoArmDaily && !Config.AutoDisarmDaily && !Config.IdleAutoArm) return;
        var now = DateTime.Now;
        if (!Config.ScheduleDays.Contains((int)now.DayOfWeek)) return;
        var today = now.ToString("yyyy-MM-dd");
        if (Config.AutoArmDaily && !state.Armed && !state.Triggered
            && now.Hour == Config.ArmHour && now.Minute == Config.ArmMinute && state.LastAutoArmDay != today)
        {
            state.LastAutoArmDay = today;
            Arm();
        }
        if (Config.AutoDisarmDaily && state.Armed && !state.Triggered
            && now.Hour == Config.DisarmHour && now.Minute == Config.DisarmMinute && state.LastAutoDisarmDay != today)
        {
            state.LastAutoDisarmDay = today;
            Disarm();
        }
        if (Config.IdleAutoArm && !state.Armed && !state.Triggered)
        {
            int nowMinutes = now.Hour * 60 + now.Minute;
            int armMinutes = Config.ArmHour * 60 + Config.ArmMinute;
            int endMinutes = Config.AutoDisarmDaily ? Config.DisarmHour * 60 + Config.DisarmMinute : armMinutes;
            bool inWindow = Config.AutoArmDaily && InWindow(nowMinutes, armMinutes, endMinutes);
            int threshold = inWindow ? Config.IdleMinutes : Config.IdleMinutesDaytime;
            if (SystemIdleSeconds() >= threshold * 60)
                Arm();
        }
    }

    private static bool InWindow(int now, int start, int end)
    {
        if (start == end) return now >= start;
        if (start < end) return now >= start && now < end;
        return now >= start || now < end;
    }

    private static double SystemIdleSeconds()
    {
        var info = new LastInputInfo { Size = (uint)Marshal.SizeOf<LastInputInfo>() };
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.Time) / 1000.0;
    }

    private static bool WifiConnected()
    {
        try
        {
            return NetworkInterface.GetAllNetworkInterfaces().Any(nic =>
                nic.NetworkInterfaceType == NetworkInterfaceType.Wireless80211
                && nic.OperationalStatus == OperationalStatus.Up);
        }
        catch
        {
            return false;
        }
    }

    private void EvaluateMic()
    {
        if (Config.MicTrigger && mic == null)
        {
            mic = new MicLevelWin();
            mic.Loud += OnMicLoud;
            mic.Start();
        }
        else if (!Config.MicTrigger && mic != null)
        {
            mic.Loud -= OnMicLoud;
            mic.Dispose();
            mic = null;
        }
    }

    private void OnMicLoud()
    {
        if (!state.Armed || state.Triggered) return;
        if (monitoringStartsAt == null || DateTime.Now < monitoringStartsAt) return;
        Trigger("loud sound — microphone");
    }

    private void CheckWifi()
    {
        if (!Config.WifiTrigger) { wifiBaselineConnected = null; return; }
        if (wifiBaselineConnected == null)
        {
            wifiBaselineConnected = WifiConnected();
            return;
        }
        if (wifiBaselineConnected == true && !WifiConnected())
            Trigger("left Wi-Fi range — network dropped");
    }

    private void StopMic()
    {
        if (mic != null)
        {
            mic.Loud -= OnMicLoud;
            mic.Dispose();
            mic = null;
        }
    }

    private bool MotionSensingAllowedNow()
    {
        var status = SystemInformation.PowerStatus;
        bool charging = status.PowerLineStatus == PowerLineStatus.Online;
        if (charging)
        {
            if (!Config.MotionOnCharger) return false;
        }
        else
        {
            if (!Config.MotionOnBattery) return false;
            int percent = status.BatteryLifePercent >= 0 && status.BatteryLifePercent <= 1
                ? (int)(status.BatteryLifePercent * 100)
                : 100;
            if (percent < Config.MotionBatteryFloor) return false;
        }
        return true;
    }

    public void ClearTriggeredAndDisarm() => Disarm();

    public void Dispose()
    {
        tick.Stop();
        hooks.Dispose();
        StopMic();
        KeepAwake.Disable();
    }
}
