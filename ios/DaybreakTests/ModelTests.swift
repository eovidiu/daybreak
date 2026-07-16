import XCTest
@testable import Daybreak

final class ModelTests: XCTestCase {
    func testDayArithmeticAndLabels() {
        XCTAssertEqual(Day.add("2026-07-16", 1), "2026-07-17")
        XCTAssertEqual(Day.add("2026-07-16", -1), "2026-07-15")
        XCTAssertEqual(Day.add("not-a-day", 1), "not-a-day")
        XCTAssertTrue(Day.label("2026-07-16").contains("July"))
        XCTAssertEqual(Day.label("bad"), "bad")
        let short = Day.shortLabel("2026-07-16")
        XCTAssertFalse(short.weekday.isEmpty)
        XCTAssertEqual(short.dayNum, "16")
        XCTAssertEqual(Day.shortLabel("bad").dayNum, "")
        XCTAssertEqual(Day.time(540), "09:00")
        XCTAssertEqual(Day.time(75), "01:15")
        XCTAssertFalse(Day.today().isEmpty)
    }

    func testBucketMetadata() {
        XCTAssertEqual(Bucket.urgent.title, "Urgent")
        XCTAssertEqual(Bucket.progress.title, "Progress")
        XCTAssertEqual(Bucket.extra.title, "Extras")
        for b in Bucket.allCases { XCTAssertFalse(b.subtitle.isEmpty) }
    }

    func testTaskDecodingFromApiShape() throws {
        let jsonData = """
        {"id":"t1","day":"2026-07-16","bucket":"urgent","title":"Do","note":"",
         "done":false,"scheduled_start":540,"scheduled_minutes":60,"position":0}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(PlannerTask.self, from: jsonData)
        XCTAssertEqual(task.scheduledStart, 540)
        XCTAssertEqual(task.bucket, .urgent)
    }

    func testEventDecodingFromApiShape() throws {
        let jsonData = """
        {"id":"e1","day":"2026-07-16","bucket":"progress","title":"Sync","note":"n",
         "start_min":600,"duration_min":90}
        """.data(using: .utf8)!
        let event = try JSONDecoder().decode(PlannerEvent.self, from: jsonData)
        XCTAssertEqual(event.startMin, 600)
        XCTAssertEqual(event.durationMin, 90)
    }

    func testApiClientReadsEnvironmentBase() {
        let client = ApiClient()
        XCTAssertEqual(client.base.scheme, "https")
    }
}
