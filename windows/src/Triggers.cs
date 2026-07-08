using System.Runtime.InteropServices;
using Windows.Devices.Sensors;

namespace Banshell;

public class AccelerometerMonitor
{
    private readonly Accelerometer? sensor;
    private double latestX, latestY, latestZ;
    private volatile bool hasReading;

    public AccelerometerMonitor()
    {
        sensor = Accelerometer.GetDefault();
        if (sensor != null)
        {
            sensor.ReportInterval = Math.Max(sensor.MinimumReportInterval, 100);
            sensor.ReadingChanged += (_, args) =>
            {
                latestX = args.Reading.AccelerationX;
                latestY = args.Reading.AccelerationY;
                latestZ = args.Reading.AccelerationZ;
                hasReading = true;
            };
        }
    }

    public bool Available => sensor != null;

    public (double X, double Y, double Z)? Read()
    {
        if (!hasReading) return null;
        return (latestX, latestY, latestZ);
    }

    public static double Delta((double X, double Y, double Z) first, (double X, double Y, double Z) second)
    {
        double dx = first.X - second.X;
        double dy = first.Y - second.Y;
        double dz = first.Z - second.Z;
        return Math.Sqrt(dx * dx + dy * dy + dz * dz);
    }
}

public class InputHooks : IDisposable
{
    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookExW(int hookId, HookProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandleW(string? moduleName);

    private const int WH_KEYBOARD_LL = 13;
    private const int WH_MOUSE_LL = 14;

    private IntPtr keyboardHook;
    private IntPtr mouseHook;
    private readonly HookProc keyboardProc;
    private readonly HookProc mouseProc;

    public event Action? InputDetected;

    public InputHooks()
    {
        keyboardProc = OnHook;
        mouseProc = OnHook;
    }

    public void Start()
    {
        var module = GetModuleHandleW(null);
        if (keyboardHook == IntPtr.Zero)
            keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardProc, module, 0);
        if (mouseHook == IntPtr.Zero)
            mouseHook = SetWindowsHookExW(WH_MOUSE_LL, mouseProc, module, 0);
    }

    private IntPtr OnHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0) InputDetected?.Invoke();
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
        if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
        keyboardHook = IntPtr.Zero;
        mouseHook = IntPtr.Zero;
    }
}

public static class KeepAwake
{
    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint flags);

    private const uint ES_CONTINUOUS = 0x80000000;
    private const uint ES_SYSTEM_REQUIRED = 0x00000001;

    public static void Enable() => SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED);

    public static void Disable() => SetThreadExecutionState(ES_CONTINUOUS);
}
