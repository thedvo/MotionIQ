import Foundation

enum Constants {
    // MARK: - Vision
    /// Joints below this confidence are discarded entirely — no interpolation.
    static let jointConfidenceThreshold: Float = 0.6

    // MARK: - Rep counting — squat
    static let squatStandingAngle: Double = 155   // degrees; above this = standing
    static let squatBottomAngle: Double = 100     // degrees; below this = bottom
    static let repHysteresis: Double = 10         // prevents jitter at phase boundaries

    // MARK: - Rep counting — pushup
    static let pushupStandingAngle: Double = 150  // elbow angle; above this = top position
    static let pushupBottomAngle: Double = 100    // elbow angle; below this = bottom

    // MARK: - Rep counting — lunge
    static let lungeStandingAngle: Double = 155   // front knee angle; above this = standing
    static let lungeBottomAngle: Double = 105     // front knee angle; below this = bottom

    // MARK: - Exercise classifier
    static let classifierLockFrames: Int = 3      // consecutive matching frames before locking
    static let classifierPushupTorsoAngle: Double = 30  // hip-shoulder from horizontal; below = horizontal
    static let classifierSquatTorsoAngle: Double = 60   // hip-shoulder from horizontal; above = vertical
    static let classifierLungeAsymmetricBentKnee: Double = 120   // bent knee below this
    static let classifierLungeAsymmetricStraightKnee: Double = 140 // opposite knee above this

    // MARK: - Form scoring — squat
    static let squatKneeIdealLow: Double = 85
    static let squatKneeIdealHigh: Double = 95
    static let squatKneePartialLow: Double = 75
    static let squatKneePartialHigh: Double = 110
    static let squatBackLeanIdeal: Double = 30    // degrees from vertical; below = ideal
    static let squatBackLeanPartial: Double = 45

    // MARK: - Form scoring — pushup
    static let pushupElbowIdealLow: Double = 85
    static let pushupElbowIdealHigh: Double = 95
    static let pushupElbowPartialLow: Double = 75
    static let pushupElbowPartialHigh: Double = 110
    static let pushupHipAlignmentIdealLow: Double = 170  // shoulder-hip-ankle; below = sag
    static let pushupHipAlignmentPartialLow: Double = 160
    static let pushupWristShoulderIdeal: Double = 0.10   // fraction of frame width
    static let pushupWristShoulderPartial: Double = 0.20

    // MARK: - Form scoring — lunge
    static let lungeKneeIdealLow: Double = 85
    static let lungeKneeIdealHigh: Double = 100
    static let lungeKneePartialHigh: Double = 115
    static let lungeKneeTrackingIdeal: Double = 0.15     // knee-ankle X offset fraction
    static let lungeKneeTrackingPartial: Double = 0.25
    static let lungeTorsoIdeal: Double = 10              // shoulder-hip from vertical
    static let lungeTorsoPartial: Double = 20

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
