import CoreGraphics
import Foundation
import IOKit.hid
import IOKit.ps

final class LidSensor {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = ["PrimaryUsagePage": 0x20, "PrimaryUsage": 0x8A]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let found = deviceSet.first else { return }
        if IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            device = found
        }
    }

    var available: Bool { device != nil }

    func readAngle() -> Double? {
        guard let device else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var reportLength = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &reportLength)
        guard result == kIOReturnSuccess, reportLength >= 3 else { return nil }
        let rawAngle = UInt16(report[1]) | (UInt16(report[2]) << 8)
        return Double(rawAngle)
    }
}

func onACPower() -> Bool {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return true }
    guard let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return true }
    return (sourceType as String) == "AC Power"
}

func batteryPercent() -> Int? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
        return nil
    }
    for source in sources {
        guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
            as? [String: Any],
            let current = description[kIOPSCurrentCapacityKey as String] as? Int,
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int, maximum > 0 else { continue }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }
    return nil
}

func inputMonitoringGranted() -> Bool {
    IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}

func requestInputMonitoring() {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}

final class InputTap {
    private var tap: CFMachPort?
    var onInput: (() -> Void)?

    var running: Bool { tap != nil }

    func start() -> Bool {
        func maskBit(_ type: CGEventType) -> CGEventMask {
            CGEventMask(1) << CGEventMask(type.rawValue)
        }
        let mask = maskBit(.keyDown) | maskBit(.leftMouseDown) | maskBit(.rightMouseDown)
            | maskBit(.otherMouseDown) | maskBit(.scrollWheel) | maskBit(.mouseMoved)
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo in
                if let userInfo {
                    let tapInstance = Unmanaged<InputTap>.fromOpaque(userInfo).takeUnretainedValue()
                    tapInstance.onInput?()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer)
        guard let tap else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}
