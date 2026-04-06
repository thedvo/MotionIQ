/// Tracks rep phases for a single exercise using a hysteresis state machine.
/// Feed the primary angle each frame via process(angle:).
/// Exercise is now the shared top-level enum defined in Exercise.swift.
final class RepCounter {

    enum Phase: Equatable {
        case standing, descending, bottom, ascending

        // Explicit nonisolated == overrides the @MainActor-isolated synthesized version,
        // allowing Equatable to be used in test code (which runs nonisolated).
        nonisolated static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.standing, .standing), (.descending, .descending),
                 (.bottom, .bottom), (.ascending, .ascending): true
            default: false
            }
        }
    }

    private(set) var repCount: Int = 0
    private(set) var currentPhase: Phase = .standing

    private let exercise: Exercise

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    func reset() {
        repCount = 0
        currentPhase = .standing
    }

    /// Process one frame's primary angle. Returns true if a rep just completed.
    /// Caller is responsible for supplying the correct angle for the exercise:
    ///   squat/lunge → knee angle    pushup → elbow angle
    @discardableResult
    func process(angle: Double) -> Bool {
        switch exercise {
        case .squat:  return processPhases(angle: angle,
                                           standingThreshold: Constants.squatStandingAngle,
                                           bottomThreshold: Constants.squatBottomAngle)
        case .pushup: return processPhases(angle: angle,
                                           standingThreshold: Constants.pushupStandingAngle,
                                           bottomThreshold: Constants.pushupBottomAngle)
        case .lunge:  return processPhases(angle: angle,
                                           standingThreshold: Constants.lungeStandingAngle,
                                           bottomThreshold: Constants.lungeBottomAngle)
        }
    }

    // MARK: - Private

    /// Generic phase machine shared by all three exercises.
    /// `standingThreshold` = angle above which = standing/top position.
    /// `bottomThreshold`   = angle below which = bottom position.
    /// Hysteresis (±Constants.repHysteresis) prevents jitter at boundaries.
    ///
    /// Phase transitions:
    ///   standing   → descending : angle < standingThreshold
    ///   descending → bottom     : angle < bottomThreshold
    ///   descending → standing   : angle > standingThreshold + hysteresis (partial — no count)
    ///   bottom     → ascending  : angle > bottomThreshold + hysteresis
    ///   ascending  → standing   : angle > standingThreshold → rep counted
    ///   ascending  → bottom     : angle < bottomThreshold (went down again mid-rep)
    private func processPhases(angle: Double,
                                standingThreshold: Double,
                                bottomThreshold: Double) -> Bool {
        let h = Constants.repHysteresis

        switch currentPhase {
        case .standing:
            if angle < standingThreshold {
                currentPhase = .descending
            }

        case .descending:
            if angle < bottomThreshold {
                currentPhase = .bottom
            } else if angle > standingThreshold + h {
                currentPhase = .standing
            }

        case .bottom:
            if angle > bottomThreshold + h {
                currentPhase = .ascending
            }

        case .ascending:
            if angle > standingThreshold {
                currentPhase = .standing
                repCount += 1
                return true
            } else if angle < bottomThreshold {
                currentPhase = .bottom
            }
        }
        return false
    }
}
