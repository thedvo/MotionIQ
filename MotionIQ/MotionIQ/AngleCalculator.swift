import CoreGraphics

/// Stateless geometry utilities for computing joint angles from pose data.
/// All functions are pure — no Vision types, no camera dependency — making them fully unit-testable.
enum AngleCalculator {

    /// Returns the angle in degrees at `vertex`, formed by vectors to `a` and `b`.
    /// Works with Vision's normalized coordinate space (0.0–1.0).
    /// Returns 0 if either vector has zero magnitude (coincident points).
    static func angle(a: CGPoint, vertex: CGPoint, b: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag = sqrt(v1.dx * v1.dx + v1.dy * v1.dy) * sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard mag > 0 else { return 0 }
        return acos(max(-1, min(1, dot / mag))) * 180 / .pi
    }

    /// Hip → knee → ankle angle. Tries left side first; falls back to right.
    /// Returns nil if neither side has sufficient joint confidence.
    static func kneeAngle(from pose: PoseData) -> Double? {
        if let hip = pose.joint(.leftHip),
           let knee = pose.joint(.leftKnee),
           let ankle = pose.joint(.leftAnkle) {
            return angle(a: hip.point, vertex: knee.point, b: ankle.point)
        }
        if let hip = pose.joint(.rightHip),
           let knee = pose.joint(.rightKnee),
           let ankle = pose.joint(.rightAnkle) {
            return angle(a: hip.point, vertex: knee.point, b: ankle.point)
        }
        return nil
    }

    /// Shoulder → elbow → wrist angle. Tries left side first; falls back to right.
    static func elbowAngle(from pose: PoseData) -> Double? {
        if let shoulder = pose.joint(.leftShoulder),
           let elbow = pose.joint(.leftElbow),
           let wrist = pose.joint(.leftWrist) {
            return angle(a: shoulder.point, vertex: elbow.point, b: wrist.point)
        }
        if let shoulder = pose.joint(.rightShoulder),
           let elbow = pose.joint(.rightElbow),
           let wrist = pose.joint(.rightWrist) {
            return angle(a: shoulder.point, vertex: elbow.point, b: wrist.point)
        }
        return nil
    }

    /// Angle of the hip–shoulder vector from vertical (0° = perfectly upright torso).
    /// Uses left side first; falls back to right.
    /// Vision Y is flipped (1.0 = top), so "up" is the +Y direction.
    static func torsoAngleFromVertical(from pose: PoseData) -> Double? {
        let hip: JointPosition?
        let shoulder: JointPosition?
        if let lh = pose.joint(.leftHip), let ls = pose.joint(.leftShoulder) {
            hip = lh; shoulder = ls
        } else if let rh = pose.joint(.rightHip), let rs = pose.joint(.rightShoulder) {
            hip = rh; shoulder = rs
        } else {
            return nil
        }
        guard let h = hip, let s = shoulder else { return nil }
        // Vector from hip to shoulder
        let dx = s.point.x - h.point.x
        let dy = s.point.y - h.point.y
        // Angle from vertical (+Y axis) using atan2
        return abs(atan2(dx, dy) * 180 / .pi)
    }

    /// Angle of the hip–shoulder vector from horizontal (0° = fully horizontal torso).
    /// Used by the exercise classifier to distinguish vertical vs. horizontal body orientation.
    static func torsoAngleFromHorizontal(from pose: PoseData) -> Double? {
        guard let verticalAngle = torsoAngleFromVertical(from: pose) else { return nil }
        return abs(90 - verticalAngle)
    }

    /// Shoulder → hip → ankle angle. Measures hip alignment (sagging/piking in pushups).
    /// Tries left side first; falls back to right.
    static func hipAlignmentAngle(from pose: PoseData) -> Double? {
        if let shoulder = pose.joint(.leftShoulder),
           let hip = pose.joint(.leftHip),
           let ankle = pose.joint(.leftAnkle) {
            return angle(a: shoulder.point, vertex: hip.point, b: ankle.point)
        }
        if let shoulder = pose.joint(.rightShoulder),
           let hip = pose.joint(.rightHip),
           let ankle = pose.joint(.rightAnkle) {
            return angle(a: shoulder.point, vertex: hip.point, b: ankle.point)
        }
        return nil
    }

    /// Horizontal offset between wrist and shoulder as a fraction of the normalized frame width.
    /// Used to check wrist-under-shoulder alignment in pushups.
    /// Returns nil if neither side has sufficient confidence.
    static func wristShoulderHorizontalOffset(from pose: PoseData) -> Double? {
        if let shoulder = pose.joint(.leftShoulder),
           let wrist = pose.joint(.leftWrist) {
            return abs(wrist.point.x - shoulder.point.x)
        }
        if let shoulder = pose.joint(.rightShoulder),
           let wrist = pose.joint(.rightWrist) {
            return abs(wrist.point.x - shoulder.point.x)
        }
        return nil
    }

    /// Front knee angle for lunges: picks the more-bent knee (lower angle).
    /// Returns nil if neither side has sufficient confidence.
    static func frontKneeAngle(from pose: PoseData) -> Double? {
        let left = kneeAngle(side: .left, from: pose)
        let right = kneeAngle(side: .right, from: pose)
        switch (left, right) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    /// Knee X offset from ankle X as a fraction of the normalized frame width.
    /// Used to check knee-over-foot tracking in lunges.
    /// Evaluates the more-bent (front) knee side.
    static func frontKneeAnkleHorizontalOffset(from pose: PoseData) -> Double? {
        let left = kneeAngle(side: .left, from: pose)
        let right = kneeAngle(side: .right, from: pose)
        // Pick the side with the more bent knee (lower angle = front leg)
        let usedSide: Side
        switch (left, right) {
        case let (l?, r?): usedSide = l < r ? .left : .right
        case (.some, nil): usedSide = .left
        case (nil, .some): usedSide = .right
        default: return nil
        }
        if usedSide == .left,
           let knee = pose.joint(.leftKnee),
           let ankle = pose.joint(.leftAnkle) {
            return abs(knee.point.x - ankle.point.x)
        }
        if usedSide == .right,
           let knee = pose.joint(.rightKnee),
           let ankle = pose.joint(.rightAnkle) {
            return abs(knee.point.x - ankle.point.x)
        }
        return nil
    }

    // MARK: - Private helpers

    private enum Side { case left, right }

    private static func kneeAngle(side: Side, from pose: PoseData) -> Double? {
        switch side {
        case .left:
            guard let hip = pose.joint(.leftHip),
                  let knee = pose.joint(.leftKnee),
                  let ankle = pose.joint(.leftAnkle) else { return nil }
            return angle(a: hip.point, vertex: knee.point, b: ankle.point)
        case .right:
            guard let hip = pose.joint(.rightHip),
                  let knee = pose.joint(.rightKnee),
                  let ankle = pose.joint(.rightAnkle) else { return nil }
            return angle(a: hip.point, vertex: knee.point, b: ankle.point)
        }
    }
}
