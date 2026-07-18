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
}
