import CoreGraphics

/// Detects when the user has stopped moving by tracking hip joint velocity
/// over a rolling window of frames.
///
/// Each frame: append the current hip position, compute mean Euclidean velocity
/// across the window. If mean < restVelocityThreshold for a full window → fires onRest.
///
/// Falls back to shoulder joint if hip confidence is below threshold.
/// Reset the buffer when a new set begins so accumulated stillness from a previous
/// set doesn't immediately re-trigger rest in the next one.
final class RestDetector {

    /// Called once when rest is first detected. Not called again until reset() + re-detection.
    var onRest: (() -> Void)?

    private var positionBuffer: [CGPoint] = []
    private var hasFiredRest = false

    func reset() {
        positionBuffer = []
        hasFiredRest = false
    }

    /// Process one frame. Supply the current pose; the detector picks the best available joint.
    func process(pose: PoseData) {
        guard !hasFiredRest else { return }

        guard let position = hipOrShoulderPosition(from: pose) else { return }

        positionBuffer.append(position)

        // Keep only the most recent window
        if positionBuffer.count > Constants.restFrameWindow {
            positionBuffer.removeFirst()
        }

        // Don't evaluate until we have a full window
        guard positionBuffer.count == Constants.restFrameWindow else { return }

        let meanVelocity = computeMeanVelocity(positions: positionBuffer)
        if meanVelocity < Constants.restVelocityThreshold {
            hasFiredRest = true
            onRest?()
        }
    }

    // MARK: - Private

    /// Returns the hip joint position if above confidence threshold; falls back to shoulder.
    private func hipOrShoulderPosition(from pose: PoseData) -> CGPoint? {
        if let hip = pose.joint(.leftHip) ?? pose.joint(.rightHip) {
            return hip.point
        }
        if let shoulder = pose.joint(.leftShoulder) ?? pose.joint(.rightShoulder) {
            return shoulder.point
        }
        return nil
    }

    /// Mean Euclidean distance between consecutive positions in the buffer.
    private func computeMeanVelocity(positions: [CGPoint]) -> Double {
        guard positions.count > 1 else { return 0 }
        var totalDistance = 0.0
        for i in 1 ..< positions.count {
            let dx = positions[i].x - positions[i - 1].x
            let dy = positions[i].y - positions[i - 1].y
            totalDistance += sqrt(dx * dx + dy * dy)
        }
        return totalDistance / Double(positions.count - 1)
    }
}
