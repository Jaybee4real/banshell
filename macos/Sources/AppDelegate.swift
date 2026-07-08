import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var watcher: Watcher?
    private var settingsController: SettingsWindowController?
    private var firstRunController: FirstRunWindowController?
    private var statusMenuItem: NSMenuItem?
    private var readinessMenuItem: NSMenuItem?
    private var armMenuItem: NSMenuItem?
    private var disarmMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettingsRequested),
            name: Notification.Name("com.jaybee.banshell.showSettings"), object: nil)
        let config = loadConfig() ?? Config.defaults
        if !config.hasPin {
            saveConfig(config)
            showFirstRun()
        }
        let watcherInstance = Watcher(config: loadConfig() ?? config)
        watcherInstance.onChange = { [weak self] armed, triggered in
            self?.refreshMenu(armed: armed, triggered: triggered)
        }
        watcher = watcherInstance
        watcherInstance.start()
        refreshMenu(armed: watcherInstance.uiArmed, triggered: watcherInstance.uiTriggered)
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = menuIcon(name: "shield")
        let menu = NSMenu()

        let statusLine = NSMenuItem(title: "BANSHELL — starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        statusMenuItem = statusLine

        let readinessLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        readinessLine.isEnabled = false
        readinessLine.isHidden = true
        menu.addItem(readinessLine)
        readinessMenuItem = readinessLine

        menu.addItem(.separator())

        let armItem = NSMenuItem(title: "Arm Now", action: #selector(armNow), keyEquivalent: "")
        armItem.target = self
        menu.addItem(armItem)
        armMenuItem = armItem

        let disarmItem = NSMenuItem(title: "Disarm…", action: #selector(disarmTapped), keyEquivalent: "")
        disarmItem.target = self
        menu.addItem(disarmItem)
        disarmMenuItem = disarmItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let drillItem = NSMenuItem(title: "Test Siren (Drill)…", action: #selector(drillTapped), keyEquivalent: "")
        drillItem.target = self
        menu.addItem(drillItem)

        let logItem = NSMenuItem(title: "View Log", action: #selector(viewLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit BANSHELL", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func menuIcon(name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "BANSHELL")
        image?.isTemplate = true
        return image
    }

    private func refreshMenu(armed: Bool, triggered: Bool) {
        if triggered {
            statusItem?.button?.image = menuIcon(name: "bell.and.waves.left.and.right.fill")
            statusMenuItem?.title = "BANSHELL — ALARM ACTIVE"
        } else if armed {
            statusItem?.button?.image = menuIcon(name: "shield.fill")
            statusMenuItem?.title = "BANSHELL — Armed"
        } else {
            statusItem?.button?.image = menuIcon(name: "shield")
            let config = loadConfig() ?? Config.defaults
            statusMenuItem?.title = config.autoArmDaily
                ? String(format: "BANSHELL — Disarmed · arms at %02d:%02d", config.armHour, config.armMinute)
                : "BANSHELL — Disarmed"
        }
        armMenuItem?.isHidden = armed
        disarmMenuItem?.isHidden = !armed
        let sudoOK = sudoersReady()
        readinessMenuItem?.isHidden = sudoOK
        if !sudoOK {
            readinessMenuItem?.title = "⚠ Closed-lid protection off — open Settings"
        }
    }

    @objc private func armNow() {
        watcher?.armNow()
    }

    @objc private func disarmTapped() {
        guard let config = loadConfig() else { return }
        if let pin = promptForPin(message: "Enter your disarm code"), verifyPin(pin, config: config) {
            watcher?.disarmNow()
        } else {
            let alert = NSAlert()
            alert.messageText = "Wrong code"
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    @objc private func drillTapped() {
        let alert = NSAlert()
        alert.messageText = "Fire a live drill?"
        alert.informativeText = "The real siren will sound at full volume and the screen will lock until you enter your disarm code."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Fire Drill")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            watcher?.drill()
        }
    }

    @objc private func showSettings() {
        guard let watcher else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(watcher: watcher)
        }
        settingsController?.show()
    }

    @objc private func showSettingsRequested() {
        showSettings()
    }

    private func showFirstRun() {
        if firstRunController == nil {
            firstRunController = FirstRunWindowController { [weak self] in
                self?.firstRunController = nil
                self?.showSettings()
            }
        }
        firstRunController?.show()
    }

    @objc private func viewLog() {
        NSWorkspace.shared.open(Paths.logFile)
    }

    @objc private func quitTapped() {
        if watcher?.uiArmed == true {
            guard let config = loadConfig(),
                  let pin = promptForPin(message: "BANSHELL is armed. Enter your disarm code to quit."),
                  verifyPin(pin, config: config) else { return }
        }
        runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"])
        let uid = getuid()
        runProcess("/bin/launchctl", ["bootout", "gui/\(uid)/\(launchdLabel)"])
        NSApp.terminate(nil)
    }

    func promptForPin(message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
