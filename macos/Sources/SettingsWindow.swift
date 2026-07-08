import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let watcher: Watcher
    private var window: NSWindow?
    private var config: Config
    private var autoArmCheckbox: NSButton!
    private var timePicker: NSDatePicker!
    private var lidCheckbox: NSButton!
    private var powerCheckbox: NSButton!
    private var touchCheckbox: NSButton!
    private var sensitivitySlider: NSSlider!
    private var sensitivityLabel: NSTextField!
    private var liveAngleLabel: NSTextField!
    private var exitDelayPopup: NSPopUpButton!
    private var entryDelayPopup: NSPopUpButton!
    private var readinessLid: NSTextField!
    private var readinessSudo: NSTextField!
    private var readinessInput: NSTextField!
    private var ownerNameField: NSTextField!
    private var ownerEmailField: NSTextField!
    private var ownerMessageField: NSTextField!
    private var angleTimer: Timer?
    private var sudoNotice: (message: String, until: Date)?

    private let exitChoices = [10, 30, 60, 120]
    private let entryChoices = [5, 10, 15, 30]

    init(watcher: Watcher) {
        self.watcher = watcher
        self.config = loadConfig() ?? Config.defaults
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        config = loadConfig() ?? Config.defaults
        applyConfigToControls()
        refreshReadiness()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        angleTimer?.invalidate()
        angleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateLiveAngle()
            self?.refreshReadiness()
        }
    }

    func windowWillClose(_ notification: Notification) {
        angleTimer?.invalidate()
        angleTimer = nil
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func buildWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
        panel.title = "BANSHELL Settings"
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(sectionLabel("Schedule"))
        let scheduleRow = NSStackView()
        scheduleRow.orientation = .horizontal
        scheduleRow.spacing = 8
        autoArmCheckbox = NSButton(checkboxWithTitle: "Arm automatically every day at",
                                   target: self, action: #selector(controlChanged))
        timePicker = NSDatePicker()
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = .hourMinute
        timePicker.target = self
        timePicker.action = #selector(controlChanged)
        scheduleRow.addArrangedSubview(autoArmCheckbox)
        scheduleRow.addArrangedSubview(timePicker)
        stack.addArrangedSubview(scheduleRow)

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Triggers"))
        lidCheckbox = NSButton(checkboxWithTitle: "Motion — lid hinge angle changes",
                               target: self, action: #selector(controlChanged))
        stack.addArrangedSubview(lidCheckbox)

        let sensitivityRow = NSStackView()
        sensitivityRow.orientation = .horizontal
        sensitivityRow.spacing = 8
        let sensitivityCaption = NSTextField(labelWithString: "Sensitivity:")
        sensitivitySlider = NSSlider(value: 3, minValue: 1, maxValue: 10,
                                     target: self, action: #selector(controlChanged))
        sensitivitySlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        sensitivityLabel = NSTextField(labelWithString: "3°")
        liveAngleLabel = NSTextField(labelWithString: "")
        liveAngleLabel.textColor = .secondaryLabelColor
        liveAngleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sensitivityRow.addArrangedSubview(indent())
        sensitivityRow.addArrangedSubview(sensitivityCaption)
        sensitivityRow.addArrangedSubview(sensitivitySlider)
        sensitivityRow.addArrangedSubview(sensitivityLabel)
        sensitivityRow.addArrangedSubview(liveAngleLabel)
        stack.addArrangedSubview(sensitivityRow)

        powerCheckbox = NSButton(checkboxWithTitle: "Charger disconnected",
                                 target: self, action: #selector(controlChanged))
        stack.addArrangedSubview(powerCheckbox)
        touchCheckbox = NSButton(checkboxWithTitle: "Keyboard or trackpad touched",
                                 target: self, action: #selector(controlChanged))
        stack.addArrangedSubview(touchCheckbox)

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Timing"))
        let timingRow = NSStackView()
        timingRow.orientation = .horizontal
        timingRow.spacing = 8
        exitDelayPopup = NSPopUpButton()
        for choice in exitChoices { exitDelayPopup.addItem(withTitle: "\(choice)s") }
        exitDelayPopup.target = self
        exitDelayPopup.action = #selector(controlChanged)
        entryDelayPopup = NSPopUpButton()
        for choice in entryChoices { entryDelayPopup.addItem(withTitle: "\(choice)s") }
        entryDelayPopup.target = self
        entryDelayPopup.action = #selector(controlChanged)
        timingRow.addArrangedSubview(NSTextField(labelWithString: "Walk-away delay"))
        timingRow.addArrangedSubview(exitDelayPopup)
        timingRow.addArrangedSubview(NSTextField(labelWithString: "   Siren delay after trigger"))
        timingRow.addArrangedSubview(entryDelayPopup)
        stack.addArrangedSubview(timingRow)

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Security"))
        let pinButton = NSButton(title: "Change Disarm Code…", target: self, action: #selector(changePin))
        stack.addArrangedSubview(pinButton)

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Owner Card — shown on the alarm screen"))
        ownerNameField = NSTextField(string: "")
        ownerNameField.placeholderString = "Your name"
        ownerEmailField = NSTextField(string: "")
        ownerEmailField.placeholderString = "Contact email"
        ownerMessageField = NSTextField(wrappingLabelWithString: "")
        ownerMessageField.isEditable = true
        ownerMessageField.isBezeled = true
        ownerMessageField.isSelectable = true
        ownerMessageField.placeholderString = "Personal message, e.g. \"This laptop is protected and traceable. Return it.\""
        for field in [ownerNameField, ownerEmailField, ownerMessageField] {
            field!.translatesAutoresizingMaskIntoConstraints = false
            field!.widthAnchor.constraint(equalToConstant: 400).isActive = true
            field!.delegate = self
            stack.addArrangedSubview(field!)
        }
        ownerMessageField.heightAnchor.constraint(equalToConstant: 52).isActive = true

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Readiness"))
        readinessLid = NSTextField(labelWithString: "")
        stack.addArrangedSubview(readinessLid)
        readinessSudo = NSTextField(labelWithString: "")
        stack.addArrangedSubview(readinessSudo)
        let sudoRow = NSStackView()
        sudoRow.orientation = .horizontal
        let enableSudoButton = NSButton(title: "Enable Closed-Lid Protection…",
                                        target: self, action: #selector(enableClosedLid))
        enableSudoButton.keyEquivalent = ""
        let copySudoButton = NSButton(title: "Copy Terminal Command Instead",
                                      target: self, action: #selector(copySudoCommand))
        sudoRow.addArrangedSubview(indent())
        sudoRow.addArrangedSubview(enableSudoButton)
        sudoRow.addArrangedSubview(copySudoButton)
        stack.addArrangedSubview(sudoRow)
        readinessInput = NSTextField(labelWithString: "")
        stack.addArrangedSubview(readinessInput)
        let grantRow = NSStackView()
        grantRow.orientation = .horizontal
        let grantButton = NSButton(title: "Open Input Monitoring Settings",
                                   target: self, action: #selector(openInputMonitoring))
        grantRow.addArrangedSubview(indent())
        grantRow.addArrangedSubview(grantButton)
        stack.addArrangedSubview(grantRow)

        stack.addArrangedSubview(spacer(8))
        let footer = NSTextField(labelWithString: "Changes save immediately. A 10-second power-button hold defeats any software alarm — keep FileVault and Find My on.")
        footer.font = NSFont.systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byWordWrapping
        footer.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(footer)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        panel.contentView = content
        panel.setContentSize(NSSize(width: 470, height: 720))
        window = panel
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func indent() -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func applyConfigToControls() {
        autoArmCheckbox.state = config.autoArmDaily ? .on : .off
        var components = DateComponents()
        components.hour = config.armHour
        components.minute = config.armMinute
        timePicker.dateValue = Calendar.current.date(from: components) ?? Date()
        lidCheckbox.state = config.lidTrigger ? .on : .off
        powerCheckbox.state = config.powerTrigger ? .on : .off
        touchCheckbox.state = config.inputTrigger ? .on : .off
        sensitivitySlider.doubleValue = config.lidDeltaDegrees
        sensitivityLabel.stringValue = "\(Int(config.lidDeltaDegrees))°"
        exitDelayPopup.selectItem(at: exitChoices.firstIndex(of: config.exitDelaySeconds) ?? 1)
        entryDelayPopup.selectItem(at: entryChoices.firstIndex(of: config.entryDelaySeconds) ?? 2)
        ownerNameField.stringValue = config.ownerName ?? ""
        ownerEmailField.stringValue = config.ownerEmail ?? ""
        ownerMessageField.stringValue = config.ownerMessage ?? ""
    }

    func controlTextDidChange(_ notification: Notification) {
        config.ownerName = ownerNameField.stringValue
        config.ownerEmail = ownerEmailField.stringValue
        config.ownerMessage = ownerMessageField.stringValue
        saveConfig(config)
        watcher.reloadConfig(config)
    }

    @objc private func controlChanged() {
        config.autoArmDaily = autoArmCheckbox.state == .on
        let components = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        config.armHour = components.hour ?? config.armHour
        config.armMinute = components.minute ?? config.armMinute
        config.lidTrigger = lidCheckbox.state == .on
        config.powerTrigger = powerCheckbox.state == .on
        config.inputTrigger = touchCheckbox.state == .on
        config.lidDeltaDegrees = Double(Int(sensitivitySlider.doubleValue))
        sensitivityLabel.stringValue = "\(Int(config.lidDeltaDegrees))°"
        config.exitDelaySeconds = exitChoices[max(0, exitDelayPopup.indexOfSelectedItem)]
        config.entryDelaySeconds = entryChoices[max(0, entryDelayPopup.indexOfSelectedItem)]
        saveConfig(config)
        watcher.reloadConfig(config)
    }

    private func updateLiveAngle() {
        if let angle = watcher.lidSensor.readAngle() {
            liveAngleLabel.stringValue = "lid now: \(Int(angle))°"
        } else {
            liveAngleLabel.stringValue = ""
        }
    }

    private func refreshReadiness() {
        readinessLid.stringValue = watcher.lidSensor.available
            ? "✅ Lid-angle sensor detected"
            : "❌ No lid-angle sensor — motion trigger unavailable on this Mac"
        if let notice = sudoNotice, Date() < notice.until {
            readinessSudo.stringValue = notice.message
        } else {
            sudoNotice = nil
            readinessSudo.stringValue = sudoersReady()
                ? "✅ Closed-lid protection ready"
                : "❌ Closed-lid protection off — click Enable below (asks for your password once)"
        }
        readinessInput.stringValue = inputMonitoringGranted()
            ? "✅ Touch trigger permission granted"
            : "❌ Touch trigger needs Input Monitoring permission"
    }

    @objc private func enableClosedLid() {
        switch installSudoersRuleWithPrompt() {
        case .installed, .cancelled:
            sudoNotice = nil
        case .failed(let message):
            sudoNotice = ("❌ Could not enable: \(message)", Date().addingTimeInterval(10))
        }
        refreshReadiness()
    }

    @objc private func copySudoCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sudoersCommand, forType: .string)
        sudoNotice = ("📋 Copied — paste into Terminal, enter your password, then re-open Settings",
                      Date().addingTimeInterval(8))
        refreshReadiness()
    }

    @objc private func openInputMonitoring() {
        requestInputMonitoring()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func changePin() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Change Disarm Code"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let container = NSStackView(frame: NSRect(x: 0, y: 0, width: 240, height: 96))
        container.orientation = .vertical
        container.spacing = 8
        let currentField = NSSecureTextField(frame: .zero)
        currentField.placeholderString = "Current code"
        let newField = NSSecureTextField(frame: .zero)
        newField.placeholderString = "New code (min 4 chars)"
        let confirmField = NSSecureTextField(frame: .zero)
        confirmField.placeholderString = "Confirm new code"
        for field in [currentField, newField, confirmField] {
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
            container.addArrangedSubview(field)
        }
        alert.accessoryView = container
        alert.window.initialFirstResponder = config.hasPin ? currentField : newField
        currentField.isHidden = !config.hasPin
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if config.hasPin, !verifyPin(currentField.stringValue, config: config) {
            showError("Current code is wrong.", on: window)
            return
        }
        guard newField.stringValue.count >= 4 else {
            showError("New code must be at least 4 characters.", on: window)
            return
        }
        guard newField.stringValue == confirmField.stringValue else {
            showError("Codes do not match.", on: window)
            return
        }
        config.pinSaltHex = randomSaltHex()
        config.pinHashHex = hashPin(newField.stringValue, saltHex: config.pinSaltHex)
        saveConfig(config)
        watcher.reloadConfig(config)
    }

    private func showError(_ message: String, on window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .critical
        alert.beginSheetModal(for: window)
    }
}

final class FirstRunWindowController: NSObject {
    private var window: NSWindow?
    private let onComplete: () -> Void
    private var newField: NSSecureTextField!
    private var confirmField: NSSecureTextField!
    private var errorLabel: NSTextField!

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func show() {
        if window == nil { buildWindow() }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                             styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Welcome to BANSHELL"
        panel.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let banner = NSTextField(labelWithString: "🚨")
        banner.font = NSFont.systemFont(ofSize: 44)
        stack.addArrangedSubview(banner)

        let title = NSTextField(labelWithString: "Set your disarm code")
        title.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "This code is the only thing that silences the siren.\nDo not forget it.")
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        newField = NSSecureTextField(frame: .zero)
        newField.placeholderString = "Code (min 4 characters)"
        newField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(newField)

        confirmField = NSSecureTextField(frame: .zero)
        confirmField.placeholderString = "Confirm code"
        confirmField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(confirmField)

        errorLabel = NSTextField(labelWithString: "")
        errorLabel.textColor = .systemRed
        stack.addArrangedSubview(errorLabel)

        let saveButton = NSButton(title: "Set Code", target: self, action: #selector(saveTapped))
        saveButton.keyEquivalent = "\r"
        stack.addArrangedSubview(saveButton)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        panel.contentView = content
        panel.setContentSize(NSSize(width: 420, height: 320))
        window = panel
    }

    @objc private func saveTapped() {
        guard newField.stringValue.count >= 4 else {
            errorLabel.stringValue = "Code must be at least 4 characters."
            return
        }
        guard newField.stringValue == confirmField.stringValue else {
            errorLabel.stringValue = "Codes do not match."
            return
        }
        var config = loadConfig() ?? Config.defaults
        config.pinSaltHex = randomSaltHex()
        config.pinHashHex = hashPin(newField.stringValue, saltHex: config.pinSaltHex)
        saveConfig(config)
        window?.orderOut(nil)
        window?.close()
        onComplete()
    }
}
