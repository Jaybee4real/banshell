# BANSHELL

**Breach-Activated Noise Siren Halting Equipment Loss on Laptops.**

An anti-theft alarm for laptops. It arms itself every night at a time you pick. If someone moves your machine, unplugs it, or touches the keyboard while it's armed, the screen locks behind a code prompt, the volume gets forced to maximum, and a siren screams until the right code is entered. The name is the banshee, the Irish spirit whose wail can't be silenced, crossed with the clamshell your laptop actually is. The wail lives in the shell.

I built this because I wanted my MacBook to scream if anyone grabbed it at night. Turns out that's harder than it sounds, and the obvious approach doesn't work: modern Macs don't have an accelerometer. Apple removed the Sudden Motion Sensor years ago when SSDs made it pointless. What M-series MacBooks do have is a lid-angle sensor buried in the hinge, and it's sensitive enough to register a one-degree wobble when someone picks the machine up. So that's what BANSHELL watches.

## How it detects a grab

There's no single perfect signal, so it watches three at once. Any of them fires the alarm.

On macOS:

| Trigger | What it catches |
|---|---|
| Lid hinge angle (polled 10x/sec) | Lifting or carrying wobbles the hinge. Opening or closing the lid swings it massively. |
| Charger disconnect | Yanking the power cable. |
| Input tap | Any key press, click, scroll, or trackpad touch. |

On Windows, the motion trigger uses a real accelerometer when the machine has one (many Windows laptops and all 2-in-1s do). The charger and input triggers work the same way.

The motion threshold is tunable in Settings. The default (3° on Mac, 0.06g on Windows) sits above ambient desk vibration and below "someone picked this up."

## What happens when it fires

1. A full-screen lock takes over every display. Force Quit, app switching, and log-out are disabled. Warning beeps start.
2. You get a grace period (15 seconds by default) to type your code. This is how you disarm your own machine when you come back to it.
3. No code? Output gets forced to the built-in speakers, the volume is slammed to 100% and re-asserted every 150ms, and the siren starts. Volume keys do nothing. Plugging in headphones does nothing.
4. The siren runs until the correct code is entered. The code is stored as a salted SHA-256 hash, never in plain text.

On macOS, killing the process doesn't help either: launchd restarts it in under a second and it resumes the siren from saved state.

## Install

### macOS (Apple Silicon or Intel, macOS 13+)

Download `Banshell-macOS.zip` from the [latest release](../../releases/latest), unzip, and drag `Banshell.app` to Applications. The app is self-signed, so the first launch needs a right-click → Open, or:

```
xattr -dr com.apple.quarantine /Applications/Banshell.app
```

Launch it, set your disarm code, and it lives in the menu bar. Then two one-time grants, both shown in Settings with a button each:

1. **Closed-lid protection.** BANSHELL keeps the Mac awake while armed so the speakers stay live with the lid shut. That needs one `pmset` sudoers entry. Click "Enable Closed-Lid Protection" in Settings and enter your admin password in the macOS prompt; the rule is checked with `visudo -cf` before it's installed. Prefer to see exactly what runs? The "copy the command instead" button gives you the same thing for Terminal.
2. **Touch trigger.** Add Banshell under System Settings → Privacy & Security → Input Monitoring.

To make it start at login and respawn if killed:

```
/Applications/Banshell.app/Contents/MacOS/banshell install
```

There's a full CLI too (`banshell status`, `arm`, `disarm`, `drill`, `sensors`) if you'd rather script it.

### Windows (10/11, 64-bit)

Download `Banshell-Windows.zip` from the [latest release](../../releases/latest), unzip anywhere, run `Banshell.exe`. It's self-contained, so there is no runtime to install. SmartScreen will warn about an unsigned app the first time; choose "Run anyway."

Set your code, then in Settings tick "Start BANSHELL when Windows starts." One thing Windows won't let an app do quietly: keep running with the lid closed. If you want that, set the lid action to "Do nothing" in Power Options.

## Test it before you need it

Fire a drill from the menu (Test Siren) or with `banshell drill`. The real siren sounds until you enter your code. Do this once so you know the disarm flow cold, because the first real trigger is a bad time to learn it.

## Settings

Everything lives in the Settings window: arm time, which triggers are active, motion sensitivity with a live sensor readout, the walk-away delay (so arming doesn't trap you at your own desk), the siren delay, and the disarm code. Changes save immediately.

## What this can't do

I'd rather you know the limits up front than find out from a thief.

- **A 10-second power-button hold kills any software alarm.** No app survives a hard power-off. Pair BANSHELL with FileVault + Find My (Mac) or BitLocker + Find My Device (Windows) so a powered-off stolen laptop is still a brick.
- On Windows there's no launchd equivalent baked in, so someone who already has your session unlocked could end the process from Task Manager. In practice the machine is locked while armed, so this matters less than it sounds.
- If the alarm fires while the screen is locked, the thief sees the login wall with the siren blaring. You log in first, then enter the disarm code.
- The siren tops out at what laptop speakers can do. It's roughly 80dB up close: very loud in a quiet room, less dramatic in a busy cafe.
- Keeping the machine awake while armed costs battery, a few percent an hour. Arm it on the charger when you can; unplugging is itself a trigger anyway.

## Building from source

macOS: `cd macos && ./build.sh` (needs Xcode command line tools). Produces a universal `Banshell.app` in `macos/build/`.

Windows: `dotnet publish windows/Banshell.csproj -c Release -r win-x64 --self-contained` (needs the .NET 8 SDK).

Releases are built by the GitHub Actions workflow in `.github/workflows/release.yml` whenever a `v*` tag is pushed.

## License

MIT. Use it, fork it, make it scream differently.
