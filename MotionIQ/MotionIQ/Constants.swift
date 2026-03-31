import Foundation

enum Constants {
    // MARK: - Vision
    /// Joints below this confidence are discarded entirely — no interpolation.
    static let jointConfidenceThreshold: Float = 0.6

    // MARK: - Rep counting — squat
    static let squatStandingAngle: Double = 155   // degrees; above this = standing
    static let squatBottomAngle: Double = 100     // degrees; below this = bottom
    static let repHysteresis: Double = 10         // prevents jitter at phase boundaries

    // MARK: - Rest detection
    static let restVelocityThreshold: Double = 0.005  // normalized units/frame
    static let restFrameWindow: Int = 90               // ~3s at 30fps
    static let inactivityTimeout: TimeInterval = 60

    // MARK: - Gesture detection
    static let gestureHoldDuration: TimeInterval = 2.0
    static let gestureOffset: Double = 0.05  // wrist must be 5% of frame above shoulder

    // MARK: - Form scoring UI
    static let formScoreGreen: Double = 0.80
    static let formScoreYellow: Double = 0.60
}
