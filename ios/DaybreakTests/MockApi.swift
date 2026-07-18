import Foundation
@testable import Daybreak

final class MockApi: PlannerApi, @unchecked Sendable {
    var user: User? = User(id: "u1", email: "a@b.co", name: "A")
    var tasks: [PlannerTask] = []
    var events: [PlannerEvent] = []
    var earlierTasks: [EarlierTask] = []
    var failNext = false
    var unauthorized = false

    private func guardOk() throws {
        if unauthorized { throw ApiError(message: "unauthorized") }
        if failNext { failNext = false; throw ApiError(message: "boom") }
    }

    func me() async throws -> User {
        try guardOk()
        guard let user else { throw ApiError(message: "unauthorized") }
        return user
    }

    func signIn(email: String, password: String) async throws { try guardOk() }
    func signUp(email: String, password: String, name: String) async throws { try guardOk() }
    func signOut() async throws {}

    func day(_ day: String) async throws -> DayData {
        try guardOk()
        return DayData(tasks: tasks.filter { $0.day == day },
                       events: events.filter { $0.day == day })
    }

    func earlier(before: String) async throws -> [EarlierTask] {
        try guardOk()
        return earlierTasks
    }

    func createTask(day: String, bucket: Bucket, title: String) async throws -> PlannerTask {
        try guardOk()
        let t = PlannerTask(id: UUID().uuidString, day: day, bucket: bucket, title: title,
                            note: "", done: false, scheduledStart: nil,
                            scheduledMinutes: nil, position: tasks.count)
        tasks.append(t)
        return t
    }

    func patchTask(_ id: String, _ patch: [String: Any?]) async throws {
        try guardOk()
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let v = patch["scheduled_start"] { tasks[i].scheduledStart = v as? Int }
        if let v = patch["scheduled_minutes"] { tasks[i].scheduledMinutes = v as? Int }
        if let day = patch["day"] as? String { tasks[i].day = day }
    }
    func deleteTask(_ id: String) async throws { try guardOk() }

    func createEvent(day: String, bucket: Bucket, title: String,
                     startMin: Int, durationMin: Int) async throws -> PlannerEvent {
        try guardOk()
        let e = PlannerEvent(id: UUID().uuidString, day: day, bucket: bucket, title: title,
                             note: "", startMin: startMin, durationMin: durationMin)
        events.append(e)
        return e
    }

    func patchEvent(_ id: String, _ patch: [String: Any?]) async throws { try guardOk() }
    func deleteEvent(_ id: String) async throws { try guardOk() }

    // MARK: capture review queue

    var reviewQueue: [Review] = []

    private func insertTask(day: String, bucket: Bucket, title: String,
                            start: Int?, minutes: Int?) -> PlannerTask {
        let t = PlannerTask(id: UUID().uuidString, day: day, bucket: bucket, title: title,
                            note: "", done: false, scheduledStart: start,
                            scheduledMinutes: minutes, position: tasks.count)
        tasks.append(t)
        return t
    }

    var pendingQueue: [PendingCapture] = []

    func enqueueCapture(text: String, source: CaptureSource) async throws -> String {
        try guardOk()
        let id = UUID().uuidString
        pendingQueue.append(PendingCapture(id: id, text: text))
        return id
    }

    func pendingCaptures() async throws -> [PendingCapture] { try guardOk(); return pendingQueue }

    func fileCapture(captureId: String, classification c: Classification,
                     threshold: Double) async throws -> CaptureResult {
        try guardOk()
        pendingQueue.removeAll { $0.id == captureId }
        if Bouncer.autoFiles(confidence: c.confidence, threshold: threshold) {
            return .filed(insertTask(day: c.day, bucket: c.bucket, title: c.cleanedTitle,
                                     start: c.startMin, minutes: c.durationMin))
        }
        let r = Review(id: UUID().uuidString, title: c.cleanedTitle, bucket: c.bucket,
                       day: c.day, start: c.startMin, minutes: c.durationMin,
                       confidence: c.confidence)
        reviewQueue.append(r)
        return .queued(r)
    }

    func reviews() async throws -> [Review] { try guardOk(); return reviewQueue }

    func acceptReview(_ id: String, bucket: Bucket, day: String, title: String,
                      start: Int?, minutes: Int?) async throws -> PlannerTask {
        try guardOk()
        reviewQueue.removeAll { $0.id == id }
        return insertTask(day: day, bucket: bucket, title: title, start: start, minutes: minutes)
    }

    func dismissReview(_ id: String) async throws {
        try guardOk()
        reviewQueue.removeAll { $0.id == id }
    }

    func digest(today: String) async throws -> Digest {
        try guardOk()
        return DigestService.digest(tasks: tasks, events: events, today: today)
    }

    var auditEntries: [AuditEntry] = []
    func auditHistory() async throws -> [AuditEntry] { try guardOk(); return auditEntries }
}

// Emits a fixed classification so capture-flow tests are deterministic.
struct StubClassifier: CaptureClassifier {
    let result: Classification
    func classify(_ text: String, today: String) async -> Classification { result }
}
