import AVFoundation
import Combine
import Vision

/// Sets up the camera pipeline and runs Vision pose detection on a background queue.
/// Publishes PoseData to subscribers on the main queue.
final class LiveCameraProvider: NSObject, PoseProviding {

    // nonisolated(unsafe): these are accessed from processingQueue, not MainActor.
    // Thread safety is guaranteed by AVFoundation's design — it serializes all
    // camera callbacks onto processingQueue.
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    nonisolated(unsafe) private let subject = PassthroughSubject<PoseData?, Never>()

    /// Dedicated background queue for all Vision processing.
    /// alwaysDiscardsLateVideoFrames ensures we never pile up unprocessed frames.
    private let processingQueue = DispatchQueue(
        label: "com.danvo.MotionIQ.vision",
        qos: .userInteractive
    )

    var posePublisher: AnyPublisher<PoseData?, Never> {
        // Hop to main queue so all subscribers receive on MainActor without extra boilerplate.
        subject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    override init() {
        super.init()
        setupSession()
    }

    func start() {
        processingQueue.async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func stop() {
        processingQueue.async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    // MARK: - Private

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(output)
        captureSession.commitConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LiveCameraProvider: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called on processingQueue (~30fps). Runs Vision and publishes PoseData.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            subject.send(nil)
            return
        }

        let request = VNDetectHumanBodyPoseRequest()
        // .right corrects for iPhone portrait orientation:
        // the camera sensor is naturally landscape, so frames arrive rotated 90° CW.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try? handler.perform([request])

        let poseData = request.results?.first.map { PoseData(from: $0) }
        subject.send(poseData)
    }
}
