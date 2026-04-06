import CoreGraphics

/// Identifies which exercise the user is performing from pose data.
///
/// Rules are evaluated in priority order (pushup → squat → lunge) each frame.
/// Classification locks after `Constants.classifierLockFrames` consecutive matching frames.
/// Once locked, the classification does not change until reset() is called.
///
/// All detection logic uses AngleCalculator and Vision Y-coordinate conventions:
///   Y = 0.0 (bottom of frame) → 1.0 (top of frame)
final class ExerciseClassifier {

    /// The locked exercise, or nil if not yet classified.
    private(set) var detectedExercise: Exercise?

    private var consecutiveCounts: [Exercise: Int] = [:]

    /// Reset classification state. Call when a new set begins.
    func reset() {
        detectedExercise = nil
        consecutiveCounts = [:]
    }

    /// Process one frame. Returns the locked exercise once confidence threshold is met.
    @discardableResult
    func process(pose: PoseData) -> Exercise? {
        // Once locked, do not re-classify
        if let locked = detectedExercise { return locked }

        let candidate = classify(pose: pose)

        // Increment the matching candidate; reset all others
        for exercise in Exercise.allCases {
            if exercise == candidate {
                consecutiveCounts[exercise, default: 0] += 1
            } else {
                consecutiveCounts[exercise] = 0
            }
        }

        // Lock if we've seen the same exercise for enough consecutive frames
        if let candidate,
           let count = consecutiveCounts[candidate],
           count >= Constants.classifierLockFrames {
            detectedExercise = candidate
        }

        return detectedExercise
    }

    // MARK: - Private classification rules

    /// Returns the best matching Exercise for this frame, or nil if no rule matches.
    /// Priority: pushup → squat → lunge (avoids misclassification at overlap points).
    private func classify(pose: PoseData) -> Exercise? {
        if isPushup(pose: pose)  { return .pushup }
        if isSquat(pose: pose)   { return .squat }
        if isLunge(pose: pose)   { return .lunge }
        return nil
    }

    /// Pushup: both wrists below hip Y AND torso near horizontal.
    /// "Below hip" in Vision coords = wrist.y < hip.y (lower Y = lower on screen).
    private func isPushup(pose: PoseData) -> Bool {
        guard let torsoAngle = AngleCalculator.torsoAngleFromHorizontal(from: pose),
              torsoAngle < Constants.classifierPushupTorsoAngle else { return false }

        // Both wrists must be below hip
        let leftOk: Bool
        if let wrist = pose.joint(.leftWrist), let hip = pose.joint(.leftHip) {
            leftOk = wrist.point.y < hip.point.y
        } else {
            leftOk = false
        }
        let rightOk: Bool
        if let wrist = pose.joint(.rightWrist), let hip = pose.joint(.rightHip) {
            rightOk = wrist.point.y < hip.point.y
        } else {
            rightOk = false
        }
        return leftOk && rightOk
    }

    /// Squat: torso near vertical AND hip Y cycling below knee Y.
    /// "Hip below knee" = hip.y < knee.y in Vision coords.
    private func isSquat(pose: PoseData) -> Bool {
        guard let torsoAngle = AngleCalculator.torsoAngleFromHorizontal(from: pose),
              torsoAngle > Constants.classifierSquatTorsoAngle else { return false }

        let leftHipBelowKnee: Bool
        if let hip = pose.joint(.leftHip), let knee = pose.joint(.leftKnee) {
            leftHipBelowKnee = hip.point.y < knee.point.y
        } else {
            leftHipBelowKnee = false
        }
        let rightHipBelowKnee: Bool
        if let hip = pose.joint(.rightHip), let knee = pose.joint(.rightKnee) {
            rightHipBelowKnee = hip.point.y < knee.point.y
        } else {
            rightHipBelowKnee = false
        }
        // Either side is sufficient (camera may only clearly see one side)
        return leftHipBelowKnee || rightHipBelowKnee
    }

    /// Lunge: torso vertical AND asymmetric knee angles (one bent, one extended).
    private func isLunge(pose: PoseData) -> Bool {
        guard let torsoAngle = AngleCalculator.torsoAngleFromHorizontal(from: pose),
              torsoAngle > Constants.classifierSquatTorsoAngle else { return false }

        let leftKnee  = kneeAngle(side: .left, pose: pose)
        let rightKnee = kneeAngle(side: .right, pose: pose)

        guard let left = leftKnee, let right = rightKnee else { return false }

        let asymmetric = (left  < Constants.classifierLungeAsymmetricBentKnee &&
                          right > Constants.classifierLungeAsymmetricStraightKnee) ||
                         (right < Constants.classifierLungeAsymmetricBentKnee &&
                          left  > Constants.classifierLungeAsymmetricStraightKnee)
        return asymmetric
    }

    // MARK: - Helpers

    private enum Side { case left, right }

    private func kneeAngle(side: Side, pose: PoseData) -> Double? {
        switch side {
        case .left:
            guard let hip   = pose.joint(.leftHip),
                  let knee  = pose.joint(.leftKnee),
                  let ankle = pose.joint(.leftAnkle) else { return nil }
            return AngleCalculator.angle(a: hip.point, vertex: knee.point, b: ankle.point)
        case .right:
            guard let hip   = pose.joint(.rightHip),
                  let knee  = pose.joint(.rightKnee),
                  let ankle = pose.joint(.rightAnkle) else { return nil }
            return AngleCalculator.angle(a: hip.point, vertex: knee.point, b: ankle.point)
        }
    }
}
