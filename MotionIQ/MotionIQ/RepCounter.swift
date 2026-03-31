/// Tracks rep phases for a single exercise using a hysteresis state machine.
/// Feed the primary angle each frame via process(angle:).
/// Phase 1 supports squat only; additional exercises added in Phase 2.
final class RepCounter {

    enum Exercise {
        case squat
    }

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
    @discardableResult
    func process(angle: Double) -> Bool {
        switch exercise {
        case .squat:
            return processSquat(kneeAngle: angle)
        }
    }

    // MARK: - Private

    /// Squat rep phase machine.
    /// Thresholds from Constants; ±hysteresis prevents jitter at boundaries.
    ///
    /// Phase transitions:
    ///   standing    → descending  : angle drops below squatStandingAngle
    ///   descending  → bottom      : angle drops below squatBottomAngle
    ///   descending  → standing    : angle rises back above standing + hysteresis (partial rep, no count)
    ///   bottom      → ascending   : angle rises above bottom + hysteresis
    ///   ascending   → standing    : angle rises above squatStandingAngle → rep counted
    ///   ascending   → bottom      : angle drops back below bottom (went down again mid-rep)
    private func processSquat(kneeAngle: Double) -> Bool {
        let standing = Constants.squatStandingAngle
        let bottom = Constants.squatBottomAngle
        let h = Constants.repHysteresis

        switch currentPhase {
        case .standing:
            if kneeAngle < standing {
                currentPhase = .descending
            }

        case .descending:
            if kneeAngle < bottom {
                currentPhase = .bottom
            } else if kneeAngle > standing + h {
                // Rose back up before reaching bottom — not a valid rep
                currentPhase = .standing
            }

        case .bottom:
            if kneeAngle > bottom + h {
                currentPhase = .ascending
            }

        case .ascending:
            if kneeAngle > standing {
                currentPhase = .standing
                repCount += 1
                return true
            } else if kneeAngle < bottom {
                // Went back down mid-ascent
                currentPhase = .bottom
            }
        }
        return false
    }
}
