import XCTest
@testable import Daybreak

final class DigestServiceTests: XCTestCase {
    let today = "2026-07-15"

    // A local-midnight Date for a yyyy-MM-dd string, optionally offset by hours, built
    // with the same calendar/timezone DigestService uses.
    private func date(_ ymd: String, addingHours hours: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let f = DateFormatter(); f.calendar = cal; f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return cal.date(byAdding: .hour, value: hours, to: f.date(from: ymd)!)!
    }

    private func task(_ id: String, day: String, bucket: Bucket = .urgent, done: Bool = false,
                      position: Int = 0, completedAt: Date? = nil) -> PlannerTask {
        PlannerTask(id: id, day: day, bucket: bucket, title: id, note: "", done: done,
                    scheduledStart: nil, scheduledMinutes: nil, position: position,
                    completedAt: completedAt)
    }

    // MARK: top-3

    func testTop3OrdersByCategoryBucketPositionId() {
        let tasks = [
            task("D", day: "2026-07-16", bucket: .urgent, position: 0),   // future
            task("B", day: "2026-07-14", bucket: .progress, position: 5), // overdue/progress
            task("C", day: "2026-07-15", bucket: .urgent, position: 2),   // today
            task("E", day: "2026-07-10", bucket: .urgent, position: 3),   // overdue/urgent/pos3
            task("A", day: "2026-07-10", bucket: .urgent, position: 0),   // overdue/urgent/pos0
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.top3.map(\.id), ["A", "E", "B"])
    }

    func testTop3ExcludesCompletedAndCapsAtThree() {
        let tasks = [
            task("done", day: today, done: true, position: 0),
            task("t1", day: today, position: 1),
            task("t2", day: today, position: 2),
            task("t3", day: today, position: 3),
            task("t4", day: today, position: 4),
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.top3.map(\.id), ["t1", "t2", "t3"])
    }

    func testTop3IdBreaksTies() {
        let tasks = [
            task("zeta", day: today, bucket: .extra, position: 0),
            task("alpha", day: today, bucket: .extra, position: 0),
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.top3.map(\.id), ["alpha", "zeta"])
    }

    // MARK: stuck

    func testStuckIsOldestOverdueIncomplete() {
        let tasks = [
            task("recent", day: "2026-07-14", position: 0),
            task("oldest", day: "2026-07-01", position: 0),
            task("oldDone", day: "2026-06-20", done: true, position: 0), // completed, ignored
            task("today", day: today, position: 0),                      // not overdue
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.stuck?.id, "oldest")
    }

    func testStuckNilWhenNothingOverdue() {
        let d = DigestService.digest(tasks: [task("t", day: today)], events: [], today: today)
        XCTAssertNil(d.stuck)
    }

    // MARK: small win

    func testSmallWinIsMostRecentWithinThreeDays() {
        let tasks = [
            task("old", day: "2026-07-10", done: true, completedAt: date("2026-07-11")), // 4d, out
            task("mid", day: "2026-07-13", done: true, completedAt: date("2026-07-13")), // in
            task("new", day: "2026-07-14", done: true, completedAt: date("2026-07-14")), // in, newest
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.smallWin?.id, "new")
    }

    func testSmallWinIncludesCutoffBoundary() {
        // Exactly 3 days before midnight today (2026-07-12 00:00) is inside the window.
        let tasks = [task("edge", day: "2026-07-12", done: true,
                          completedAt: date("2026-07-12"))]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertEqual(d.smallWin?.id, "edge")
    }

    func testSmallWinNilWhenNoRecentCompletions() {
        let tasks = [
            task("openTask", day: today),                                        // not done
            task("stale", day: "2026-07-01", done: true, completedAt: date("2026-07-01")),
        ]
        let d = DigestService.digest(tasks: tasks, events: [], today: today)
        XCTAssertNil(d.smallWin)
    }

    // MARK: events + empties

    func testTodayEventsFilteredAndUnranked() {
        let events = [
            PlannerEvent(id: "e1", day: today, bucket: .progress, title: "Sync",
                         note: "", startMin: 600, durationMin: 30),
            PlannerEvent(id: "e2", day: "2026-07-16", bucket: .urgent, title: "Later",
                         note: "", startMin: 540, durationMin: 60),
            PlannerEvent(id: "e3", day: today, bucket: .extra, title: "Lunch",
                         note: "", startMin: 720, durationMin: 45),
        ]
        let d = DigestService.digest(tasks: [], events: events, today: today)
        XCTAssertEqual(d.todayEvents.map(\.id), ["e1", "e3"])  // input order preserved
    }

    func testEmptyInputsGiveEmptyDigest() {
        let d = DigestService.digest(tasks: [], events: [], today: today)
        XCTAssertEqual(d, Digest(top3: [], stuck: nil, smallWin: nil, todayEvents: []))
    }
}
