// =============================================================================
// LiveCameraProvider.swift — The Camera Engine
// =============================================================================
//
// WHAT THIS FILE DOES:
// This is the part of the app that talks to the physical camera. It turns on
// the camera, receives a stream of video frames (~30 per second), runs Apple's
// body-detection AI on each frame, and then broadcasts the result to the rest
// of the app so the UI can update.
//
// THREADING — the most important concept in this file:
// Running body detection on every frame is heavy work. If we did it on the
// main thread (the one responsible for drawing the UI), the app would freeze.
// --> So we use a separate background thread called `processingQueue` for all the
// heavy lifting. 
// --> The camera sends frames directly to that thread, we do the
// work there, and only at the very end do we hand the result back to the main
// thread so the UI can use it safely.
//
// HOW THE DATA FLOWS:
//   Camera hardware
//     → sends a raw video frame to captureOutput() on processingQueue
//     → we ask Apple's Vision AI to find a person in that frame
//     → Vision returns joint positions (where are the knees, elbows, etc.)
//     → we convert that to our own PoseData format
//     → we publish PoseData via `subject` (think of it as a radio broadcaster)
//     → posePublisher delivers that data to any subscribers on the main thread
// 
// This essentailly converts the data collected from the back camera into our PoseData format and allows it to be used within any component that wants to utilize that data. 
//
// =============================================================================

import AVFoundation
import Combine
import Vision

// LiveCameraProvider is the "real" camera implementation.
// NSObject is required because AVFoundation is an older Apple framework that needs it. PoseProviding is our own protocol (see PoseProviding.swift) — conforming to it means tests can swap this out for a fake camera.
final class LiveCameraProvider: NSObject, PoseProviding {

    // captureSession: Apple's object that manages the camera hardware.
    // Think of it as the "camera session manager" — you tell it to start/stop, and it handles everything between the lens and your code.
    // nonisolated(unsafe): this property is accessed from processingQueue (background), not the main thread. We mark it this way to tell Swift we're handling thread safety ourselves (AVFoundation guarantees it for us).
    nonisolated(unsafe) let captureSession = AVCaptureSession()

    // subject: the internal broadcaster. When we have new pose data, we "send" it into this subject and anything subscribed to posePublisher receives it.
    // Like a walkie-talkie transmitter — subject is the mic, posePublisher is the signal anyone can tune into.
    nonisolated(unsafe) private let subject = PassthroughSubject<PoseData?, Never>()

    // processingQueue: our dedicated background thread for Vision work.
    // "userInteractive" priority means the OS treats it as high-priority, keeping our frame processing fast enough to feel real-time.
    // alwaysDiscardsLateVideoFrames (set below) means if we're still processing frame N when frame N+1 arrives, we just skip N+1 rather than falling behind.
    private let processingQueue = DispatchQueue(
        label: "com.danvo.MotionIQ.vision",
        qos: .userInteractive
    )

    // posePublisher: the public-facing stream of pose data.
    // Any part of the app can subscribe to this and receive a new PoseData every time a frame is processed. `.receive(on: DispatchQueue.main)` ensures
    // subscribers always get the data on the main thread, so they can safely update the UI without any extra work on their end.
    var posePublisher: AnyPublisher<PoseData?, Never> {
        subject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // init: when LiveCameraProvider is created, immediately configure the camera.
    // We don't start streaming yet — that happens when start() is called.
    override init() {
        super.init()
        setupSession()
    }

    // start(): begin streaming camera frames.
    // Called on the background queue because starting a capture session is a blocking operation — doing it on the main thread would freeze the UI briefly.
    func start() {
        processingQueue.async { [captureSession] in
            captureSession.startRunning()
        }
    }

    // stop(): shut down the camera stream.
    // Same reason as start() — runs on the background queue to avoid blocking the UI.
    func stop() {
        processingQueue.async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    // MARK: - Private

    // setupSession(): wires up the camera hardware to this class.
    private func setupSession() {
        captureSession.beginConfiguration()  // start a batch of config changes
        captureSession.sessionPreset = .high // request high-quality video

        guard
            // 1. Find the back camera and create an "input" from it
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // 2. Create a "video output" that will call our captureOutput() function each time a new frame is ready
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true  // don't queue up frames if we fall behind
        output.setSampleBufferDelegate(self, queue: processingQueue)  // call us on the background queue

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            return
        }

        // 3. Connect input → session → output and lock in the configuration    
        captureSession.addOutput(output)
        captureSession.commitConfiguration()  // apply all config changes at once
    }
}

// MARK: - Frame-by-frame processing

extension LiveCameraProvider: AVCaptureVideoDataOutputSampleBufferDelegate {

    // captureOutput(): Apple calls this function every time a new camera frame arrives.
    // This is the heart of the whole pipeline — it runs ~30 times per second on processingQueue.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        //  1. Extract the raw image from the frame (pixelBuffer)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            subject.send(nil)
            return
        }

        //  2. Ask Vision to find a human body in the image (VNDetectHumanBodyPoseRequest)
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            // `orientation: .right` fixes a rotation quirk: iPhone camera sensors are physically
            // landscape, so every frame arrives rotated 90° clockwise. Telling Vision the
            // orientation is `.right` corrects for this so joint coordinates come out upright.
        try? handler.perform([request])
        
        // 3. Convert the first result (if any) to our PoseData format
        let poseData = request.results?.first.map { PoseData(from: $0) }
        // 4. Broadcast the result via subject — nil if no person was detected
        subject.send(poseData)
    }
}
