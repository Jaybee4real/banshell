import AVFoundation
import CoreVideo
import Foundation

final class CameraMotion: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(label: "banshell.camera")
    private var previousGrid: [UInt8]?
    private var motionFrames = 0
    private let gridCols = 32
    private let gridRows = 24
    private let threshold = 14.0
    private var running = false
    var onMotion: (() -> Void)?

    var authorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func start() {
        guard !running else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            logLine("camera motion: not authorized — grant Camera access in System Settings")
            return
        }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            logLine("camera motion: no camera available")
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .low
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        previousGrid = nil
        motionFrames = 0
        session.startRunning()
        running = true
        logLine("camera motion: watching")
    }

    func stop() {
        guard running else { return }
        session.stopRunning()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        previousGrid = nil
        running = false
        logLine("camera motion: stopped")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let luma = base.assumingMemoryBound(to: UInt8.self)

        var grid = [UInt8]()
        grid.reserveCapacity(gridCols * gridRows)
        for row in 0..<gridRows {
            let sampleY = row * height / gridRows
            for col in 0..<gridCols {
                let sampleX = col * width / gridCols
                grid.append(luma[sampleY * bytesPerRow + sampleX])
            }
        }

        if let previous = previousGrid, previous.count == grid.count {
            var total = 0
            for index in 0..<grid.count {
                total += abs(Int(grid[index]) - Int(previous[index]))
            }
            let meanDifference = Double(total) / Double(grid.count)
            if meanDifference > threshold {
                motionFrames += 1
            } else {
                motionFrames = 0
            }
            if motionFrames >= 2 {
                motionFrames = 0
                DispatchQueue.main.async { self.onMotion?() }
            }
        }
        previousGrid = grid
    }
}
