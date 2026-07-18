import XCTest
@testable import Daybreak

final class CaptureEngineTests: XCTestCase {
    let today = "2026-07-15"

    struct Boom: Error {}

    func testValidPrimaryResultIsUsed() async {
        let expected = Classification(bucket: .progress, day: today, startMin: 600,
                                      durationMin: 60, cleanedTitle: "From model",
                                      confidence: 0.8)
        let engine = CaptureEngine(primary: { _, _ in expected })
        let r = await engine.classify("anything", today: today)
        XCTAssertEqual(r, expected)
    }

    func testThrowingPrimaryFallsBackToRules() async {
        let engine = CaptureEngine(primary: { _, _ in throw Boom() })
        let r = await engine.classify("call the client", today: today)
        XCTAssertEqual(r.bucket, .urgent)          // rule-based result
        XCTAssertEqual(r.cleanedTitle, "Call the client")
    }

    func testOutOfRangePrimaryFallsBack() async {
        let bad = Classification(bucket: .urgent, day: "nonsense", startMin: 99999,
                                 durationMin: -5, cleanedTitle: "x", confidence: 9)
        let engine = CaptureEngine(primary: { _, _ in bad })
        let r = await engine.classify("tidy the desk", today: today)
        XCTAssertEqual(r.bucket, .extra)           // fell back to rules
    }

    func testNoPrimaryUsesRules() async {
        let engine = CaptureEngine()
        let r = await engine.classify("plan the roadmap", today: today)
        XCTAssertEqual(r.bucket, .progress)
    }

    func testIsInRange() {
        let ok = Classification(bucket: .urgent, day: "2026-07-15", startMin: 540,
                                durationMin: 30, cleanedTitle: "x", confidence: 0.7)
        XCTAssertTrue(ok.isInRange)
        var bad = ok; bad.day = "2026/07/15"; XCTAssertFalse(bad.isInRange)
        bad = ok; bad.startMin = 1440; XCTAssertFalse(bad.isInRange)
        bad = ok; bad.durationMin = 0; XCTAssertFalse(bad.isInRange)
        bad = ok; bad.confidence = 1.5; XCTAssertFalse(bad.isInRange)
        var nilled = ok; nilled.startMin = nil; nilled.durationMin = nil
        XCTAssertTrue(nilled.isInRange)
    }

    func testFactoryReturnsAWorkingClassifier() async {
        let r = await Capture.makeClassifier().classify("call today", today: today)
        XCTAssertTrue(r.isInRange)
    }

    #if canImport(FoundationModels)
    // Pins every branch of the model-output normalization without invoking the model.
    @available(iOS 26, *)
    func testCaptureGuessNormalization() {
        let full = CaptureGuess(bucket: "URGENT", day: "2026-07-15", startMin: 900,
                                durationMin: 30, cleanedTitle: "Call", confidence: 0.9)
            .asClassification()
        XCTAssertEqual(full.bucket, .urgent)          // case-insensitive raw match
        XCTAssertEqual(full.startMin, 900)
        XCTAssertEqual(full.durationMin, 30)

        let empty = CaptureGuess(bucket: "nonsense", day: "2026-07-15", startMin: -1,
                                 durationMin: -1, cleanedTitle: "x", confidence: 0.3)
            .asClassification()
        XCTAssertEqual(empty.bucket, .extra)          // unknown -> .extra
        XCTAssertNil(empty.startMin)                  // -1 -> nil
        XCTAssertNil(empty.durationMin)               // -1 -> nil
    }
    #endif
}
