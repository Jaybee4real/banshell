namespace Banshell;

public class Watcher : IDisposable
{
    public BanshellConfig Config { get; private set; }
    private BanshellState state;
    private readonly System.Windows.Forms.Timer tick;
    private readonly AccelerometerMonitor accelerometer = new();
    private readonly InputHooks hooks = new();
    private (double X, double Y, double Z)? accelBaseline;
    private bool? powerBaselineOnline;
    private DateTime? monitoringStartsAt;

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
        tick = new System.Windows.Forms.Timer { Interval = 100 };
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
        monitoringStartsAt = null;
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
        CheckAutoArm();
        if (!state.Armed || state.Triggered) return;
        if (monitoringStartsAt == null || DateTime.Now < monitoringStartsAt) return;

        if (Config.MotionTrigger && accelBaseline == null)
            accelBaseline = accelerometer.Read();
        if (Config.PowerTrigger && powerBaselineOnline == null)
            powerBaselineOnline = SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Online;

        if (Config.MotionTrigger && accelBaseline is { } baseline && accelerometer.Read() is { } reading)
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
        if (!Config.AutoArmDaily || state.Armed || state.Triggered) return;
        var now = DateTime.Now;
        var today = now.ToString("yyyy-MM-dd");
        if (now.Hour == Config.ArmHour && now.Minute == Config.ArmMinute && state.LastAutoArmDay != today)
        {
            state.LastAutoArmDay = today;
            Arm();
        }
    }

    public void ClearTriggeredAndDisarm() => Disarm();

    public void Dispose()
    {
        tick.Stop();
        hooks.Dispose();
        KeepAwake.Disable();
    }
}
