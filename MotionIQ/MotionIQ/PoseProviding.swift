import Combine

/// Abstracts the source of pose data so WorkoutViewModel never depends on AVCaptureSession.
/// The real camera and test mocks both conform to this protocol.
protocol PoseProviding: AnyObject {
    /// Emits a new PoseData (or nil if no person detected) for each processed frame.
    /// Guaranteed to deliver on the main queue.
    var posePublisher: AnyPublisher<PoseData?, Never> { get }

    func start()
    func stop()
}
