import Foundation
import Observation

/// The workout's top-level state.
enum WorkoutState: Equatable {
    case idle         // before any joints are detected
    case detecting    // joints visible, waiting for exercise lock
    case inSet        // exercise active, counting reps
    case resting      // user stopped moving between sets
    case paused       // workout explicitly paused by user
    case sessionEnd   // workout over

    nonisolated static func == (lhs: WorkoutState, rhs: WorkoutState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.detecting, .detecting), (.inSet, .inSet),
             (.resting, .resting), (.paused, .paused), (.sessionEnd, .sessionEnd): true
        default: false
        }
    }
}

/// Payload captured when a set ends. WorkoutLogger persists this.
struct CompletedSet {
    let exercise: Exercise
    let repCount: Int
    let duration: TimeInterval
    let formScores: [Double]

    var averageFormScore: Double {
        guard !formScores.isEmpty else { return 0 }
        return formScores.reduce(0, +) / Double(formScores.count)
    }
}

/// Central workout engine. Owns all detectors and drives state transitions.
@Observable
final class WorkoutStateMachine {

    // MARK: - Published state

    private(set) var workoutState: WorkoutState = .idle
    private(set) var currentExercise: Exercise?
    private(set) var repCount: Int = 0
    private(set) var currentRepPhase: RepCounter.Phase = .standing
    private(set) var currentFormScore: Double = 1.0
    private(set) var activeFormFlags: [FormFlag] = []
    private(set) var restElapsed: TimeInterval = 0
    private(set) var sessionElapsed: TimeInterval = 0  // total session time, pauses when paused
    private(set) var setElapsed: TimeInterval = 0      // current set duration
    private(set) var completedSets: [CompletedSet] = []
    private(set) var sessionStartTime: Date?

    // MARK: - Callbacks
    // Arrays instead of single closures so WorkoutLogger and WorkoutViewModel
    // can both subscribe without overwriting each other.

    var onSetCompleted: [(CompletedSet) -> Void] = []
    var onSessionEnded: [() -> Void] = []

    // MARK: - Detectors

    private let classifier      = ExerciseClassifier()
    private let restDetector    = RestDetector()
    private let gestureDetector = GestureDetector()
    private var repCounter: RepCounter = RepCounter(exercise: .squat)

    // MARK: - Timers

    private var inactivityTimer: Timer?
    private var restStartTime: Date?
    private var restUpdateTimer: Timer?
    private var sessionTimer: Timer?      // ticks every 0.5s; updates sessionElapsed + setElapsed
    private var setStartTime: Date?
    private var pausedAt: Date?           // when we entered paused state
    private var accumulatedSessionTime: TimeInterval = 0  // accounts for pause periods
    private var stateBeforePause: WorkoutState = .idle

    // MARK: - Per-rep accumulation

    private var repFrameScores: [Double] = []
    private var setRepScores: [Double] = []

    // MARK: - Confidence counter

    private var detectedFrameCount = 0
    private let detectedFrameThreshold = 5

    // MARK: - Init

    init() {
        restDetector.onRest = { [weak self] in
            self?.handleRestDetected()
        }
        gestureDetector.onGesture = { [weak self] event in
            self?.handleGesture(event)
        }
    }

    // MARK: - Main entry point

    func process(pose: PoseData) {
        // Gesture detector always runs so pause/resume gestures work in any state
        gestureDetector.process(pose: pose)

        switch workoutState {
        case .idle:       processIdle(pose: pose)
        case .detecting:  processDetecting(pose: pose)
        case .inSet:      processInSet(pose: pose)
        case .resting, .paused, .sessionEnd:
            break
        }
    }

    // MARK: - Manual controls

    /// Called when the user taps Start or does the start gesture.
    /// This is the only way to leave .idle — nothing auto-advances.
    func startWorkout() {
        guard workoutState == .idle else { return }
        transition(to: .detecting)
    }

    func startNextSet() {
        guard workoutState == .resting else { return }
        transition(to: .inSet)
    }

    func endWorkout() {
        transition(to: .sessionEnd)
    }

    func togglePause() {
        if workoutState == .paused {
            transition(to: stateBeforePause)
        } else if workoutState == .inSet || workoutState == .resting {
            stateBeforePause = workoutState
            transition(to: .paused)
        }
    }

    // MARK: - State processors

    private func processIdle(pose: PoseData) {
        // Do nothing — user must explicitly tap Start or use start gesture.
        // Camera runs so the skeleton overlay is visible before starting.
    }

    private func processDetecting(pose: PoseData) {
        restDetector.process(pose: pose)
        if let exercise = classifier.process(pose: pose) {
            currentExercise = exercise
            repCounter = RepCounter(exercise: exercise)
            transition(to: .inSet)
        }
    }

    private func processInSet(pose: PoseData) {
        restDetector.process(pose: pose)

        guard let exercise = currentExercise else { return }

        let angle: Double?
        switch exercise {
        case .squat, .lunge: angle = AngleCalculator.kneeAngle(from: pose)
        case .pushup:        angle = AngleCalculator.elbowAngle(from: pose)
        }

        if let angle {
            let repCompleted = repCounter.process(angle: angle)
            currentRepPhase = repCounter.currentPhase
            repCount = repCounter.repCount

            if let result = FormScorer.score(pose: pose, exercise: exercise, phase: currentRepPhase) {
                currentFormScore = result.score
                activeFormFlags = result.flags
                repFrameScores.append(result.score)
            }

            if repCompleted {
                let repScore = repFrameScores.isEmpty ? 1.0 :
                    repFrameScores.reduce(0, +) / Double(repFrameScores.count)
                setRepScores.append(repScore)
                repFrameScores = []
            }
        }
    }

    // MARK: - Detector callbacks

    private func handleRestDetected() {
        guard workoutState == .inSet else { return }
        transition(to: .resting)
    }

    private func handleGesture(_ event: GestureEvent) {
        switch event {
        case .pause:
            togglePause()
            gestureDetector.reset()
        case .nextSet:
            switch workoutState {
            case .idle:     startWorkout()         // both arms up = start workout
            case .inSet:    transition(to: .resting)
            case .resting:  startNextSet()
            default:        break
            }
        case .endWorkout:
            endWorkout()
        }
    }

    // MARK: - State transitions

    private func transition(to newState: WorkoutState) {
        let previous = workoutState
        workoutState = newState

        switch newState {
        case .idle:
            break

        case .detecting:
            sessionStartTime = Date()
            accumulatedSessionTime = 0
            startSessionTimer()
            startInactivityTimer()

        case .inSet:
            stopInactivityTimer()
            stopRestTimer()

            if previous == .paused && stateBeforePause == .inSet {
                // Resuming inSet — don't reset set state, just resume timers
                if let pauseStart = pausedAt {
                    // Shift setStartTime forward by the paused duration so setElapsed is correct
                    let pauseDuration = Date().timeIntervalSince(pauseStart)
                    setStartTime = setStartTime.map { $0.addingTimeInterval(pauseDuration) }
                }
                pausedAt = nil
                resumeSessionTimer()
            } else if previous == .resting || previous == .paused {
                // New set
                classifier.reset()
                restDetector.reset()
                gestureDetector.reset()
                repCounter.reset()
                setStartTime = Date()
                repFrameScores = []
                setRepScores = []
                currentFormScore = 1.0
                activeFormFlags = []
                repCount = 0
                currentRepPhase = .standing
                pausedAt = nil
                if previous == .paused { resumeSessionTimer() }
            } else {
                // First set
                setStartTime = Date()
            }

        case .resting:
            startRestTimer()
            startInactivityTimer()
            gestureDetector.reset()

            let duration = setStartTime.map { Date().timeIntervalSince($0) } ?? 0
            if let exercise = currentExercise {
                let set = CompletedSet(exercise: exercise,
                                       repCount: repCounter.repCount,
                                       duration: duration,
                                       formScores: setRepScores)
                completedSets.append(set)
                onSetCompleted.forEach { $0(set) }
            }

        case .paused:
            pausedAt = Date()
            pauseSessionTimer()
            stopRestTimer()
            stopInactivityTimer()
            gestureDetector.reset()

        case .sessionEnd:
            stopInactivityTimer()
            stopRestTimer()
            stopSessionTimer()
            onSessionEnded.forEach { $0() }
        }
    }

    // MARK: - Session timer

    private func startSessionTimer() {
        stopSessionTimer()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sessionElapsed = self.accumulatedSessionTime +
                (self.sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0)
            // Also update set elapsed while in a set
            if self.workoutState == .inSet, let setStart = self.setStartTime {
                self.setElapsed = Date().timeIntervalSince(setStart)
            }
        }
    }

    private func pauseSessionTimer() {
        // Snapshot accumulated time before pausing
        accumulatedSessionTime = sessionElapsed
        sessionStartTime = nil
        stopSessionTimer()
    }

    private func resumeSessionTimer() {
        sessionStartTime = Date()
        startSessionTimer()
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // MARK: - Rest timer

    private func startRestTimer() {
        restStartTime = Date()
        restUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.restStartTime else { return }
            self.restElapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopRestTimer() {
        restUpdateTimer?.invalidate()
        restUpdateTimer = nil
        restStartTime = nil
        restElapsed = 0
    }

    // MARK: - Inactivity timer

    private func startInactivityTimer() {
        stopInactivityTimer()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: Constants.inactivityTimeout,
                                               repeats: false) { [weak self] _ in
            guard let self, self.workoutState == .resting else { return }
            self.transition(to: .sessionEnd)
        }
    }

    private func stopInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
    }
}
