import XCTest
@testable import Daybreak

// Covers the @Model entities' initializers, computed accessors, and converters.
final class LocalModelTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testTaskEntityConvertersAndCompletedAt() {
        let done = TaskEntity(day: "2026-07-18", bucket: .urgent, title: "T", note: "n",
                              done: true, scheduledStart: 540, scheduledMinutes: 60,
                              position: 2, auditRecordId: "a1", now: now)
        XCTAssertEqual(done.bucket, .urgent)
        XCTAssertEqual(done.completedAt, now)          // done -> completedAt set
        let task = done.asTask()
        XCTAssertEqual(task.title, "T")
        XCTAssertEqual(task.scheduledStart, 540)
        XCTAssertEqual(task.bucket, .urgent)
        let earlier = done.asEarlier()
        XCTAssertEqual(earlier.title, "T")
        XCTAssertEqual(earlier.bucket, .urgent)

        let open = TaskEntity(day: "2026-07-18", bucket: .extra, title: "O", now: now)
        XCTAssertNil(open.completedAt)                 // not done -> nil
    }

    func testEventEntityConverter() {
        let e = EventEntity(day: "2026-07-18", bucket: .progress, title: "Sync", note: "",
                            startMin: 600, durationMin: 90, now: now)
        XCTAssertEqual(e.bucket, .progress)
        let ev = e.asEvent()
        XCTAssertEqual(ev.startMin, 600)
        XCTAssertEqual(ev.durationMin, 90)
        XCTAssertEqual(ev.bucket, .progress)
    }

    func testCaptureItemAccessors() {
        let c = CaptureItem(text: "call dentist", source: .share, status: .pending, now: now)
        XCTAssertEqual(c.source, .share)
        XCTAssertEqual(c.status, .pending)
        XCTAssertEqual(c.text, "call dentist")
    }

    func testReviewItemAccessors() {
        let r = ReviewItem(captureId: "c1", cleanedTitle: "Call dentist",
                           suggestedBucket: .urgent, suggestedDay: "2026-07-18",
                           suggestedStart: 900, suggestedMinutes: 30, confidence: 0.5,
                           auditRecordId: "a1", now: now)
        XCTAssertEqual(r.suggestedBucket, .urgent)
        XCTAssertEqual(r.confidence, 0.5)
        XCTAssertEqual(r.auditRecordId, "a1")
    }

    func testAuditRecordAccessors() {
        let a = AuditRecord(captureId: "c1", rawInput: "call dentist", chosenBucket: .urgent,
                            confidence: 0.8, autoFiled: true, modelTier: .ruleBased, now: now)
        XCTAssertEqual(a.chosenBucket, .urgent)
        XCTAssertEqual(a.modelTier, .ruleBased)
        XCTAssertTrue(a.autoFiled)
        XCTAssertEqual(a.correctionsJSON, "[]")
    }

    func testRawFallbacksForUnknownStrings() {
        let t = TaskEntity(day: "d", bucket: .urgent, title: "x", now: now)
        t.bucketRaw = "nonsense"
        XCTAssertEqual(t.bucket, .extra)               // unknown bucket -> .extra
        let c = CaptureItem(text: "x", source: .typed, now: now)
        c.sourceRaw = "nonsense"; c.statusRaw = "nonsense"
        XCTAssertEqual(c.source, .typed)               // unknown -> defaults
        XCTAssertEqual(c.status, .pending)
    }
}
