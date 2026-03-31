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
}
