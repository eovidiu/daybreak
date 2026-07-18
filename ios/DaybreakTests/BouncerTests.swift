import XCTest
@testable import Daybreak

final class BouncerTests: XCTestCase {
    func testGateIsInclusiveAtThreshold() {
        XCTAssertTrue(Bouncer.autoFiles(confidence: 0.6, threshold: 0.6))
        XCTAssertTrue(Bouncer.autoFiles(confidence: 0.75, threshold: 0.6))
        XCTAssertFalse(Bouncer.autoFiles(confidence: 0.59, threshold: 0.6))
    }

    func testThresholdClampsToBand() {
        XCTAssertEqual(CaptureThreshold.clamp(0.1), 0.3, accuracy: 0.0001)
        XCTAssertEqual(CaptureThreshold.clamp(0.99), 0.9, accuracy: 0.0001)
        XCTAssertEqual(CaptureThreshold.clamp(0.55), 0.55, accuracy: 0.0001)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "bouncer-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testLoadReturnsDefaultWhenUnset() {
        XCTAssertEqual(CaptureThreshold.load(freshDefaults()),
                       CaptureThreshold.defaultValue, accuracy: 0.0001)
    }

    func testSaveThenLoadRoundTrips() {
        let d = freshDefaults()
        CaptureThreshold.save(0.7, d)
        XCTAssertEqual(CaptureThreshold.load(d), 0.7, accuracy: 0.0001)
    }

    func testSaveClampsOutOfRange() {
        let d = freshDefaults()
        CaptureThreshold.save(0.05, d)
        XCTAssertEqual(CaptureThreshold.load(d), 0.3, accuracy: 0.0001)
    }

    func testLoadClampsCorruptStoredValue() {
        let d = freshDefaults()
        d.set(2.0, forKey: CaptureThreshold.key)   // bypass save() clamping
        XCTAssertEqual(CaptureThreshold.load(d), 0.9, accuracy: 0.0001)
    }
}
