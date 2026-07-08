import AppKit
import Foundation

func requirePinInTerminal(_ config: Config) -> Bool {
    let attempt = readSecret("Disarm code: ")
    if verifyPin(attempt, config: config) { return true }
    print("Wrong code.")
    return false
}

func commandInstall() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>\(launchdLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(binaryPath())</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key>
        <dict>
            <key>SuccessfulExit</key><false/>
        </dict>
        <key>StandardOutPath</key><string>\(Paths.logFile.path)</string>
        <key>StandardErrorPath</key><string>\(Paths.logFile.path)</string>
    </dict>
    </plist>
    """
    try? FileManager.default.createDirectory(at: Paths.agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? plist.write(to: Paths.agentPlist, atomically: true, encoding: .utf8)
    let uid = getuid()
    runProcess("/bin/launchctl", ["bootout", "gui/\(uid)", Paths.agentPlist.path])
    let status = runProcess("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.agentPlist.path])
    print(status == 0 ? "BANSHELL installed — menu bar icon is up, respawns if killed, starts at login."
                      : "Wrote \(Paths.agentPlist.path) but launchctl bootstrap failed (\(status)).")
    print("""

    For closed-lid protection, allow pmset without a password (one time):

    \(sudoersCommand)

    For the touch trigger: System Settings → Privacy & Security → Input Monitoring → add Banshell.
    """)
}

func commandUninstall() {
    let uid = getuid()
    runProcess("/bin/launchctl", ["bootout", "gui/\(uid)", Paths.agentPlist.path])
    try? FileManager.default.removeItem(at: Paths.agentPlist)
    runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"])
    print("Watcher removed. Config kept at \(Paths.supportDir.path).")
}

func commandStatus() {
    guard let config = loadConfig(), config.hasPin else {
        print("Not configured — launch Banshell.app and set a disarm code.")
        return
    }
    let state = loadState()
    let uid = getuid()
    let agentLoaded = runProcess("/bin/launchctl", ["print", "gui/\(uid)/\(launchdLabel)"]) == 0
    let sensor = LidSensor()
    print("""
    BANSHELL v\(banshellVersion)
      state:        \(state.triggered ? "TRIGGERED" : state.armed ? "ARMED" : "disarmed")
      watcher:      \(agentLoaded ? "running (launchd)" : "NOT RUNNING — run `banshell install`")
      auto-arm:     \(config.autoArmDaily ? String(format: "daily at %02d:%02d", config.armHour, config.armMinute) : "off")
      lid sensor:   \(sensor.available ? "ok (\(sensor.readAngle().map { "\(Int($0))°" } ?? "?"))" : "unavailable")
      power:        \(onACPower() ? "AC" : "battery")
      closed-lid:   \(sudoersReady() ? "ready (sudoers ok)" : "NOT READY — sudoers entry missing")
      touch:        \(inputMonitoringGranted() ? "permission granted" : "needs Input Monitoring permission")
      triggers:     lid=\(config.lidTrigger) power=\(config.powerTrigger) touch=\(config.inputTrigger)
      sensitivity:  \(config.lidDeltaDegrees)° · exit delay \(config.exitDelaySeconds)s · entry delay \(config.entryDelaySeconds)s
    """)
}

func commandSensors() {
    let sensor = LidSensor()
    print("Live sensor feed (10s) — move the lid to see the angle change:")
    for _ in 0..<20 {
        let angle = sensor.readAngle().map { "\(Int($0))°" } ?? "n/a"
        print("  lid: \(angle)   power: \(onACPower() ? "AC" : "battery")")
        usleep(500_000)
    }
}

func runCLI(_ command: String) {
    switch command {
    case "setpin":
        guard var config = loadConfig() else { print("Launch Banshell.app first."); exit(1) }
        if config.hasPin, !requirePinInTerminal(config) { exit(1) }
        let pin = readSecret("New disarm code: ")
        guard pin.count >= 4, pin == readSecret("Confirm code: ") else { print("Aborted."); exit(1) }
        config.pinSaltHex = randomSaltHex()
        config.pinHashHex = hashPin(pin, saltHex: config.pinSaltHex)
        saveConfig(config)
        print("Code updated.")
    case "arm":
        guard loadConfig()?.hasPin == true else { print("Launch Banshell.app and set a code first."); exit(1) }
        var state = loadState()
        state.armed = true
        state.triggered = false
        saveState(state)
        print("Arming — watcher picks it up within a second (walk-away delay applies).")
    case "disarm":
        guard let config = loadConfig() else { print("Launch Banshell.app first."); exit(1) }
        guard requirePinInTerminal(config) else { exit(1) }
        var state = loadState()
        if state.triggered {
            print("Alarm is TRIGGERED — enter the code on the alarm screen to stop it.")
            exit(1)
        }
        state.armed = false
        saveState(state)
        print("Disarmed.")
    case "drill":
        guard loadConfig()?.hasPin == true else { print("Launch Banshell.app and set a code first."); exit(1) }
        print("Firing a live drill in 3 seconds — the siren WILL sound until you enter your code.")
        sleep(3)
        var state = loadState()
        state.armed = true
        state.triggered = true
        state.reason = "drill"
        saveState(state)
    case "watch":
        guard let config = loadConfig(), config.hasPin else {
            logLine("no config — launch Banshell.app and set a disarm code first")
            exit(1)
        }
        let watcher = Watcher(config: config)
        watcher.start()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    case "install":
        commandInstall()
    case "uninstall":
        commandUninstall()
    case "status":
        commandStatus()
    case "sensors":
        commandSensors()
    case "version":
        print("BANSHELL v\(banshellVersion)")
    default:
        print("""
        BANSHELL v\(banshellVersion) — Breach-Activated Noise Siren Halting Equipment Loss on Laptops

        Launch with no arguments for the menu bar app, or:

          install     install + start at login (launchd, respawns if killed)
          status      state and readiness checklist
          arm         arm now
          disarm      disarm (asks for code)
          drill       test the full alarm right now
          sensors     live lid-angle / power feed
          setpin      change the disarm code
          uninstall   stop and remove the watcher
        """)
    }
}
