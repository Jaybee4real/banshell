import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let watcher: Watcher
    private var window: NSWindow?
    private var config: Config
    private var autoArmCheckbox: NSButton!
    private var timePicker: NSDatePicker!
    private var autoDisarmCheckbox: NSButton!
    private var disarmTimePicker: NSDatePicker!
    private var dayButtons: [NSButton] = []
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
    private var autoUpdateCheckbox: NSButton!
    private var idleAutoArmCheckbox: NSButton!
    private var idleMinutesField: NSTextField!
    private var daytimeIdleField: NSTextField!
    private var wifiCheckbox: NSButton!
    private var micCheckbox: NSButton!
    private var micGrantButton: NSButton!
    private var cameraGrantButton: NSButton!
    private var cameraCheckbox: NSButton!
    private var cameraStatusLabel: NSTextField!
    private var onChargerCheckbox: NSButton!
    private var onBatteryCheckbox: NSButton!
    private var batteryFloorSlider: NSSlider!
    private var batteryFloorLabel: NSTextField!
    private var lidClosedCheckbox: NSButton!
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
            self?.updateCameraStatus()
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

        let disarmRow = NSStackView()
        disarmRow.orientation = .horizontal
        disarmRow.spacing = 8
        autoDisarmCheckbox = NSButton(checkboxWithTitle: "Disarm automatically at",
                                      target: self, action: #selector(controlChanged))
        disarmTimePicker = NSDatePicker()
        disarmTimePicker.datePickerStyle = .textFieldAndStepper
        disarmTimePicker.datePickerElements = .hourMinute
        disarmTimePicker.target = self
        disarmTimePicker.action = #selector(controlChanged)
        disarmRow.addArrangedSubview(autoDisarmCheckbox)
        disarmRow.addArrangedSubview(disarmTimePicker)
        stack.addArrangedSubview(disarmRow)

        let daysRow = NSStackView()
        daysRow.orientation = .horizontal
        daysRow.spacing = 4
        daysRow.addArrangedSubview(NSTextField(labelWithString: "Days:"))
        let dayNames = ["S", "M", "T", "W", "T", "F", "S"]
        for index in 0..<7 {
            let button = NSButton(title: dayNames[index], target: self, action: #selector(dayToggled(_:)))
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.tag = index + 1
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            dayButtons.append(button)
            daysRow.addArrangedSubview(button)
        }
        stack.addArrangedSubview(daysRow)

        let idleRow = NSStackView()
        idleRow.orientation = .horizontal
        idleRow.spacing = 6
        idleAutoArmCheckbox = NSButton(checkboxWithTitle: "Arm after no use for",
                                       target: self, action: #selector(controlChanged))
        idleMinutesField = NSTextField(string: "10")
        idleMinutesField.alignment = .center
        idleMinutesField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        idleMinutesField.delegate = self
        idleRow.addArrangedSubview(idleAutoArmCheckbox)
        idleRow.addArrangedSubview(idleMinutesField)
        idleRow.addArrangedSubview(NSTextField(labelWithString: "min (inside the arm window)"))
        stack.addArrangedSubview(idleRow)

        let daytimeIdleRow = NSStackView()
        daytimeIdleRow.orientation = .horizontal
        daytimeIdleRow.spacing = 6
        daytimeIdleField = NSTextField(string: "30")
        daytimeIdleField.alignment = .center
        daytimeIdleField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        daytimeIdleField.delegate = self
        daytimeIdleRow.addArrangedSubview(indent())
        daytimeIdleRow.addArrangedSubview(daytimeIdleField)
        daytimeIdleRow.addArrangedSubview(NSTextField(labelWithString: "min (outside the arm window)"))
        stack.addArrangedSubview(daytimeIdleRow)

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

        wifiCheckbox = NSButton(checkboxWithTitle: "Left Wi-Fi range (works with the lid closed)",
                                target: self, action: #selector(controlChanged))
        stack.addArrangedSubview(wifiCheckbox)

        micCheckbox = NSButton(checkboxWithTitle: "Loud sound nearby — microphone",
                               target: self, action: #selector(micToggled))
        micGrantButton = NSButton(title: "Allow…", target: self, action: #selector(grantMic))
        stack.addArrangedSubview(permissionRow(micCheckbox, micGrantButton))

        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(sectionLabel("Motion — camera (catches movement with the lid open)"))
        cameraCheckbox = NSButton(checkboxWithTitle: "Detect movement with the camera",
                                  target: self, action: #selector(cameraToggled))
        cameraGrantButton = NSButton(title: "Allow…", target: self, action: #selector(grantCamera))
        stack.addArrangedSubview(permissionRow(cameraCheckbox, cameraGrantButton))
        cameraStatusLabel = NSTextField(labelWithString: "")
        cameraStatusLabel.font = NSFont.systemFont(ofSize: 11)
        cameraStatusLabel.textColor = .secondaryLabelColor
        let cameraStatusRow = NSStackView()
        cameraStatusRow.orientation = .horizontal
        cameraStatusRow.addArrangedSubview(indent())
        cameraStatusRow.addArrangedSubview(cameraStatusLabel)
        stack.addArrangedSubview(cameraStatusRow)

        let onChargerRow = NSStackView()
        onChargerRow.orientation = .horizontal
        onChargerCheckbox = NSButton(checkboxWithTitle: "Use camera while charging",
                                     target: self, action: #selector(controlChanged))
        onBatteryCheckbox = NSButton(checkboxWithTitle: "Use camera on battery",
                                     target: self, action: #selector(controlChanged))
        onChargerRow.addArrangedSubview(indent())
        onChargerRow.addArrangedSubview(onChargerCheckbox)
        onChargerRow.addArrangedSubview(onBatteryCheckbox)
        stack.addArrangedSubview(onChargerRow)

        let floorRow = NSStackView()
        floorRow.orientation = .horizontal
        floorRow.spacing = 6
        batteryFloorSlider = NSSlider(value: 20, minValue: 0, maxValue: 90,
                                      target: self, action: #selector(controlChanged))
        batteryFloorSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        batteryFloorLabel = NSTextField(labelWithString: "20%")
        floorRow.addArrangedSubview(indent())
        floorRow.addArrangedSubview(NSTextField(labelWithString: "Turn camera off below"))
        floorRow.addArrangedSubview(batteryFloorSlider)
        floorRow.addArrangedSubview(batteryFloorLabel)
        stack.addArrangedSubview(floorRow)

        lidClosedCheckbox = NSButton(checkboxWithTitle: "Keep watching when the lid is closed",
                                     target: self, action: #selector(controlChanged))
        stack.addArrangedSubview(lidClosedCheckbox)

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
        stack.addArrangedSubview(sectionLabel("Updates"))
        let updateRow = NSStackView()
        updateRow.orientation = .horizontal
        autoUpdateCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates",
                                      target: self, action: #selector(controlChanged))
        let checkNowButton = NSButton(title: "Check Now", target: self, action: #selector(checkForUpdatesNow))
        updateRow.addArrangedSubview(autoUpdateCheckbox)
        updateRow.addArrangedSubview(checkNowButton)
        stack.addArrangedSubview(updateRow)
        let versionLabel = NSTextField(labelWithString: "Installed: v\(banshellVersion)")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        stack.addArrangedSubview(spacer(8))
        let footer = NSTextField(labelWithString: "Changes save immediately. A 10-second power-button hold defeats any software alarm — keep FileVault and Find My on.")
        footer.font = NSFont.systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byWordWrapping
        footer.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(footer)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        panel.contentView = content
        panel.setContentSize(NSSize(width: 486, height: 680))
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

    private func permissionRow(_ checkbox: NSButton, _ grantButton: NSButton) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .fill
        checkbox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(checkbox)
        row.addArrangedSubview(grantButton)
        row.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return row
    }

    private func applyConfigToControls() {
        autoArmCheckbox.state = config.autoArmDaily ? .on : .off
        var components = DateComponents()
        components.hour = config.armHour
        components.minute = config.armMinute
        timePicker.dateValue = Calendar.current.date(from: components) ?? Date()
        autoDisarmCheckbox.state = config.autoDisarmOn ? .on : .off
        var disarmComponents = DateComponents()
        disarmComponents.hour = config.disarmH
        disarmComponents.minute = config.disarmM
        disarmTimePicker.dateValue = Calendar.current.date(from: disarmComponents) ?? Date()
        let scheduled = config.scheduledDays
        for button in dayButtons { button.state = scheduled.contains(button.tag) ? .on : .off }
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
        autoUpdateCheckbox.state = config.autoUpdateCheck != false ? .on : .off
        cameraCheckbox.state = config.cameraMotionOn ? .on : .off
        onChargerCheckbox.state = config.allowMotionOnCharger ? .on : .off
        onBatteryCheckbox.state = config.allowMotionOnBattery ? .on : .off
        batteryFloorSlider.doubleValue = Double(config.batteryFloor)
        batteryFloorLabel.stringValue = "\(config.batteryFloor)%"
        lidClosedCheckbox.state = config.watchLidClosed ? .on : .off
        idleAutoArmCheckbox.state = config.idleAutoArmOn ? .on : .off
        idleMinutesField.stringValue = "\(config.idleArmMinutes)"
        daytimeIdleField.stringValue = "\(config.daytimeIdleArmMinutes)"
        wifiCheckbox.state = config.wifiTriggerOn ? .on : .off
        micCheckbox.state = config.micTriggerOn ? .on : .off
        updateCameraStatus()
        updatePermissionButtons()
    }

    private func updatePermissionButtons() {
        cameraGrantButton.isHidden = watcher.camera.authorized
        micGrantButton.isHidden = watcher.mic.authorized
    }

    @objc private func grantCamera() {
        watcher.camera.requestAccess { [weak self] _ in self?.updatePermissionButtons() }
    }

    @objc private func grantMic() {
        watcher.mic.requestAccess { [weak self] _ in self?.updatePermissionButtons() }
    }

    @objc private func micToggled() {
        if micCheckbox.state == .on, !watcher.mic.authorized {
            watcher.mic.requestAccess { [weak self] granted in
                guard let self else { return }
                if !granted { self.micCheckbox.state = .off }
                self.updatePermissionButtons()
                self.controlChanged()
            }
            return
        }
        controlChanged()
    }

    private func updateCameraStatus() {
        let power = onACPower() ? "charging" : "on battery"
        let percentText = batteryPercent().map { " · \($0)%" } ?? ""
        if !config.cameraMotionOn {
            cameraStatusLabel.stringValue = "Off. \(power)\(percentText)."
        } else if !watcher.camera.authorized {
            cameraStatusLabel.stringValue = "⚠ Needs camera permission — toggle it on to grant."
        } else if config.motionSensingAllowedNow() {
            cameraStatusLabel.stringValue = "Active when armed & lid open. \(power)\(percentText)."
        } else {
            cameraStatusLabel.stringValue = "Paused by your power rules right now. \(power)\(percentText)."
        }
    }

    @objc private func cameraToggled() {
        if cameraCheckbox.state == .on, !watcher.camera.authorized {
            watcher.camera.requestAccess { [weak self] granted in
                guard let self else { return }
                if !granted { self.cameraCheckbox.state = .off }
                self.controlChanged()
            }
            return
        }
        controlChanged()
    }

    func controlTextDidChange(_ notification: Notification) {
        config.ownerName = ownerNameField.stringValue
        config.ownerEmail = ownerEmailField.stringValue
        config.ownerMessage = ownerMessageField.stringValue
        let minutes = max(1, min(120, Int(idleMinutesField.stringValue.filter { $0.isNumber }) ?? config.idleArmMinutes))
        config.idleMinutes = minutes
        let daytime = max(1, min(240, Int(daytimeIdleField.stringValue.filter { $0.isNumber }) ?? config.daytimeIdleArmMinutes))
        config.idleMinutesDaytime = daytime
        saveConfig(config)
        watcher.reloadConfig(config)
    }

    @objc private func controlChanged() {
        config.autoArmDaily = autoArmCheckbox.state == .on
        let components = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        config.armHour = components.hour ?? config.armHour
        config.armMinute = components.minute ?? config.armMinute
        config.autoDisarmDaily = autoDisarmCheckbox.state == .on
        let disarmComponents = Calendar.current.dateComponents([.hour, .minute], from: disarmTimePicker.dateValue)
        config.disarmHour = disarmComponents.hour ?? config.disarmH
        config.disarmMinute = disarmComponents.minute ?? config.disarmM
        let selectedDays = dayButtons.filter { $0.state == .on }.map { $0.tag }.sorted()
        config.scheduleDays = selectedDays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : selectedDays
        config.lidTrigger = lidCheckbox.state == .on
        config.powerTrigger = powerCheckbox.state == .on
        config.inputTrigger = touchCheckbox.state == .on
        config.lidDeltaDegrees = Double(Int(sensitivitySlider.doubleValue))
        sensitivityLabel.stringValue = "\(Int(config.lidDeltaDegrees))°"
        config.exitDelaySeconds = exitChoices[max(0, exitDelayPopup.indexOfSelectedItem)]
        config.entryDelaySeconds = entryChoices[max(0, entryDelayPopup.indexOfSelectedItem)]
        config.autoUpdateCheck = autoUpdateCheckbox.state == .on
        config.cameraMotion = cameraCheckbox.state == .on
        config.motionOnCharger = onChargerCheckbox.state == .on
        config.motionOnBattery = onBatteryCheckbox.state == .on
        config.motionBatteryFloor = Int(batteryFloorSlider.doubleValue)
        config.watchWhenLidClosed = lidClosedCheckbox.state == .on
        config.idleAutoArm = idleAutoArmCheckbox.state == .on
        config.wifiTrigger = wifiCheckbox.state == .on
        config.micTrigger = micCheckbox.state == .on
        batteryFloorLabel.stringValue = "\(Int(batteryFloorSlider.doubleValue))%"
        saveConfig(config)
        watcher.reloadConfig(config)
        updateCameraStatus()
        updatePermissionButtons()
    }

    @objc private func checkForUpdatesNow() {
        Updater.shared.checkForUpdates(silent: false)
    }

    @objc private func dayToggled(_ sender: NSButton) {
        controlChanged()
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
