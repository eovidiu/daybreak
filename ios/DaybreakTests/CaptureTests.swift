import XCTest
@testable import Daybreak

final class CaptureTests: XCTestCase {
    let clf = RuleBasedClassifier()
    let today = "2026-07-15"  // Wednesday

    func c(_ text: String) -> Classification { clf.classifySync(text, today: today) }

    // MARK: bucket + confidence

    func testBucketByKeyword() {
        XCTAssertEqual(c("call the client").bucket, .urgent)
        XCTAssertEqual(c("plan the roadmap").bucket, .progress)
        XCTAssertEqual(c("tidy the desk").bucket, .extra)
    }

    func testZeroKeywordsFallsToExtra() {
        let r = c("buy some milk")
        XCTAssertEqual(r.bucket, .extra)
        XCTAssertEqual(r.confidence, 0.40, accuracy: 0.001)
    }

    func testSingleKeywordIsHighConfidence() {
        XCTAssertEqual(c("call the client").confidence, 0.95, accuracy: 0.001)
    }

    func testTieBreaksToUrgent() {
        let r = c("call and plan")  // urgent(call)=1, progress(plan)=1
        XCTAssertEqual(r.bucket, .urgent)
        XCTAssertEqual(r.confidence, 0.5, accuracy: 0.001)  // tie -> margin 0 -> 0.5
    }

    func testWholeTokenMatchOnly() {
        // "payment" must NOT match "pay"; "emails" must NOT match "email".
        let r = c("track payment emails")
        XCTAssertEqual(r.bucket, .extra)  // no whole-token urgent keyword
        XCTAssertEqual(r.confidence, 0.40, accuracy: 0.001)
    }

    // MARK: date

    func testToday() { XCTAssertEqual(c("call today").day, "2026-07-15") }
    func testTomorrow() { XCTAssertEqual(c("gym tomorrow").day, "2026-07-16") }
    func testInNDays() { XCTAssertEqual(c("review in 3 days").day, "2026-07-18") }

    func testBareWeekdayRollsForward() {
        XCTAssertEqual(c("call monday").day, "2026-07-20")     // next Monday
        XCTAssertEqual(c("call tuesday").day, "2026-07-21")    // next Tuesday
        XCTAssertEqual(c("call wednesday").day, "2026-07-22")  // today excluded -> next week
    }

    func testNextWeekdayAddsAWeek() {
        XCTAssertEqual(c("call next tuesday").day, "2026-07-28")  // 07-21 + 7
    }

    func testTonightSetsEveningAndUrgent() {
        let r = c("dinner tonight")
        XCTAssertEqual(r.day, "2026-07-15")
        XCTAssertEqual(r.startMin, 20 * 60)   // 20:00 default
        XCTAssertEqual(r.bucket, .urgent)     // "tonight" is an urgent keyword
    }

    // MARK: time

    func testClockFormats() {
        XCTAssertEqual(c("meet at 3pm").startMin, 15 * 60)
        XCTAssertEqual(c("meet at 3:30pm").startMin, 15 * 60 + 30)
        XCTAssertEqual(c("standup 15:00").startMin, 15 * 60)
        XCTAssertEqual(c("open at 9").startMin, 9 * 60)
        XCTAssertNil(c("read a book").startMin)
    }

    // MARK: duration

    func testDurations() {
        XCTAssertEqual(c("focus for 30 min").durationMin, 30)
        XCTAssertEqual(c("block 30m").durationMin, 30)
        XCTAssertEqual(c("deep work 1 hour").durationMin, 60)
        XCTAssertEqual(c("nap 1h").durationMin, 60)
        XCTAssertNil(c("quick note").durationMin)
    }

    // MARK: cleaned title + full example

    func testCleanedTitleStripsDateTimeDuration() {
        XCTAssertEqual(c("gym tomorrow").cleanedTitle, "Gym")
        XCTAssertEqual(c("call the dentist at 3pm").cleanedTitle, "Call the dentist")
    }

    func testFullExample() {
        let r = c("call the dentist next Tuesday 3pm for 30 min")
        XCTAssertEqual(r.bucket, .urgent)
        XCTAssertEqual(r.day, "2026-07-28")
        XCTAssertEqual(r.startMin, 15 * 60)
        XCTAssertEqual(r.durationMin, 30)
        XCTAssertEqual(r.cleanedTitle, "Call the dentist")
        XCTAssertEqual(r.confidence, 0.95, accuracy: 0.001)
    }

    func testAsyncMatchesSync() async {
        let sync = clf.classifySync("call today", today: today)
        let async = await clf.classify("call today", today: today)
        XCTAssertEqual(sync, async)
    }
}
