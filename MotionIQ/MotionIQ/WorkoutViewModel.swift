import Combine
import Observation

/// Connects pose data to exercise logic and exposes state for the UI.
/// Owned by WorkoutView as @State — persists for the lifetime of the view.
@Observable
final class WorkoutViewModel {

    // MARK: - Published state (observed by WorkoutView)

    var currentPose: PoseData?
    var repCount: Int = 0
    var currentPhase: RepCounter.Phase = .standing

    // MARK: - Internal

    /// Exposed so WorkoutView can pass captureSession to CameraPreviewView.
    let cameraProvider: LiveCameraProvider

    private let repCounter = RepCounter(exercise: .squat)
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(provider: LiveCameraProvider = LiveCameraProvider()) {
        cameraProvider = provider
        subscribeToPoses()
    }

    // MARK: - Lifecycle

    func start() {
        cameraProvider.start()
    }

    func stop() {
        cameraProvider.stop()
    }

    // MARK: - Private

    private func subscribeToPoses() {
        cameraProvider.posePublisher
            .sink { [weak self] poseData in
                guard let self else { return }
                self.currentPose = poseData
                if let poseData {
                    self.processPose(poseData)
                }
            }
            .store(in: &cancellables)
    }

    private func processPose(_ pose: PoseData) {
        // Phase 1: squat only. Phase 2 adds the exercise classifier to select the right angle.
        if let kneeAngle = AngleCalculator.kneeAngle(from: pose) {
            repCounter.process(angle: kneeAngle)
            repCount = repCounter.repCount
            currentPhase = repCounter.currentPhase
        }
    }
}
