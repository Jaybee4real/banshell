# BANSHELL

**Breach-Activated Noise Siren Halting Equipment Loss on Laptops.**

An anti-theft alarm for laptops. It arms itself every night at a time you pick. If someone moves your machine, unplugs it, or touches the keyboard while it's armed, the screen locks behind a code prompt, the volume gets forced to maximum, and a siren screams until the right code is entered. The name is the banshee, the Irish spirit whose wail can't be silenced, crossed with the clamshell your laptop actually is. The wail lives in the shell.

I built this because I wanted my MacBook to scream if anyone grabbed it at night. Turns out that's harder than it sounds, and the obvious approach doesn't work: modern Macs don't have an accelerometer. Apple removed the Sudden Motion Sensor years ago when SSDs made it pointless. What M-series MacBooks do have is a lid-angle sensor buried in the hinge, and it's sensitive enough to register a one-degree wobble when someone picks the machine up. So that's what BANSHELL watches.

## How it detects a grab

There's no single perfect signal, so it watches several at once. Any of them fires the alarm.

On macOS:

| Trigger | What it catches |
|---|---|
| Lid hinge angle (polled 20x/sec) | Lifting or carrying wobbles the hinge. Opening or closing the lid swings it massively. |
| Charger disconnect | Yanking the power cable. |
| Input tap | Any key press, click, scroll, or trackpad touch. |
| Camera motion (opt-in) | The laptop being lifted or carried with the lid open, which the hinge sensor can miss. |

Apple Silicon Macs have no accelerometer — Apple removed it years ago — so the hinge sensor is the only built-in inertial signal, and it only sees the lid move relative to the base. To catch the machine being physically moved with the lid untouched, turn on the camera motion trigger in Settings: while armed it watches the webcam for a sudden scene change. It's off by default because it lights the green camera LED and needs camera permission.

On Windows, the motion trigger uses a real accelerometer when the machine has one (many laptops and all 2-in-1s do), so it catches physical movement directly without the camera. The charger and input triggers work the same way.

The motion threshold is tunable in Settings. The default (2° on Mac, 0.06g on Windows) sits above ambient noise — the Mac hinge sensor reads dead-still at rest — and below "someone picked this up."

### Power and battery rules

Camera watching (Mac) and the accelerometer (Windows) cost battery, so both are power-aware. In Settings you choose whether they run while charging, while on battery, or both, and set a battery-floor percentage below which they switch off automatically to save power — the cheap triggers (hinge, charger, input) keep running regardless. "Keep watching when the lid is closed" controls whether BANSHELL holds the machine awake to stay armed with the lid shut, or lets it sleep to save battery.

## What happens when it fires

1. A full-screen lock takes over every display. On macOS it captures the displays outright, which disables Mission Control and the swipe-between-spaces gesture, so a thief sitting in a full-screen app can't slide past the lock. Force Quit, app switching, and log-out are disabled too. Warning beeps start.
2. You get a grace period (15 seconds by default) to type your code. This is how you disarm your own machine when you come back to it.
3. No code? Output gets forced to the built-in speakers, the volume is slammed to 100% and re-asserted every 150ms, and the siren starts. Volume keys do nothing. Plugging in headphones does nothing.
4. The siren runs until the correct code is entered. The code is stored as a salted SHA-256 hash, never in plain text.

The lock screen doubles as an owner card: your name, contact email, and a personal message, all set in Settings. Whoever is holding the machine gets told exactly whose it is while the siren makes the point. Check the design any time with `banshell preview`: same screen, no siren, Esc closes it.

On macOS, killing the process doesn't help either: launchd restarts it in under a second and it resumes the siren from saved state.

## Install

### macOS (Apple Silicon or Intel, macOS 13+)

Download `Banshell-macOS-Installer.pkg` from the [latest release](../../releases/latest) and double-click it. It's not signed with a paid Apple certificate, so macOS blocks the first open: right-click the pkg → **Open**, or approve it under System Settings → Privacy & Security → **Open Anyway**. The installer drops BANSHELL in Applications and starts the background agent for you, so there's no Terminal step. Set your disarm code in the window that appears, and it lives in the menu bar from then on.

Then two one-time grants, both a single button in Settings:

1. **Closed-lid protection.** BANSHELL keeps the Mac awake while armed so the speakers stay live with the lid shut. That needs one `pmset` sudoers entry. Click "Enable Closed-Lid Protection" in Settings and enter your admin password in the macOS prompt; the rule is checked with `visudo -cf` before it's installed. Prefer to see exactly what runs? The "copy the command instead" button gives you the same thing for Terminal.
2. **Touch trigger.** Add Banshell under System Settings → Privacy & Security → Input Monitoring.

Prefer to do it by hand? `Banshell-macOS.zip` is also attached: unzip, drag `Banshell.app` to Applications, then run `/Applications/Banshell.app/Contents/MacOS/banshell install`. There's a full CLI too (`banshell status`, `arm`, `disarm`, `drill`, `preview`, `sensors`).

### Windows (10/11, 64-bit)

Download `Banshell-Setup.exe` from the [latest release](../../releases/latest) and run it. It's not signed with a paid certificate, so SmartScreen warns the first time: click **More info → Run anyway**. Click through the installer, tick "Start BANSHELL automatically when Windows starts" if you want autostart, and it finishes by launching the app to its tray. Nothing else to install, since it's self-contained.

Set your code in the first window. One thing Windows won't let an app do quietly: keep running with the lid closed. If you want that, set the lid action to "Do nothing" in Power Options.

Prefer no installer? `Banshell-Windows-portable.zip` is also attached: unzip anywhere and run `Banshell.exe`.

## Test it before you need it

Fire a drill from the menu (Test Siren) or with `banshell drill`. The real siren sounds until you enter your code. Do this once so you know the disarm flow cold, because the first real trigger is a bad time to learn it.

## Settings

Everything lives in the Settings window: the schedule, which triggers are active, motion sensitivity with a live sensor readout, the walk-away delay (so arming doesn't trap you at your own desk), the siren delay, the disarm code, and the owner card shown on the alarm screen. Changes save immediately.

The schedule is a nightly window: pick an arm time, optionally an auto-disarm time, and the days of the week it runs. So you can have it arm at 23:00 and disarm itself at 07:00 on weekdays, and never think about it. Auto-disarm only fires when the machine is sitting armed and quiet — if the siren is already going, the schedule will not silence it, only your code will.

## Staying up to date

BANSHELL updates itself. It checks GitHub Releases on launch and every few hours, and when a newer version is out it offers to install it: on macOS it downloads the pkg and runs it behind one admin prompt, on Windows it downloads and runs the installer silently, then relaunches. You can also trigger it any time from the menu (Check for Updates) or turn the automatic check off in Settings. There's no separate update server, the provider is this repo's releases, fetched over HTTPS, so only builds published here can be offered to you.

## What this can't do

I'd rather you know the limits up front than find out from a thief.

- **A 10-second power-button hold kills any software alarm.** No app survives a hard power-off. Pair BANSHELL with FileVault + Find My (Mac) or BitLocker + Find My Device (Windows) so a powered-off stolen laptop is still a brick.
- On Windows the alarm swallows the keyboard escape routes while it's up: the Windows key (which kills Task View, Show Desktop, and the Ctrl+Win+arrow virtual-desktop switch in one go), Alt+Tab, Alt+F4, and the Ctrl+Shift+Esc Task Manager shortcut. Two things a user-mode app genuinely can't intercept: **Ctrl+Alt+Del** (it's a kernel secure-attention sequence) and the **four-finger trackpad swipe** between virtual desktops (a hardware gesture, not a keystroke). Either can hide the visual lock, but the siren keeps blaring on every desktop regardless, and there's no launchd equivalent, so a determined thief who reaches Task Manager could end the process. This is the Windows analog of the power-button hold: the noise is the real deterrent.
- If the alarm fires while the screen is locked, the thief sees the login wall with the siren blaring. You log in first, then enter the disarm code.
- The siren tops out at what laptop speakers can do. It's roughly 80dB up close: very loud in a quiet room, less dramatic in a busy cafe.
- Keeping the machine awake while armed costs battery, a few percent an hour. Arm it on the charger when you can; unplugging is itself a trigger anyway.

## Building from source

macOS: `cd macos && ./build.sh` (needs Xcode command line tools). Produces a universal `Banshell.app` in `macos/build/`.

Windows: `dotnet publish windows/Banshell.csproj -c Release -r win-x64 --self-contained` (needs the .NET 8 SDK).

Releases are built by the GitHub Actions workflow in `.github/workflows/release.yml` whenever a `v*` tag is pushed.

## License

MIT. Use it, fork it, make it scream differently.
