import CoreGraphics

/// Specific form failures detected during a rep.
/// Used to drive real-time cue text in the UI.
enum FormFlag: String {
    // Squat
    case insufficientDepth      // knee angle too high at bottom
    case hipNotBelowKnee        // hip Y not below knee Y at bottom
    case forwardLean            // excessive torso lean

    // Pushup
    case elbowTooWide           // elbow angle out of range at bottom
    case hipSagging             // shoulder-hip-ankle alignment broken
    case wristNotUnderShoulder  // wrist too far from shoulder horizontally

    // Lunge
    case lungeKneeAngle         // front knee angle out of range
    case kneeNotOverFoot        // front knee drifting off ankle line
    case torsoNotUpright        // torso leaning in lunge

    var cueText: String {
        switch self {
        case .insufficientDepth:     "Go deeper"
        case .hipNotBelowKnee:       "Sit lower — hips below knees"
        case .forwardLean:           "Keep your chest up"
        case .elbowTooWide:          "Control your depth"
        case .hipSagging:            "Keep hips level"
        case .wristNotUnderShoulder: "Hands under shoulders"
        case .lungeKneeAngle:        "Bend front knee to 90°"
        case .kneeNotOverFoot:       "Track knee over foot"
        case .torsoNotUpright:       "Keep torso upright"
        }
    }
}

/// Result of scoring a single frame.
struct FormResult {
    /// 0.0–1.0: mean of all check scores this frame.
    let score: Double
    /// Flags for checks that did not pass — drives cue text.
    let flags: [FormFlag]
}

/// Stateless per-frame form evaluator.
/// Only scores during active movement phases (descending / bottom / ascending).
/// Returns nil during standing phase — nothing to evaluate.
enum FormScorer {

    /// Evaluate form for one frame. Returns nil if the phase is .standing (no useful data).
    static func score(pose: PoseData,
                      exercise: Exercise,
                      phase: RepCounter.Phase) -> FormResult? {
        guard phase != .standing else { return nil }

        switch exercise {
        case .squat:  return scoreSquat(pose: pose, phase: phase)
        case .pushup: return scorePushup(pose: pose, phase: phase)
        case .lunge:  return scoreLunge(pose: pose, phase: phase)
        }
    }

    // MARK: - Squat

    private static func scoreSquat(pose: PoseData, phase: RepCounter.Phase) -> FormResult {
        var scores: [Double] = []
        var flags: [FormFlag] = []

        // Check 1: knee angle at bottom
        if phase == .bottom, let kneeAngle = AngleCalculator.kneeAngle(from: pose) {
            let (s, passed) = rangeScore(value: kneeAngle,
                                         idealLow: Constants.squatKneeIdealLow,
                                         idealHigh: Constants.squatKneeIdealHigh,
                                         partialLow: Constants.squatKneePartialLow,
                                         partialHigh: Constants.squatKneePartialHigh)
            scores.append(s)
            if !passed { flags.append(.insufficientDepth) }
        }

        // Check 2: hip below knee at bottom (Vision Y: higher value = higher on screen)
        if phase == .bottom {
            if let hip = pose.joint(.leftHip) ?? pose.joint(.rightHip),
               let knee = pose.joint(.leftKnee) ?? pose.joint(.rightKnee) {
                // In Vision coords: hip.y < knee.y means hip is lower on screen
                if hip.point.y < knee.point.y {
                    scores.append(1.0)
                } else {
                    scores.append(0.0)
                    flags.append(.hipNotBelowKnee)
                }
            }
        }

        // Check 3: back lean (torso angle from vertical)
        if let lean = AngleCalculator.torsoAngleFromVertical(from: pose) {
            let s = thresholdScore(value: lean,
                                   ideal: Constants.squatBackLeanIdeal,
                                   partial: Constants.squatBackLeanPartial,
                                   lowerIsBetter: true)
            scores.append(s)
            if s < 1.0 { flags.append(.forwardLean) }
        }

        return FormResult(score: scores.isEmpty ? 1.0 : scores.reduce(0, +) / Double(scores.count),
                          flags: flags)
    }

    // MARK: - Pushup

    private static func scorePushup(pose: PoseData, phase: RepCounter.Phase) -> FormResult {
        var scores: [Double] = []
        var flags: [FormFlag] = []

        // Check 1: elbow angle at bottom
        if phase == .bottom, let elbowAngle = AngleCalculator.elbowAngle(from: pose) {
            let (s, passed) = rangeScore(value: elbowAngle,
                                         idealLow: Constants.pushupElbowIdealLow,
                                         idealHigh: Constants.pushupElbowIdealHigh,
                                         partialLow: Constants.pushupElbowPartialLow,
                                         partialHigh: Constants.pushupElbowPartialHigh)
            scores.append(s)
            if !passed { flags.append(.elbowTooWide) }
        }

        // Check 2: hip alignment (shoulder-hip-ankle)
        if let hipAngle = AngleCalculator.hipAlignmentAngle(from: pose) {
            let s = thresholdScore(value: hipAngle,
                                   ideal: Constants.pushupHipAlignmentIdealLow,
                                   partial: Constants.pushupHipAlignmentPartialLow,
                                   lowerIsBetter: false)
            scores.append(s)
            if s < 1.0 { flags.append(.hipSagging) }
        }

        // Check 3: wrist under shoulder
        if let offset = AngleCalculator.wristShoulderHorizontalOffset(from: pose) {
            let s = thresholdScore(value: offset,
                                   ideal: Constants.pushupWristShoulderIdeal,
                                   partial: Constants.pushupWristShoulderPartial,
                                   lowerIsBetter: true)
            scores.append(s)
            if s < 1.0 { flags.append(.wristNotUnderShoulder) }
        }

        return FormResult(score: scores.isEmpty ? 1.0 : scores.reduce(0, +) / Double(scores.count),
                          flags: flags)
    }

    // MARK: - Lunge

    private static func scoreLunge(pose: PoseData, phase: RepCounter.Phase) -> FormResult {
        var scores: [Double] = []
        var flags: [FormFlag] = []

        // Check 1: front knee angle at bottom
        if phase == .bottom, let kneeAngle = AngleCalculator.frontKneeAngle(from: pose) {
            // Ideal: 85–100°, partial: 101–115°, fail: >115°
            let s: Double
            if kneeAngle >= Constants.lungeKneeIdealLow && kneeAngle <= Constants.lungeKneeIdealHigh {
                s = 1.0
            } else if kneeAngle <= Constants.lungeKneePartialHigh {
                s = 0.5
            } else {
                s = 0.0
            }
            scores.append(s)
            if s < 1.0 { flags.append(.lungeKneeAngle) }
        }

        // Check 2: knee tracking over foot
        if let offset = AngleCalculator.frontKneeAnkleHorizontalOffset(from: pose) {
            let s = thresholdScore(value: offset,
                                   ideal: Constants.lungeKneeTrackingIdeal,
                                   partial: Constants.lungeKneeTrackingPartial,
                                   lowerIsBetter: true)
            scores.append(s)
            if s < 1.0 { flags.append(.kneeNotOverFoot) }
        }

        // Check 3: torso upright
        if let lean = AngleCalculator.torsoAngleFromVertical(from: pose) {
            let s = thresholdScore(value: lean,
                                   ideal: Constants.lungeTorsoIdeal,
                                   partial: Constants.lungeTorsoPartial,
                                   lowerIsBetter: true)
            scores.append(s)
            if s < 1.0 { flags.append(.torsoNotUpright) }
        }

        return FormResult(score: scores.isEmpty ? 1.0 : scores.reduce(0, +) / Double(scores.count),
                          flags: flags)
    }

    // MARK: - Scoring helpers

    /// Scores a value against an ideal range and partial range.
    /// Returns (1.0, true) if inside ideal, (0.5, false) if inside partial, (0.0, false) outside.
    private static func rangeScore(value: Double,
                                   idealLow: Double, idealHigh: Double,
                                   partialLow: Double, partialHigh: Double) -> (Double, Bool) {
        if value >= idealLow && value <= idealHigh { return (1.0, true) }
        if value >= partialLow && value <= partialHigh { return (0.5, false) }
        return (0.0, false)
    }

    /// Scores a single-threshold check: below `ideal` = 1.0, below `partial` = 0.5, else 0.0.
    /// `lowerIsBetter`: true means smaller values are good (e.g., lean angle);
    ///                  false means larger values are good (e.g., hip alignment angle).
    private static func thresholdScore(value: Double,
                                       ideal: Double,
                                       partial: Double,
                                       lowerIsBetter: Bool) -> Double {
        if lowerIsBetter {
            if value <= ideal  { return 1.0 }
            if value <= partial { return 0.5 }
            return 0.0
        } else {
            if value >= ideal  { return 1.0 }
            if value >= partial { return 0.5 }
            return 0.0
        }
    }
}
