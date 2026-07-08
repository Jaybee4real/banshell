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
    private(set) var active = false
    var onDisarm: (() -> Void)?

    func begin(reason: String) {
        guard !active else { return }
        active = true
        logLine("ALARM TRIGGERED: \(reason)")
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let entryDelay = loadConfig()?.entryDelaySeconds ?? 15
        savedDevice = AudioControl.defaultOutputDevice()
        if let device = savedDevice { savedVolume = AudioControl.readVolume(device) }
        if let speakers = AudioControl.builtInSpeakers() {
            AudioControl.setDefaultOutput(speakers)
            AudioControl.setVolume(speakers, 0.7)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar, .disableProcessSwitching,
            .disableForceQuit, .disableSessionTermination, .disableHideApplication,
        ]
        buildWindows(reason: reason)
        synth.start()
        entryDeadline = Date().addingTimeInterval(Double(entryDelay))
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reassertFocus()
        }
        reassertFocus()
    }

    private func buildWindows(reason: String) {
        for screen in NSScreen.screens {
            let window = KioskWindow(contentRect: screen.frame, styleMask: .borderless,
                                     backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.backgroundColor = NSColor.black
            window.isOpaque = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)
            if screen == NSScreen.main {
                window.contentView = buildContent(size: screen.frame.size, reason: reason)
            }
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func buildContent(size: NSSize, reason: String) -> NSView {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let centerX = size.width / 2

        let title = NSTextField(labelWithString: "🚨  BANSHELL  🚨")
        title.font = NSFont.systemFont(ofSize: 64, weight: .black)
        title.textColor = NSColor.systemRed
        title.alignment = .center
        title.sizeToFit()
        title.frame.origin = NSPoint(x: centerX - title.frame.width / 2, y: size.height * 0.62)
        content.addSubview(title)

        let reasonField = NSTextField(labelWithString: reason.uppercased())
        reasonField.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        reasonField.textColor = NSColor.white
        reasonField.alignment = .center
        reasonField.sizeToFit()
        reasonField.frame.origin = NSPoint(x: centerX - reasonField.frame.width / 2, y: size.height * 0.55)
        content.addSubview(reasonField)
        reasonLabel = reasonField

        let countdown = NSTextField(labelWithString: "")
        countdown.font = NSFont.monospacedSystemFont(ofSize: 28, weight: .heavy)
        countdown.textColor = NSColor.systemYellow
        countdown.alignment = .center
        countdown.frame = NSRect(x: centerX - 300, y: size.height * 0.47, width: 600, height: 40)
        content.addSubview(countdown)
        countdownLabel = countdown

        let field = NSSecureTextField(frame: NSRect(x: centerX - 160, y: size.height * 0.38, width: 320, height: 44))
        field.font = NSFont.monospacedSystemFont(ofSize: 26, weight: .bold)
        field.alignment = .center
        field.placeholderString = "ENTER CODE"
        field.target = self
        field.action = #selector(pinSubmitted(_:))
        content.addSubview(field)
        pinField = field

        let hint = NSTextField(labelWithString: "Enter disarm code and press Return")
        hint.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        hint.textColor = NSColor.gray
        hint.alignment = .center
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: centerX - hint.frame.width / 2, y: size.height * 0.33)
        content.addSubview(hint)

        return content
    }

    private func tickCountdown() {
        guard let deadline = entryDeadline else {
            countdownLabel?.stringValue = "⚠️  SIREN ACTIVE  ⚠️"
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
        logLine("entry delay expired — full siren")
        synth.escalateToSiren()
        countdownLabel?.stringValue = "⚠️  SIREN ACTIVE  ⚠️"
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
        if let field = pinField, let window = windows.first(where: { $0.contentView?.subviews.contains(field) ?? false }) {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(field)
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
        logLine("correct code — alarm disarmed")
        enforcerTimer?.invalidate()
        countdownTimer?.invalidate()
        focusTimer?.invalidate()
        enforcerTimer = nil
        countdownTimer = nil
        focusTimer = nil
        entryDeadline = nil
        synth.stop()
        if let device = savedDevice {
            AudioControl.setDefaultOutput(device)
            if let volume = savedVolume { AudioControl.setVolume(device, volume) }
        }
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        pinField = nil
        NSApp.presentationOptions = []
        NSApp.setActivationPolicy(.accessory)
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)
        active = false
        onDisarm?()
    }
}
