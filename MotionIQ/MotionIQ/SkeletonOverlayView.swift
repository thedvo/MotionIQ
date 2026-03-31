import SwiftUI

/// Draws skeleton joints and bones over the camera feed for visual verification.
/// This is the primary tool for confirming Vision detection is working correctly.
struct SkeletonOverlayView: View {

    let pose: PoseData?

    // Pairs of joints to connect with lines (bones).
    private let connections: [(PoseData.JointName, PoseData.JointName)] = [
        // Head / neck
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        // Arms
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        // Torso
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        // Legs
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        GeometryReader { geometry in
            if let pose {
                Canvas { context, size in
                    // Draw bones first so joints render on top
                    for (from, to) in connections {
                        guard
                            let fromJoint = pose.joint(from),
                            let toJoint = pose.joint(to)
                        else { continue }

                        var path = Path()
                        path.move(to: toScreen(fromJoint.point, in: size))
                        path.addLine(to: toScreen(toJoint.point, in: size))
                        context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 2)
                    }

                    // Draw joint dots — colored by confidence for debugging
                    for name in PoseData.JointName.allCases {
                        guard let joint = pose.joints[name] else { continue }
                        let center = toScreen(joint.point, in: size)
                        let radius: CGFloat = joint.confidence >= Constants.jointConfidenceThreshold ? 5 : 3
                        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                         width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor(for: joint.confidence)))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    // MARK: - Helpers

    /// Vision: (0,0) = bottom-left, (1,1) = top-right
    /// SwiftUI: (0,0) = top-left
    /// Flip Y: screenY = (1 - visionY) * height
    private func toScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    private func dotColor(for confidence: Float) -> Color {
        switch confidence {
        case 0.8...:    return .green
        case 0.6..<0.8: return .yellow
        default:        return .red.opacity(0.6)
        }
    }
}
