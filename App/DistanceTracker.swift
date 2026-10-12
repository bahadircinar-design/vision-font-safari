//  DistanceTracker.swift — Vision Font
//  Low-res camera capture (~10 fps, only while tracking is on) + Vision face landmarks -> pupil distance in pixels.
//  Privacy: frames live only in memory for the duration of one Vision request. Nothing is saved, shown or sent.

import AVFoundation
import Foundation
import Vision

final class DistanceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Sample {
        let ipdPx: Double?         // nil = no face this frame
        let imageWidth: Double
        let time: TimeInterval     // ProcessInfo.systemUptime
    }

    enum TrackerError: LocalizedError {
        case noCamera, cannotAddInput, cannotAddOutput, denied
        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera found."
            case .cannotAddInput, .cannotAddOutput: return "The camera couldn't be started (it may be in use by another app)."
            case .denied: return "Camera access is off. Turn it on in System Settings ▸ Privacy & Security ▸ Camera ▸ Vision Font."
            }
        }
    }

    /// Delivered on the main queue.
    var onSample: ((Sample) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.bahacinar.VisionFont.camera", qos: .userInitiated)
    private var configured = false
    private var lastProcessed: TimeInterval = 0
    private let minInterval: TimeInterval = 0.1   // ~10 fps
    private(set) var isRunning = false

    static var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch authorization {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    func start() throws {
        guard DistanceTracker.authorization == .authorized else { throw TrackerError.denied }
        if !configured { try configure() }
        isRunning = true
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        isRunning = false
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    private func configure() throws {
        let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                      mediaType: .video, position: .unspecified).devices.first
            ?? AVCaptureDevice.default(for: .video)
        guard let camera = device else { throw TrackerError.noCamera }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for preset in [AVCaptureSession.Preset.vga640x480, .medium, .low] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset; break
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw TrackerError.cannotAddInput }
        session.addInput(input)

        // Ask the camera for ~10 fps when it supports it (saves power); we also drop frames below.
        if (try? camera.lockForConfiguration()) != nil {
            let target = CMTime(value: 1, timescale: 10)
            if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameDuration <= target && target <= $0.maxFrameDuration }) {
                camera.activeVideoMinFrameDuration = target
                camera.activeVideoMaxFrameDuration = target
            }
            camera.unlockForConfiguration()
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw TrackerError.cannotAddOutput }
        session.addOutput(output)
        configured = true
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate (camera queue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessed >= minInterval, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = now
        let width = Double(CVPixelBufferGetWidth(pixelBuffer))
        let height = Double(CVPixelBufferGetHeight(pixelBuffer))
        let ipd = Self.interpupillaryPixels(pixelBuffer, size: CGSize(width: width, height: height))
        let sample = Sample(ipdPx: ipd, imageWidth: width, time: now)
        DispatchQueue.main.async { [weak self] in self?.onSample?(sample) }
    }

    /// Pixel distance between the pupils of the largest face, corrected for head turn, or nil.
    static func interpupillaryPixels(_ buffer: CVPixelBuffer, size: CGSize) -> Double? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let face = request.results?
                .filter({ $0.confidence > 0.5 })
                .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let lm = face.landmarks else { return nil }

        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let pts = region?.pointsInImage(imageSize: size), !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + $1.x }, sy = pts.reduce(0) { $0 + $1.y }
            return CGPoint(x: sx / CGFloat(pts.count), y: sy / CGFloat(pts.count))
        }
        // Pupils first; fall back to the centre of each eye outline.
        guard let left = center(lm.leftPupil) ?? center(lm.leftEye),
              let right = center(lm.rightPupil) ?? center(lm.rightEye) else { return nil }
        var ipd = Double(hypot(left.x - right.x, left.y - right.y))
        guard ipd > 4 else { return nil }
        // A turned head shortens the apparent IPD by cos(yaw). Only correct moderate, reported yaw.
        if let yaw = face.yaw?.doubleValue {
            let c = cos(yaw)
            if c >= 0.75 && c < 0.999 { ipd /= c }
        }
        return ipd
    }
}
