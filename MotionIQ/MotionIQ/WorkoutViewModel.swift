import Combine
import CoreData
import Observation
import SwiftUI

/// Thin bridge between the camera pose stream and WorkoutStateMachine.
/// Forwards poses to the machine and converts machine state for the UI.
/// Also owns the two Claude API calls per session and PR detection.
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

    // MARK: - Claude state

    /// 1–2 sentence micro-feedback from Claude shown in the rest HUD.
    /// Set during each rest period; cleared when the next set starts.
    var currentClaudeFeedback: String?

    /// 3–5 sentence coaching paragraph for the session summary screen.
    /// Nil while the async call is in flight; set when it resolves.
    var claudeSessionFeedback: String?

    /// True while the end-of-session Claude call is in flight.
    var isLoadingSessionFeedback = false

    /// Personal records achieved in this session, e.g. ["Squat rep PR: 12"].
    /// Populated at session end before the summary screen appears.
    var personalRecords: [String] = []

    // MARK: - Internal

    let cameraProvider: LiveCameraProvider

    private let stateMachine = WorkoutStateMachine()
    private let logger       = WorkoutLogger()
    private let claudeClient = ClaudeAPIClient()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(provider: LiveCameraProvider = LiveCameraProvider()) {
        cameraProvider = provider

        // Logger subscribes first so CoreData is written before the ViewModel
        // reads back historical data for PR detection.
        logger.attach(to: stateMachine)

        // ViewModel subscribes second — order within a single state transition
        // is logger → viewmodel.
        stateMachine.onSetCompleted.append { [weak self] set in
            self?.handlePostSetClaude(set)
        }
        stateMachine.onSessionEnded.append { [weak self] in
            self?.handleSessionEnd()
        }

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

    // MARK: - Claude: post-set call (Call 1 of 2)

    /// Fires when the state machine transitions to .resting.
    /// Builds a short prompt from the completed set's stats and calls Claude.
    /// Degrades gracefully to a hardcoded fallback cue if the call fails.
    private func handlePostSetClaude(_ set: CompletedSet) {
        currentClaudeFeedback = nil     // clear previous rest's feedback
        let prompt = buildPostSetPrompt(set)
        let exercise = set.exercise
        Task { [weak self] in
            guard let self else { return }
            do {
                let feedback = try await claudeClient.send(prompt: prompt)
                await MainActor.run { self.currentClaudeFeedback = feedback }
            } catch {
                await MainActor.run {
                    self.currentClaudeFeedback = ClaudeAPIClient.fallbackCue(for: exercise)
                }
            }
        }
    }

    private func buildPostSetPrompt(_ set: CompletedSet) -> String {
        """
        Exercise: \(set.exercise.rawValue)
        Reps: \(set.repCount)
        Form score: \(Int(set.averageFormScore * 100))%
        Duration: \(Int(set.duration))s

        Give one sentence of feedback on this set. Mention the form score only if it's below 80%. End with one specific thing to focus on next set.
        """
    }

    // MARK: - Claude: end-of-session call (Call 2 of 2)

    /// Fires when the state machine transitions to .sessionEnd.
    /// Detects PRs first (before the logger saves the session to CoreData),
    /// then fires the end-of-session Claude call. Result is persisted via
    /// WorkoutLogger.updateCoachingSummary(_:) and shown on the summary screen.
    private func handleSessionEnd() {
        let sets = stateMachine.completedSets
        personalRecords = detectPRs(currentSets: sets)

        isLoadingSessionFeedback = true
        claudeSessionFeedback = nil

        let prompt = buildSessionPrompt(sets: sets, prs: personalRecords)
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await claudeClient.send(prompt: prompt)
                await MainActor.run {
                    self.claudeSessionFeedback    = summary
                    self.isLoadingSessionFeedback = false
                    self.logger.updateCoachingSummary(summary)
                }
            } catch {
                await MainActor.run {
                    // Fallback: generic summary based on dominant exercise
                    let fallback = sets.first.map {
                        ClaudeAPIClient.fallbackCue(for: $0.exercise)
                    } ?? "Great work today — keep building consistency."
                    self.claudeSessionFeedback    = fallback
                    self.isLoadingSessionFeedback = false
                }
            }
        }
    }

    private func buildSessionPrompt(sets: [CompletedSet], prs: [String]) -> String {
        let byExercise = Dictionary(grouping: sets, by: \.exercise)
        let exerciseSummary = byExercise.map { exercise, exSets in
            let totalReps = exSets.map(\.repCount).reduce(0, +)
            let avgForm   = exSets.map(\.averageFormScore).reduce(0, +) / Double(exSets.count)
            return "\(exercise.rawValue): \(exSets.count) sets, \(totalReps) reps, " +
                   "avgFormScore: \(String(format: "%.2f", avgForm))"
        }.joined(separator: "\n")

        let prText = prs.isEmpty ? "none" : prs.joined(separator: ", ")

        return """
        Duration: \(Int(stateMachine.sessionElapsed / 60)) min
        \(exerciseSummary)
        PRs: \(prText)

        Write 2-3 sentences summing up this workout. What went well, what to improve next time. Talk directly to the person. No intro, just start with the feedback.
        """
    }

    // MARK: - PR detection

    /// Compares the current session's per-set rep counts against all historical
    /// ExerciseSetEntity records in CoreData. Returns PR strings for any exercise
    /// where the current session beat the previous best single-set rep count.
    ///
    /// Called before the logger saves the session, so historical data doesn't
    /// yet include this session — no need to subtract it out.
    private func detectPRs(currentSets: [CompletedSet]) -> [String] {
        let context = PersistenceController.shared.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ExerciseSetEntity")
        let historicalSets = (try? context.fetch(request)) ?? []

        var historicalMax: [String: Int] = [:]
        for obj in historicalSets {
            let exStr = obj.value(forKey: "exercise") as? String ?? ""
            let reps  = Int(obj.value(forKey: "repCount") as? Int32 ?? 0)
            historicalMax[exStr] = max(historicalMax[exStr] ?? 0, reps)
        }

        let currentMax = Dictionary(grouping: currentSets, by: \.exercise)
            .mapValues { $0.map(\.repCount).max() ?? 0 }

        return currentMax.compactMap { exercise, maxReps in
            let previous = historicalMax[exercise.rawValue] ?? 0
            return maxReps > previous ? "\(exercise.displayName) rep PR: \(maxReps)" : nil
        }.sorted()
    }
}
