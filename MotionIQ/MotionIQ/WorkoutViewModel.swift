import Combine
import Observation
import SwiftUI

/// Thin bridge between the camera pose stream and WorkoutStateMachine.
/// Forwards poses to the machine and converts machine state for the UI.
@Observable
final class WorkoutViewModel {

    // MARK: - Published state

    var currentPose: PoseData?

    var workoutState: WorkoutState        { stateMachine.workoutState }
    var currentExercise: Exercise?        { stateMachine.currentExercise }
    var repCount: Int                     { stateMachine.repCount }
    var currentRepPhase: RepCounter.Phase { stateMachine.currentRepPhase }
    var activeFormFlags: [FormFlag]       { stateMachine.activeFormFlags }
    var restElapsed: TimeInterval         { stateMachine.restElapsed }
    var sessionElapsed: TimeInterval      { stateMachine.sessionElapsed }
    var setElapsed: TimeInterval          { stateMachine.setElapsed }
    var completedSets: [CompletedSet]     { stateMachine.completedSets }

    var isPaused: Bool { stateMachine.workoutState == .paused }

    /// Form score as a SwiftUI Color.
    var formScoreColor: Color {
        let score = stateMachine.currentFormScore
        if score >= Constants.formScoreGreen  { return .green }
        if score >= Constants.formScoreYellow { return .yellow }
        return .red
    }

    /// Highest-priority active form cue, or nil if form is good.
    var activeCueText: String? {
        stateMachine.activeFormFlags.first?.cueText
    }

    // MARK: - Internal

    let cameraProvider: LiveCameraProvider

    private let stateMachine = WorkoutStateMachine()
    private let logger = WorkoutLogger()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(provider: LiveCameraProvider = LiveCameraProvider()) {
        cameraProvider = provider
        logger.attach(to: stateMachine)
        subscribeToPoses()
    }

    // MARK: - Lifecycle

    func start() { cameraProvider.start() }
    func stop()  { cameraProvider.stop() }

    // MARK: - UI actions

    func startWorkout()  { stateMachine.startWorkout() }
    func startNextSet()  { stateMachine.startNextSet() }
    func endWorkout()    { stateMachine.endWorkout() }
    func togglePause()   { stateMachine.togglePause() }

    // MARK: - Private

    private func subscribeToPoses() {
        cameraProvider.posePublisher
            .sink { [weak self] poseData in
                guard let self else { return }
                self.currentPose = poseData
                if let poseData {
                    self.stateMachine.process(pose: poseData)
                }
            }
            .store(in: &cancellables)
    }
}
