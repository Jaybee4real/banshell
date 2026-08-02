import AVFoundation
import CoreAudio
import Foundation

enum AudioControl {
    static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    static func allOutputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { deviceID in
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var streamsSize = UInt32(0)
            AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize)
            return streamsSize > 0
        }
    }

    static func builtInSpeakers() -> AudioDeviceID? {
        for deviceID in allOutputDevices() {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var transport = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr,
               transport == kAudioDeviceTransportTypeBuiltIn {
                return deviceID
            }
        }
        return nil
    }

    static func setDefaultOutput(_ deviceID: AudioDeviceID) {
        var mutableID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
    }

    static func readVolume(_ deviceID: AudioDeviceID) -> Float32? {
        for element in [UInt32(0), 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            if AudioObjectHasProperty(deviceID, &address) {
                var volume = Float32(0)
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
                    return volume
                }
            }
        }
        return nil
    }

    static func setVolume(_ deviceID: AudioDeviceID, _ level: Float32) {
        var volume = level
        for element in [UInt32(0), 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            if AudioObjectHasProperty(deviceID, &address) {
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
            }
        }
        var unmute = UInt32(0)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0)
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmute)
        }
    }
}

final class SirenSynth {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let stateLock = NSLock()
    private var sirenOn = false
    private var framesRendered: Double = 0
    private var phase: Double = 0
    private var running = false
    private let fadeInSeconds: Double = 10

    func start() {
        guard !running else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let renderRate = sampleRate > 0 ? sampleRate : 48000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: renderRate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.stateLock.lock()
            let sirenMode = self.sirenOn
            self.stateLock.unlock()
            for frame in 0..<Int(frameCount) {
                let timeSeconds = self.framesRendered / renderRate
                var sample: Float = 0
                if sirenMode {
                    let sweep = (timeSeconds / 0.45).truncatingRemainder(dividingBy: 1.0)
                    let frequency = 2000.0 + 1200.0 * sweep
                    self.phase += 2.0 * Double.pi * frequency / renderRate
                    sample = Float(tanh(12.0 * sin(self.phase)))
                } else {
                    let cyclePosition = timeSeconds.truncatingRemainder(dividingBy: 0.5)
                    if cyclePosition < 0.12 {
                        self.phase += 2.0 * Double.pi * 950.0 / renderRate
                        sample = Float(sin(self.phase)) * 0.6
                    }
                }
                if self.phase > 2.0 * Double.pi { self.phase -= 2.0 * Double.pi }
                let fadeGain = Float(min(1.0, timeSeconds / self.fadeInSeconds))
                self.framesRendered += 1
                for buffer in buffers {
                    guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    pointer[frame] = sample * fadeGain
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        sourceNode = node
        do {
            try engine.start()
            running = true
        } catch {
            logLine("audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func escalateToSiren() {
        stateLock.lock()
        sirenOn = true
        stateLock.unlock()
    }

    func stop() {
        guard running else { return }
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        stateLock.lock()
        sirenOn = false
        framesRendered = 0
        phase = 0
        stateLock.unlock()
        running = false
    }
}
