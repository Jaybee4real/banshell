import AppKit
import Foundation
import IOKit.pwr_mgt

final class Watcher {
    private(set) var config: Config
    private var state: AlarmState
    let lidSensor = LidSensor()
    private let inputTap = InputTap()
    private let alarm = AlarmController()
    let camera = CameraMotion()
    private var cameraRunning = false
    private var lidBaseline: Double?
    private var powerBaselineAC: Bool?
    private var monitoringStartsAt: Date?
    private var sleepAssertion: IOPMAssertionID = 0
    private var lastStateData: Data?
    private var timer: DispatchSourceTimer?
    private var tickCounter = 0
    private let queue = DispatchQueue(label: "banshell.watch")
    var onChange: ((Bool, Bool) -> Void)?

    private(set) var uiArmed = false
    private(set) var uiTriggered = false

    init(config: Config) {
        self.config = config
        self.state = loadState()
        alarm.onDisarm = { [weak self] in
            self?.queue.async { self?.applyDisarm() }
        }
        camera.onMotion = { [weak self] in
            self?.queue.async { self?.handleCameraMotion() }
        }
    }

    func start() {
        logLine("BANSHELL v\(banshellVersion) watching — armed=\(state.armed) lidSensor=\(lidSensor.available)")
        if config.inputTrigger {
            inputTap.onInput = { [weak self] in
                self?.queue.async { self?.handleInputEvent() }
            }
            if !inputTap.start() {
                logLine("input tap unavailable — grant Input Monitoring to enable the touch trigger")
            }
        }
        if !lidSensor.available {
            logLine("lid angle sensor unavailable on this machine")
        }
        writeState()
        notifyChange()
        if state.triggered {
            let reason = state.reason ?? "resumed after restart"
            DispatchQueue.main.async { self.alarm.begin(reason: reason) }
        } else if state.armed {
            monitoringStartsAt = Date().addingTimeInterval(5)
            logLine("resumed armed — monitoring in 5s")
        }
        let dispatchTimer = DispatchSource.makeTimerSource(queue: queue)
        dispatchTimer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        dispatchTimer.setEventHandler { [weak self] in self?.tick() }
        dispatchTimer.resume()
        timer = dispatchTimer
    }

    func reloadConfig(_ newConfig: Config) {
        queue.async {
            let touchWasOff = !self.config.inputTrigger
            self.config = newConfig
            if touchWasOff, newConfig.inputTrigger, !self.inputTap.running {
                self.inputTap.onInput = { [weak self] in
                    self?.queue.async { self?.handleInputEvent() }
                }
                DispatchQueue.main.async { _ = self.inputTap.start() }
            }
        }
    }

    func armNow() {
        queue.async {
            guard !self.state.armed else { return }
            self.applyArm()
            logLine("armed from menu")
        }
    }

    func disarmNow() {
        queue.async {
            guard self.state.armed, !self.state.triggered else { return }
            self.applyDisarm()
            logLine("disarmed from menu")
        }
    }

    func drill() {
        queue.async {
            self.state.armed = true
            self.trigger(reason: "drill")
        }
    }

    private func notifyChange() {
        let armed = state.armed
        let triggered = state.triggered
        DispatchQueue.main.async {
            self.uiArmed = armed
            self.uiTriggered = triggered
            self.onChange?(armed, triggered)
        }
    }

    private func tick() {
        tickCounter += 1
        if tickCounter % 20 == 0 {
            checkExternalState()
            checkAutoArm()
        }
        guard state.armed, !state.triggered else { return }
        guard let startsAt = monitoringStartsAt else { return }
        guard Date() >= startsAt else { return }
        if tickCounter % 20 == 0 { evaluateCamera() }
        if lidBaseline == nil, config.lidTrigger, let angle = lidSensor.readAngle() {
            lidBaseline = angle
            logLine("lid baseline captured: \(angle)°")
        }
        if powerBaselineAC == nil, config.powerTrigger {
            powerBaselineAC = onACPower()
            logLine("power baseline: \(powerBaselineAC == true ? "AC" : "battery")")
        }
        if config.lidTrigger, let baseline = lidBaseline, let angle = lidSensor.readAngle(),
           abs(angle - baseline) >= config.lidDeltaDegrees {
            trigger(reason: "lid moved \(Int(abs(angle - baseline)))° — device motion")
            return
        }
        if config.powerTrigger, powerBaselineAC == true, !onACPower() {
            trigger(reason: "power cable disconnected")
        }
    }

    private func handleInputEvent() {
        guard state.armed, !state.triggered else { return }
        guard let startsAt = monitoringStartsAt, Date() >= startsAt else { return }
        trigger(reason: "keyboard or trackpad touched")
    }

    private func handleCameraMotion() {
        guard state.armed, !state.triggered, cameraRunning else { return }
        guard let startsAt = monitoringStartsAt, Date() >= startsAt else { return }
        trigger(reason: "device moved — camera")
    }

    private func lidIsOpen() -> Bool {
        guard let angle = lidSensor.readAngle() else { return true }
        return angle > 5
    }

    private func evaluateCamera() {
        let shouldRun = config.motionSensingAllowedNow() && lidIsOpen()
        if shouldRun, !cameraRunning {
            camera.start()
            cameraRunning = true
        } else if !shouldRun, cameraRunning {
            camera.stop()
            cameraRunning = false
        }
    }

    private func stopCamera() {
        if cameraRunning {
            camera.stop()
            cameraRunning = false
        }
    }

    private func checkAutoArm() {
        guard config.autoArmDaily, !state.armed, !state.triggered else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        if components.hour == config.armHour, components.minute == config.armMinute,
           state.lastAutoArmDay != today {
            state.lastAutoArmDay = today
            applyArm()
            logLine("auto-armed on schedule (\(config.armHour):\(String(format: "%02d", config.armMinute)))")
        }
    }

    private func checkExternalState() {
        guard let data = try? Data(contentsOf: Paths.stateFile), data != lastStateData,
              let external = try? JSONDecoder().decode(AlarmState.self, from: data) else { return }
        lastStateData = data
        if state.triggered {
            if !external.triggered { writeState() }
            return
        }
        if external.triggered, !state.triggered {
            state.armed = true
            state.reason = external.reason ?? "manual drill"
            trigger(reason: state.reason ?? "manual drill")
            return
        }
        if external.armed, !state.armed {
            state.lastAutoArmDay = external.lastAutoArmDay
            applyArm()
            logLine("armed by command")
        } else if !external.armed, state.armed {
            applyDisarm()
            logLine("disarmed by command")
        }
    }

    private func applyArm() {
        state.armed = true
        state.triggered = false
        state.reason = nil
        lidBaseline = nil
        powerBaselineAC = nil
        monitoringStartsAt = Date().addingTimeInterval(Double(config.exitDelaySeconds))
        writeState()
        if config.watchLidClosed {
            if runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "1"]) == 0 {
                logLine("sleep disabled — closed-lid protection active")
            } else {
                logLine("WARNING: could not disable sleep (sudoers not set up) — closed-lid protection off")
            }
            if sleepAssertion == 0 {
                IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "BANSHELL armed" as CFString, &sleepAssertion)
            }
        } else {
            logLine("watch-when-lid-closed off — machine may sleep when the lid shuts")
        }
        logLine("ARMED — monitoring starts in \(config.exitDelaySeconds)s")
        notifyChange()
    }

    private func applyDisarm() {
        state.armed = false
        state.triggered = false
        state.reason = nil
        lidBaseline = nil
        powerBaselineAC = nil
        monitoringStartsAt = nil
        stopCamera()
        writeState()
        runProcess("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"])
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        logLine("DISARMED")
        notifyChange()
    }

    private func trigger(reason: String) {
        state.triggered = true
        state.reason = reason
        stopCamera()
        writeState()
        notifyChange()
        DispatchQueue.main.async { self.alarm.begin(reason: reason) }
    }

    private func writeState() {
        saveState(state)
        lastStateData = try? Data(contentsOf: Paths.stateFile)
    }
}
