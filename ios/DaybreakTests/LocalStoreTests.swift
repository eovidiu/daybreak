import XCTest
import SwiftData
@testable import Daybreak

@MainActor
final class LocalStoreTests: XCTestCase {
    // SwiftData is unstable when many ModelContainers are created in one process,
    // so share ONE in-memory container across the class and wipe it per test.
    static let container: ModelContainer = {
        try! ModelContainer(
            for: TaskEntity.self, EventEntity.self, CaptureItem.self,
                ReviewItem.self, AuditRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()

    func makeStore() throws -> LocalStore {
        let store = LocalStore(container: Self.container)
        try store.deleteAll()
        return store
    }

    func testLocalIdentityIsAlwaysPresent() async throws {
        let store = try makeStore()
        let user = try await store.me()
        XCTAssertEqual(user.id, "local")
    }

    func testCreateListPatchDeleteTask() async throws {
        let store = try makeStore()
        let created = try await store.createTask(day: "2026-07-18", bucket: .urgent, title: "Ship")
        XCTAssertEqual(created.title, "Ship")

        var data = try await store.day("2026-07-18")
        XCTAssertEqual(data.tasks.count, 1)
        XCTAssertEqual(data.tasks[0].bucket, .urgent)

        try await store.patchTask(created.id, [
            "done": true, "scheduled_start": 540, "scheduled_minutes": 60,
            "bucket": "progress", "title": "Ship it",
        ])
        data = try await store.day("2026-07-18")
        XCTAssertTrue(data.tasks[0].done)
        XCTAssertEqual(data.tasks[0].scheduledStart, 540)
        XCTAssertEqual(data.tasks[0].bucket, .progress)
        XCTAssertEqual(data.tasks[0].title, "Ship it")

        // Clearing a schedule with nulls.
        try await store.patchTask(created.id, ["scheduled_start": nil, "scheduled_minutes": nil])
        data = try await store.day("2026-07-18")
        XCTAssertNil(data.tasks[0].scheduledStart)

        try await store.deleteTask(created.id)
        data = try await store.day("2026-07-18")
        XCTAssertTrue(data.tasks.isEmpty)
    }

    func testCompletedAtSetAndClearedByDone() async throws {
        let store = try makeStore()
        let t = try await store.createTask(day: "2026-07-18", bucket: .extra, title: "X")
        try await store.patchTask(t.id, ["done": true])
        XCTAssertNotNil(try store.taskEntity(t.id)?.completedAt)
        try await store.patchTask(t.id, ["done": false])
        XCTAssertNil(try store.taskEntity(t.id)?.completedAt)
    }

    func testEventLifecycle() async throws {
        let store = try makeStore()
        let ev = try await store.createEvent(day: "2026-07-18", bucket: .progress,
                                             title: "Sync", startMin: 600, durationMin: 90)
        var data = try await store.day("2026-07-18")
        XCTAssertEqual(data.events.count, 1)
        try await store.patchEvent(ev.id, ["start_min": 660, "duration_min": 45,
                                           "title": "Sync v2", "bucket": "urgent"])
        data = try await store.day("2026-07-18")
        XCTAssertEqual(data.events[0].startMin, 660)
        XCTAssertEqual(data.events[0].title, "Sync v2")
        try await store.deleteEvent(ev.id)
        data = try await store.day("2026-07-18")
        XCTAssertTrue(data.events.isEmpty)
    }

    func testEarlierReturnsUnfinishedPastTasks() async throws {
        let store = try makeStore()
        _ = try await store.createTask(day: "2026-07-10", bucket: .urgent, title: "Old open")
        let done = try await store.createTask(day: "2026-07-10", bucket: .extra, title: "Old done")
        try await store.patchTask(done.id, ["done": true])
        let earlier = try await store.earlier(before: "2026-07-18")
        XCTAssertEqual(earlier.map(\.title), ["Old open"])  // done one excluded
    }

    func testDataPersistsInContainer() async throws {
        let store1 = try makeStore()  // wipes, then writes
        _ = try await store1.createTask(day: "2026-07-18", bucket: .urgent, title: "Persisted")
        // A fresh LocalStore over the same container still sees it (no wipe).
        let store2 = LocalStore(container: Self.container)
        let data = try await store2.day("2026-07-18")
        XCTAssertEqual(data.tasks.map(\.title), ["Persisted"])
    }

    func testPositionsIncrementWithinADay() async throws {
        let store = try makeStore()
        let a = try await store.createTask(day: "2026-07-18", bucket: .urgent, title: "A")
        let b = try await store.createTask(day: "2026-07-18", bucket: .urgent, title: "B")
        XCTAssertLessThan(a.position, b.position)
    }

    // MARK: capture review queue (F005)

    private func classification(_ confidence: Double, bucket: Bucket = .urgent,
                                day: String = "2026-07-18", start: Int? = 540,
                                minutes: Int? = 30, title: String = "Call bank",
                                tier: ModelTier = .ruleBased) -> Classification {
        Classification(bucket: bucket, day: day, startMin: start, durationMin: minutes,
                       cleanedTitle: title, confidence: confidence, tier: tier)
    }

    // Enqueue-then-file, mirroring the capture pipeline.
    @discardableResult
    private func file(_ store: LocalStore, _ c: Classification, text: String = "x",
                      source: CaptureSource = .typed,
                      threshold: Double = 0.6) async throws -> CaptureResult {
        let id = try await store.enqueueCapture(text: text, source: source)
        return try await store.fileCapture(captureId: id, classification: c, threshold: threshold)
    }

    func testHighConfidenceAutoFilesTaskWithAudit() async throws {
        let store = try makeStore()
        let result = try await file(store, classification(0.9, tier: .foundationModels),
                                    text: "call the bank at 9")
        guard case .filed(let task) = result else { return XCTFail("expected filed") }
        XCTAssertEqual(task.title, "Call bank")
        XCTAssertEqual(task.scheduledStart, 540)

        let day = try await store.day("2026-07-18")
        XCTAssertEqual(day.tasks.count, 1)                 // task exists
        let queued = try await store.reviews()
        XCTAssertTrue(queued.isEmpty)                      // nothing queued

        let entity = try store.taskEntity(task.id)
        XCTAssertNotNil(entity?.auditRecordId)             // task links its audit
    }

    func testLowConfidenceQueuesReviewAndFilesNoTask() async throws {
        let store = try makeStore()
        let result = try await file(store, classification(0.4, bucket: .extra,
                                                          title: "Reorganize photos"),
                                    text: "maybe reorganize photos")
        guard case .queued(let review) = result else { return XCTFail("expected queued") }
        XCTAssertEqual(review.title, "Reorganize photos")
        XCTAssertEqual(review.confidence, 0.4, accuracy: 0.0001)

        let day = try await store.day("2026-07-18")
        XCTAssertTrue(day.tasks.isEmpty)                   // no task
        let queued = try await store.reviews()
        XCTAssertEqual(queued.map(\.id), [review.id])
    }

    func testAcceptReviewCreatesTaskFromEditedValues() async throws {
        let store = try makeStore()
        guard case .queued(let review) = try await file(
            store, classification(0.4, bucket: .extra, start: nil, minutes: nil,
                                  title: "Read design book"),
            text: "read design book") else { return XCTFail("expected queued") }

        let task = try await store.acceptReview(review.id, bucket: .progress, day: "2026-07-19",
                                                title: "Read the design book", start: 600, minutes: 45)
        XCTAssertEqual(task.bucket, .progress)             // edited bucket honored
        XCTAssertEqual(task.title, "Read the design book")
        XCTAssertEqual(task.scheduledStart, 600)
        let queued = try await store.reviews()
        XCTAssertTrue(queued.isEmpty)                      // review consumed
        let day = try await store.day("2026-07-19")
        XCTAssertEqual(day.tasks.count, 1)
    }

    func testDismissReviewDropsItWithoutTask() async throws {
        let store = try makeStore()
        guard case .queued(let review) = try await file(
            store, classification(0.35, bucket: .extra),
            text: "someday sort inbox") else { return XCTFail("expected queued") }
        try await store.dismissReview(review.id)
        let queued = try await store.reviews()
        XCTAssertTrue(queued.isEmpty)
        let day = try await store.day("2026-07-18")
        XCTAssertTrue(day.tasks.isEmpty)
    }

    func testReviewsSortedByCreation() async throws {
        let store = try makeStore()
        try await file(store, classification(0.4, title: "First"), text: "a")
        try await file(store, classification(0.4, title: "Second"), text: "b")
        let queued = try await store.reviews()
        XCTAssertEqual(queued.map(\.title), ["First", "Second"])
    }

    // MARK: capture pipeline (F008)

    func testEnqueueAndPendingCaptures() async throws {
        let store = try makeStore()
        let shareId = try await store.enqueueCapture(text: "from share", source: .share)
        _ = try await store.enqueueCapture(text: "typed one", source: .typed)
        let pending = try await store.pendingCaptures()
        XCTAssertEqual(pending.map(\.text), ["from share", "typed one"])

        // Filing one takes it out of the pending set.
        _ = try await store.fileCapture(captureId: shareId, classification: classification(0.9),
                                        threshold: 0.6)
        let remaining = try await store.pendingCaptures()
        XCTAssertEqual(remaining.map(\.text), ["typed one"])
    }

    func testFileCaptureUnknownIdThrows() async throws {
        let store = try makeStore()
        do {
            _ = try await store.fileCapture(captureId: "missing",
                                            classification: classification(0.9), threshold: 0.6)
            XCTFail("expected a throw for an unknown capture id")
        } catch {
            // expected
        }
    }

    // MARK: correction / audit loop (F007)

    // Auto-files a task (0.9 >= 0.6) so it carries an auditRecordId, and returns its id.
    private func fileAuditedTask(_ store: LocalStore, day: String = "2026-07-18",
                                 bucket: Bucket = .urgent) async throws -> String {
        guard case .filed(let task) = try await file(
            store, classification(0.9, bucket: bucket, day: day, start: 540),
            text: "call the bank") else { XCTFail("expected filed"); return "" }
        return task.id
    }

    func testBucketAndScheduleChangesAreLoggedAsCorrections() async throws {
        let store = try makeStore()
        let id = try await fileAuditedTask(store)
        try await store.patchTask(id, ["bucket": "progress"])
        try await store.patchTask(id, ["scheduled_start": 600])
        try await store.patchTask(id, ["day": "2026-07-20"])

        let corrections = try await store.auditHistory().first?.corrections ?? []
        XCTAssertEqual(corrections.map(\.field), ["bucket", "scheduledStart", "day"])
        XCTAssertEqual(corrections[0].old, "urgent")
        XCTAssertEqual(corrections[0].new, "progress")
        XCTAssertEqual(corrections[1].new, "600")     // scheduledStart 540 -> 600
        XCTAssertEqual(corrections[2].new, "2026-07-20")
    }

    func testTitleAndNoteEditsAreNotCorrections() async throws {
        let store = try makeStore()
        let id = try await fileAuditedTask(store)
        try await store.patchTask(id, ["title": "Call the credit union", "note": "urgent"])
        let corrections = try await store.auditHistory().first?.corrections ?? []
        XCTAssertTrue(corrections.isEmpty)
    }

    func testNoOpChangeIsNotLogged() async throws {
        let store = try makeStore()
        let id = try await fileAuditedTask(store, bucket: .urgent)
        try await store.patchTask(id, ["bucket": "urgent"])   // same value
        let corrections = try await store.auditHistory().first?.corrections ?? []
        XCTAssertTrue(corrections.isEmpty)
    }

    func testUnclearingScheduleLogsCorrection() async throws {
        let store = try makeStore()
        let id = try await fileAuditedTask(store)             // starts at 540
        try await store.patchTask(id, ["scheduled_start": nil])
        let corrections = try await store.auditHistory().first?.corrections ?? []
        XCTAssertEqual(corrections.map(\.field), ["scheduledStart"])
        XCTAssertEqual(corrections[0].old, "540")
        XCTAssertEqual(corrections[0].new, "")               // cleared
    }

    func testUnauditedTaskPatchLogsNothing() async throws {
        let store = try makeStore()
        let t = try await store.createTask(day: "2026-07-18", bucket: .urgent, title: "Manual")
        try await store.patchTask(t.id, ["bucket": "extra"])  // no auditRecordId -> no crash
        let history = try await store.auditHistory()
        XCTAssertTrue(history.isEmpty)
    }
}
