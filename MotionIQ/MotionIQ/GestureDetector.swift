import Foundation

/// Gestures detected from pose data.
enum GestureEvent {
    case nextSet     // both wrists above shoulders 2s
    case endWorkout  // right wrist above shoulder, left NOT raised, 2s
    case pause       // arms crossed at chest (X shape), both above hip, 2s
}

/// Detects hands-raised and arm-cross gestures.
///
/// Vision Y convention: 0.0 = bottom of frame, 1.0 = top.
/// "Wrist above shoulder" = wrist.y > shoulder.y + gestureOffset.
///
/// Hold timers reset on ANY single frame where the condition is not met.
/// This prevents accidental triggers from normal arm movement during reps.
///
/// Gesture priority (highest → lowest): pause > nextSet > endWorkout
/// This prevents a crossed-arms raise from triggering nextSet simultaneously.
final class GestureDetector {

    var onGesture: ((GestureEvent) -> Void)?

    private var bothArmsHoldStart: Date?
    private var rightOnlyHoldStart: Date?
    private var crossedHoldStart: Date?

    // Grace counters — consecutive inactive frames before resetting a hold timer.
    // 4 frames ≈ 0.13s at 30fps. Prevents micro-wobbles from killing a nearly-complete hold.
    private let graceFrames = 4
    private var bothArmsGrace  = 0
    private var rightOnlyGrace = 0
    private var crossedGrace   = 0

    private var nextSetFired    = false
    private var endWorkoutFired = false
    private var pauseFired      = false

    func reset() {
        bothArmsHoldStart  = nil
        rightOnlyHoldStart = nil
        crossedHoldStart   = nil
        bothArmsGrace  = 0
        rightOnlyGrace = 0
        crossedGrace   = 0
        nextSetFired    = false
        endWorkoutFired = false
        pauseFired      = false
    }

    func process(pose: PoseData) {
        let leftRaised   = isWristAboveShoulder(.left,  pose: pose)
        let rightRaised  = isWristAboveShoulder(.right, pose: pose)
        let armsCrossed  = isArmsCrossed(pose: pose)

        // X gesture: arms crossed at chest, but NOT both raised above shoulders
        let crossActive = armsCrossed && !(leftRaised && rightRaised)
        updateHoldTimer(&crossedHoldStart, active: crossActive, grace: &crossedGrace)

        // Both arms up: both wrists above their shoulders
        updateHoldTimer(&bothArmsHoldStart, active: leftRaised && rightRaised, grace: &bothArmsGrace)

        // Right only: right wrist above shoulder, left NOT above shoulder
        updateHoldTimer(&rightOnlyHoldStart, active: rightRaised && !leftRaised, grace: &rightOnlyGrace)

        let now = Date()
        let crossHeld     = holdDuration(from: crossedHoldStart,  now: now) >= Constants.gestureHoldDuration
        let bothHeld      = holdDuration(from: bothArmsHoldStart, now: now) >= Constants.gestureHoldDuration
        let rightOnlyHeld = holdDuration(from: rightOnlyHoldStart, now: now) >= Constants.gestureHoldDuration

        // Evaluate in priority order
        if crossHeld && !pauseFired {
            pauseFired = true
            onGesture?(.pause)
            return
        }

        if bothHeld && !nextSetFired {
            nextSetFired = true
            endWorkoutFired = true  // suppress endWorkout from also firing
            onGesture?(.nextSet)
            return
        }

        if rightOnlyHeld && !endWorkoutFired {
            endWorkoutFired = true
            onGesture?(.endWorkout)
        }
    }

    // MARK: - Private

    private enum Side { case left, right }

    /// Returns true if the wrist on `side` is above the same-side shoulder + offset.
    private func isWristAboveShoulder(_ side: Side, pose: PoseData) -> Bool {
        let wrist: JointPosition?
        let shoulder: JointPosition?
        switch side {
        case .left:
            wrist    = pose.joint(.leftWrist)
            shoulder = pose.joint(.leftShoulder)
        case .right:
            wrist    = pose.joint(.rightWrist)
            shoulder = pose.joint(.rightShoulder)
        }
        guard let w = wrist, let s = shoulder else { return false }
        return w.point.y > s.point.y + Constants.gestureOffset
    }

    /// Returns true when both wrists have crossed centre (X shape).
    /// Requires both wrists above their respective hips (a deliberate, raised gesture).
    /// In Vision coords (with .leftMirrored): leftWrist.x > rightWrist.x means arms are crossed.
    private func isArmsCrossed(pose: PoseData) -> Bool {
        guard let leftWrist  = pose.joint(.leftWrist),
              let rightWrist = pose.joint(.rightWrist),
              let leftHip    = pose.joint(.leftHip),
              let rightHip   = pose.joint(.rightHip) else { return false }

        let leftAboveHip  = leftWrist.point.y  > leftHip.point.y
        let rightAboveHip = rightWrist.point.y > rightHip.point.y
        guard leftAboveHip && rightAboveHip else { return false }

        // Arms crossed: left wrist has moved past centre to the right, right wrist to the left
        return leftWrist.point.x > rightWrist.point.x
    }

    /// Start timer on first active frame.
    /// Only nil the timer after `graceFrames` consecutive inactive frames — not immediately.
    private func updateHoldTimer(_ start: inout Date?, active: Bool, grace: inout Int) {
        if active {
            grace = 0
            if start == nil { start = Date() }
        } else {
            grace += 1
            if grace > graceFrames {
                start = nil
                grace = 0
            }
        }
    }

    private func holdDuration(from start: Date?, now: Date) -> TimeInterval {
        guard let start else { return 0 }
        return now.timeIntervalSince(start)
    }
}
