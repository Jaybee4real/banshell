import AppKit
import CoreAudio
import Foundation

final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AlarmController: NSObject {
    private let synth = SirenSynth()
    private var windows: [KioskWindow] = []
    private var pinField: NSSecureTextField?
    private var countdownLabel: NSTextField?
    private var reasonLabel: NSTextField?
    private var enforcerTimer: Timer?
    private var countdownTimer: Timer?
    private var focusTimer: Timer?
    private var entryDeadline: Date?
    private var savedVolume: Float32?
    private var savedDevice: AudioDeviceID?
    private var escMonitor: Any?
    private var sirenFlash = false
    private var isPreview = false
    private var displaysCaptured = false
    private(set) var active = false
    var onDisarm: (() -> Void)?

    func begin(reason: String, preview: Bool = false) {
        guard !active else { return }
        active = true
        isPreview = preview
        let config = loadConfig()
        if !preview {
            logLine("ALARM TRIGGERED: \(reason)")
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            savedDevice = AudioControl.defaultOutputDevice()
            if let device = savedDevice { savedVolume = AudioControl.readVolume(device) }
            if let speakers = AudioControl.builtInSpeakers() {
                AudioControl.setDefaultOutput(speakers)
                AudioControl.setVolume(speakers, 0.7)
            }
            NSApp.presentationOptions = [
                .hideDock, .hideMenuBar, .disableProcessSwitching,
                .disableForceQuit, .disableSessionTermination, .disableHideApplication,
            ]
        } else {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.end()
                    return nil
                }
                return event
            }
        }
        NSApp.setActivationPolicy(.regular)
        buildWindows(reason: reason, config: config)
        if !preview { synth.start() }
        if CGCaptureAllDisplays() == .success {
            displaysCaptured = true
            let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            for window in windows {
                window.level = shieldLevel
                window.orderFrontRegardless()
            }
            logLine(preview ? "displays captured (preview)" : "displays captured — space switching disabled")
        } else {
            logLine("WARNING: could not capture displays — full-screen apps may escape the lock via space switching")
        }
        entryDeadline = Date().addingTimeInterval(Double(config?.entryDelaySeconds ?? 15))
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reassertFocus()
        }
        reassertFocus()
    }

    private func buildWindows(reason: String, config: Config?) {
        for screen in NSScreen.screens {
            let window = KioskWindow(contentRect: screen.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.backgroundColor = NSColor.black
            window.isOpaque = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)
            let isMain = screen == NSScreen.main
            window.contentView = buildContent(size: screen.frame.size, reason: reason,
                                              config: config, showCard: isMain)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func buildContent(size: NSSize, reason: String, config: Config?, showCard: Bool) -> NSView {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor

        let glow = NSView(frame: content.bounds)
        glow.wantsLayer = true
        glow.layer?.borderColor = NSColor.systemRed.cgColor
        glow.layer?.borderWidth = 16
        glow.autoresizingMask = [.width, .height]
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.2
        pulse.toValue = 1.0
        pulse.duration = 0.55
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        glow.layer?.add(pulse, forKey: "pulse")
        content.addSubview(glow)

        guard showCard else { return content }

        let card = NSView()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.03, blue: 0.04, alpha: 0.94).cgColor
        card.layer?.cornerRadius = 28
        card.layer?.borderWidth = 1.5
        card.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.55).cgColor
        content.addSubview(card)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 44, bottom: 36, right: 44)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let siren = NSTextField(labelWithString: "🚨")
        siren.font = NSFont.systemFont(ofSize: 58)
        stack.addArrangedSubview(siren)

        let title = NSTextField(labelWithString: "")
        title.attributedStringValue = NSAttributedString(string: "BANSHELL", attributes: [
            .font: NSFont.systemFont(ofSize: 42, weight: .black),
            .foregroundColor: NSColor.systemRed,
            .kern: 9,
        ])
        let titleShadow = NSShadow()
        titleShadow.shadowColor = NSColor.systemRed.withAlphaComponent(0.8)
        titleShadow.shadowBlurRadius = 14
        title.shadow = titleShadow
        stack.addArrangedSubview(title)

        let reasonField = NSTextField(labelWithString: reason.uppercased())
        reasonField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        reasonField.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        reasonField.alignment = .center
        stack.addArrangedSubview(reasonField)
        reasonLabel = reasonField

        let countdown = NSTextField(labelWithString: "")
        countdown.font = NSFont.monospacedSystemFont(ofSize: 26, weight: .heavy)
        countdown.textColor = NSColor.systemYellow
        countdown.alignment = .center
        stack.addArrangedSubview(countdown)
        countdownLabel = countdown

        stack.setCustomSpacing(18, after: countdown)

        let field = NSSecureTextField()
        field.font = NSFont.monospacedSystemFont(ofSize: 24, weight: .bold)
        field.alignment = .center
        field.placeholderString = "ENTER CODE"
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(pinSubmitted(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        field.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(field)
        pinField = field

        let hint = NSTextField(labelWithString: isPreview
            ? "Preview — press Esc to close, or enter your code"
            : "Enter the disarm code, then press Return")
        hint.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        stack.addArrangedSubview(hint)

        let ownerName = config?.ownerName ?? ""
        let ownerEmail = config?.ownerEmail ?? ""
        let ownerMessage = config?.ownerMessage ?? ""
        if !ownerName.isEmpty || !ownerEmail.isEmpty || !ownerMessage.isEmpty {
            stack.setCustomSpacing(22, after: hint)
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.widthAnchor.constraint(equalToConstant: 360).isActive = true
            stack.addArrangedSubview(divider)
            stack.setCustomSpacing(22, after: divider)

            let belongsTo = NSTextField(labelWithString: "")
            belongsTo.attributedStringValue = NSAttributedString(
                string: "THIS MACHINE BELONGS TO",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1),
                    .kern: 3,
                ])
            stack.addArrangedSubview(belongsTo)

            if !ownerName.isEmpty {
                let nameField = NSTextField(labelWithString: ownerName)
                nameField.font = NSFont.systemFont(ofSize: 26, weight: .bold)
                nameField.textColor = NSColor.white
                stack.addArrangedSubview(nameField)
            }
            if !ownerEmail.isEmpty {
                let emailField = NSTextField(labelWithString: ownerEmail)
                emailField.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
                emailField.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
                stack.addArrangedSubview(emailField)
            }
            if !ownerMessage.isEmpty {
                stack.setCustomSpacing(14, after: stack.arrangedSubviews.last ?? belongsTo)
                let messageField = NSTextField(wrappingLabelWithString: "“\(ownerMessage)”")
                let baseFont = NSFont.systemFont(ofSize: 15)
                messageField.font = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                messageField.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
                messageField.alignment = .center
                messageField.translatesAutoresizingMaskIntoConstraints = false
                messageField.widthAnchor.constraint(lessThanOrEqualToConstant: 480).isActive = true
                stack.addArrangedSubview(messageField)
            }
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            card.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])
        return content
    }

    private func tickCountdown() {
        guard let deadline = entryDeadline else {
            sirenFlash.toggle()
            countdownLabel?.stringValue = "▲ SIREN ACTIVE ▲"
            countdownLabel?.textColor = sirenFlash ? NSColor.systemRed : NSColor.white
            return
        }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            entryDeadline = nil
            escalate()
        } else {
            countdownLabel?.stringValue = String(format: "SIREN IN %.0f", ceil(remaining))
        }
    }

    private func escalate() {
        guard !isPreview else { return }
        logLine("entry delay expired — full siren")
        synth.escalateToSiren()
        enforcerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            if let speakers = AudioControl.builtInSpeakers() {
                if AudioControl.defaultOutputDevice() != speakers {
                    AudioControl.setDefaultOutput(speakers)
                }
                AudioControl.setVolume(speakers, 1.0)
            } else if let device = AudioControl.defaultOutputDevice() {
                AudioControl.setVolume(device, 1.0)
            }
        }
    }

    private func reassertFocus() {
        guard active else { return }
        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        guard let field = pinField, let window = windows.first(where: { window in
            var view: NSView? = field
            while let current = view {
                if current == window.contentView { return true }
                view = current.superview
            }
            return false
        }) else { return }
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
        let editorDelegate = (window.firstResponder as? NSTextView)?.delegate as AnyObject?
        let fieldHasFocus = window.firstResponder === field || editorDelegate === field
        if !fieldHasFocus {
            window.makeFirstResponder(field)
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
            }
        }
    }

    @objc private func pinSubmitted(_ sender: NSSecureTextField) {
        guard let config = loadConfig() else { return }
        let attempt = sender.stringValue
        sender.stringValue = ""
        if verifyPin(attempt, config: config) {
            end()
        } else {
            logLine("wrong disarm code attempt")
            reasonLabel?.stringValue = "WRONG CODE"
            reasonLabel?.textColor = NSColor.systemRed
        }
    }

    func end() {
        guard active else { return }
        if !isPreview { logLine("correct code — alarm disarmed") }
        enforcerTimer?.invalidate()
        countdownTimer?.invalidate()
        focusTimer?.invalidate()
        enforcerTimer = nil
        countdownTimer = nil
        focusTimer = nil
        entryDeadline = nil
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        if !isPreview {
            synth.stop()
            if let device = savedDevice {
                AudioControl.setDefaultOutput(device)
                if let volume = savedVolume { AudioControl.setVolume(device, volume) }
            }
        }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        pinField = nil
        if displaysCaptured {
            CGReleaseAllDisplays()
            displaysCaptured = false
        }
        NSApp.presentationOptions = []
        NSApp.setActivationPolicy(.accessory)
        if !isPreview {
            signal(SIGINT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
        }
        active = false
        onDisarm?()
    }
}
