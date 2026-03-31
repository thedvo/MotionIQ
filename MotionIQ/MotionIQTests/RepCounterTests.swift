import XCTest
@testable import MotionIQ

final class RepCounterTests: XCTestCase {

    var counter: RepCounter!

    override func setUp() {
        counter = RepCounter(exercise: .squat)
    }

    func testInitialState() {
        XCTAssertEqual(counter.repCount, 0)
        XCTAssertEqual(counter.currentPhase, .standing)
    }

    func testFullRepCycle() {
        counter.process(angle: 160)  // standing → no change
        XCTAssertEqual(counter.currentPhase, .standing)

        counter.process(angle: 140)  // standing → descending
        XCTAssertEqual(counter.currentPhase, .descending)

        counter.process(angle: 90)   // descending → bottom
        XCTAssertEqual(counter.currentPhase, .bottom)

        counter.process(angle: 115)  // bottom → ascending (115 > 100 + 10 hysteresis)
        XCTAssertEqual(counter.currentPhase, .ascending)

        let repCompleted = counter.process(angle: 160)  // ascending → standing + rep counted
        XCTAssertTrue(repCompleted)
        XCTAssertEqual(counter.repCount, 1)
        XCTAssertEqual(counter.currentPhase, .standing)
    }

    func testPartialDescentDoesNotCountRep() {
        // User starts to descend but comes back up before reaching bottom
        counter.process(angle: 160)  // standing
        counter.process(angle: 140)  // descending
        counter.process(angle: 170)  // rose above standing + hysteresis (155 + 10 = 165)
        XCTAssertEqual(counter.currentPhase, .standing)
        XCTAssertEqual(counter.repCount, 0)
    }

    func testHysteresisAtBottom() {
        // Angle just above bottom threshold should NOT transition to ascending
        counter.process(angle: 160)  // standing
        counter.process(angle: 140)  // descending
        counter.process(angle: 90)   // bottom

        counter.process(angle: 105)  // 105 < 100 + 10 hysteresis — still bottom
        XCTAssertEqual(counter.currentPhase, .bottom)

        counter.process(angle: 115)  // 115 > 110 — now ascending
        XCTAssertEqual(counter.currentPhase, .ascending)
    }

    func testMultipleReps() {
        for _ in 1...3 {
            counter.process(angle: 160)  // standing (ensure clean start)
            counter.process(angle: 140)  // descending
            counter.process(angle: 90)   // bottom
            counter.process(angle: 115)  // ascending
            counter.process(angle: 160)  // standing + rep
        }
        XCTAssertEqual(counter.repCount, 3)
    }

    func testReset() {
        counter.process(angle: 160)
        counter.process(angle: 140)
        counter.process(angle: 90)
        counter.reset()
        XCTAssertEqual(counter.repCount, 0)
        XCTAssertEqual(counter.currentPhase, .standing)
    }

    func testAscendingBackToBottomDoesNotCountRep() {
        // Goes up partway then back down — should not count
        counter.process(angle: 160)  // standing
        counter.process(angle: 140)  // descending
        counter.process(angle: 90)   // bottom
        counter.process(angle: 115)  // ascending
        counter.process(angle: 85)   // dropped back to bottom
        XCTAssertEqual(counter.currentPhase, .bottom)
        XCTAssertEqual(counter.repCount, 0)
    }
}
