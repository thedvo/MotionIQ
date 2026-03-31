import CoreGraphics
import Vision

/// A single joint's position and detection confidence.
/// Position is in Vision's normalized coordinate space:
///   x: 0.0 (left) → 1.0 (right)
///   y: 0.0 (bottom) → 1.0 (top)  ← Y is flipped vs. UIKit/SwiftUI
struct JointPosition {
    let point: CGPoint
    let confidence: Float
}

/// Plain Swift representation of a detected body pose.
/// All exercise logic downstream depends on this type, never on Vision types directly.
/// This is the testability boundary — unit tests construct PoseData with arbitrary values.
struct PoseData {
    let joints: [JointName: JointPosition]

    enum JointName: String, CaseIterable {
        case nose, leftEye, rightEye, leftEar, rightEar
        case neck
        case leftShoulder, rightShoulder
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
        case root  // mid-hip point
    }

    /// Returns the joint only if its confidence meets the threshold.
    /// All callers should use this method rather than accessing joints directly.
    func joint(_ name: JointName) -> JointPosition? {
        guard let pos = joints[name], pos.confidence >= Constants.jointConfidenceThreshold else {
            return nil
        }
        return pos
    }
}

// MARK: - Vision conversion

extension PoseData {
    /// Converts a Vision observation into our plain struct.
    /// Called once per frame on the background processingQueue — must be nonisolated.
    nonisolated init(from observation: VNHumanBodyPoseObservation) {
        let mapping: [(VNHumanBodyPoseObservation.JointName, JointName)] = [
            (.nose, .nose),
            (.leftEye, .leftEye),
            (.rightEye, .rightEye),
            (.leftEar, .leftEar),
            (.rightEar, .rightEar),
            (.neck, .neck),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle),
            (.root, .root),
        ]

        var joints: [JointName: JointPosition] = [:]
        for (visionName, ourName) in mapping {
            if let point = try? observation.recognizedPoint(visionName) {
                joints[ourName] = JointPosition(
                    point: CGPoint(x: point.x, y: point.y),
                    confidence: point.confidence
                )
            }
        }
        self.joints = joints
    }
}
