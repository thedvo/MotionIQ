import XCTest
@testable import MotionIQ

final class AngleCalculatorTests: XCTestCase {

    func testRightAngle() {
        // Three points forming a 90° angle at the origin
        let a = CGPoint(x: 0, y: 1)
        let vertex = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 1, y: 0)
        XCTAssertEqual(AngleCalculator.angle(a: a, vertex: vertex, b: b), 90.0, accuracy: 0.001)
    }

    func testStraightLine() {
        // Collinear points = 180°
        let a = CGPoint(x: 0, y: 0)
        let vertex = CGPoint(x: 0.5, y: 0)
        let b = CGPoint(x: 1, y: 0)
        XCTAssertEqual(AngleCalculator.angle(a: a, vertex: vertex, b: b), 180.0, accuracy: 0.001)
    }

    func testFortyFiveDegrees() {
        let a = CGPoint(x: 0, y: 1)
        let vertex = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 1, y: 1)
        XCTAssertEqual(AngleCalculator.angle(a: a, vertex: vertex, b: b), 45.0, accuracy: 0.001)
    }

    func testCoincidentPointsReturnsZero() {
        // Guard against divide-by-zero
        let point = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(AngleCalculator.angle(a: point, vertex: point, b: point), 0.0)
    }

    func testKneeAngleUsesLeftSideFirst() {
        // Build a PoseData with only left-side joints above confidence threshold
        let joints: [PoseData.JointName: JointPosition] = [
            .leftHip:   JointPosition(point: CGPoint(x: 0.5, y: 0.6), confidence: 0.9),
            .leftKnee:  JointPosition(point: CGPoint(x: 0.5, y: 0.4), confidence: 0.9),
            .leftAnkle: JointPosition(point: CGPoint(x: 0.6, y: 0.2), confidence: 0.9),
        ]
        let pose = PoseData(joints: joints)
        let result = AngleCalculator.kneeAngle(from: pose)
        XCTAssertNotNil(result)
    }

    func testKneeAngleReturnsNilWhenNoJointsAboveThreshold() {
        let joints: [PoseData.JointName: JointPosition] = [
            .leftHip:   JointPosition(point: .zero, confidence: 0.1),  // below threshold
            .leftKnee:  JointPosition(point: .zero, confidence: 0.1),
            .leftAnkle: JointPosition(point: .zero, confidence: 0.1),
        ]
        let pose = PoseData(joints: joints)
        XCTAssertNil(AngleCalculator.kneeAngle(from: pose))
    }
}
