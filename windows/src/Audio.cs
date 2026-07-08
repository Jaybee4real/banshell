using System.Media;
using System.Runtime.InteropServices;

namespace Banshell;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator
{
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice
{
    int Activate(ref Guid interfaceId, int classContext, IntPtr activationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object activated);
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioEndpointVolume
{
    int RegisterControlChangeNotify(IntPtr notify);
    int UnregisterControlChangeNotify(IntPtr notify);
    int GetChannelCount(out uint channelCount);
    int SetMasterVolumeLevel(float levelDb, ref Guid eventContext);
    int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
    int GetMasterVolumeLevel(out float levelDb);
    int GetMasterVolumeLevelScalar(out float level);
    int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid eventContext);
    int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid eventContext);
    int GetChannelVolumeLevel(uint channel, out float levelDb);
    int GetChannelVolumeLevelScalar(uint channel, out float level);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}

public static class VolumeControl
{
    private static IAudioEndpointVolume? GetEndpointVolume()
    {
        try
        {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
            enumerator.GetDefaultAudioEndpoint(0, 1, out var device);
            var volumeGuid = typeof(IAudioEndpointVolume).GUID;
            device.Activate(ref volumeGuid, 1, IntPtr.Zero, out var activated);
            return (IAudioEndpointVolume)activated;
        }
        catch
        {
            return null;
        }
    }

    public static float? ReadVolume()
    {
        var endpoint = GetEndpointVolume();
        if (endpoint == null) return null;
        endpoint.GetMasterVolumeLevelScalar(out var level);
        return level;
    }

    public static void SetVolume(float level)
    {
        var endpoint = GetEndpointVolume();
        if (endpoint == null) return;
        var context = Guid.Empty;
        endpoint.SetMasterVolumeLevelScalar(level, ref context);
        endpoint.SetMute(false, ref context);
    }
}

public static class SirenAudio
{
    private static SoundPlayer? currentPlayer;

    private static byte[] BuildWav(Func<double, double> sampleAt, double durationSeconds)
    {
        const int sampleRate = 44100;
        int frameCount = (int)(sampleRate * durationSeconds);
        int dataSize = frameCount * 2;
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8.ToArray());
        writer.Write(36 + dataSize);
        writer.Write("WAVE"u8.ToArray());
        writer.Write("fmt "u8.ToArray());
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)1);
        writer.Write(sampleRate);
        writer.Write(sampleRate * 2);
        writer.Write((short)2);
        writer.Write((short)16);
        writer.Write("data"u8.ToArray());
        writer.Write(dataSize);
        for (int frame = 0; frame < frameCount; frame++)
        {
            double timeSeconds = (double)frame / sampleRate;
            double sample = Math.Clamp(sampleAt(timeSeconds), -1.0, 1.0);
            writer.Write((short)(sample * short.MaxValue));
        }
        return stream.ToArray();
    }

    private static readonly Lazy<byte[]> BeepWav = new(() =>
    {
        double phase = 0;
        return BuildWav(timeSeconds =>
        {
            double cyclePosition = timeSeconds % 0.5;
            if (cyclePosition >= 0.12) return 0;
            phase += 2 * Math.PI * 950.0 / 44100;
            return Math.Sin(phase) * 0.6;
        }, 2.0);
    });

    private static readonly Lazy<byte[]> SirenWav = new(() =>
    {
        double phase = 0;
        return BuildWav(timeSeconds =>
        {
            double sweep = 0.5 - 0.5 * Math.Cos(2 * Math.PI * timeSeconds / 1.3);
            double frequency = 650 + (1500 - 650) * sweep;
            phase += 2 * Math.PI * frequency / 44100;
            return Math.Tanh(3.0 * Math.Sin(phase));
        }, 2.6);
    });

    public static void PlayBeeps()
    {
        Stop();
        currentPlayer = new SoundPlayer(new MemoryStream(BeepWav.Value));
        currentPlayer.PlayLooping();
    }

    public static void PlaySiren()
    {
        Stop();
        currentPlayer = new SoundPlayer(new MemoryStream(SirenWav.Value));
        currentPlayer.PlayLooping();
    }

    public static void Stop()
    {
        currentPlayer?.Stop();
        currentPlayer?.Dispose();
        currentPlayer = null;
    }
}
