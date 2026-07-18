import Foundation
import SwiftData

// Local-first implementation of PlannerApi backed by SwiftData. Replaces the cloud
// ApiClient on iOS. Auth is a no-op — there is a single implicit local user.
@MainActor
final class LocalStore: PlannerApi {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    // Access the main context lazily inside @MainActor methods so it is first
    // materialized on the real main actor, not wherever the store was constructed.
    private var context: ModelContext { container.mainContext }

    // MARK: auth (local, no account)

    // Removes all local data (used by tests and a future "reset" action).
    func deleteAll() throws {
        try context.delete(model: TaskEntity.self)
        try context.delete(model: EventEntity.self)
        try context.delete(model: CaptureItem.self)
        try context.delete(model: ReviewItem.self)
        try context.delete(model: AuditRecord.self)
        try context.save()
    }

    func me() async throws -> User { User(id: "local", email: "", name: "You") }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String) async throws {}
    func signOut() async throws {}

    // MARK: reads

    func day(_ day: String) async throws -> DayData {
        let tasks = try allTasks()
            .filter { $0.day == day }
            .sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }
        let events = try context.fetch(FetchDescriptor<EventEntity>())
            .filter { $0.day == day }
            .sorted { $0.startMin < $1.startMin }
        return DayData(tasks: tasks.map { $0.asTask() }, events: events.map { $0.asEvent() })
    }

    func earlier(before: String) async throws -> [EarlierTask] {
        try allTasks()
            .filter { !$0.done && $0.day < before }
            .sorted { ($0.day, $0.position) > ($1.day, $1.position) }
            .map { $0.asEarlier() }
    }

    // MARK: tasks

    func createTask(day: String, bucket: Bucket, title: String) async throws -> PlannerTask {
        let position = try nextPosition(day: day)
        let entity = TaskEntity(day: day, bucket: bucket, title: title,
                                position: position, now: Date())
        context.insert(entity)
        try context.save()
        return entity.asTask()
    }

    func patchTask(_ id: String, _ patch: [String: Any?]) async throws {
        guard let t = try taskEntity(id) else { return }
        if let done = patch["done"] as? Bool {
            t.done = done
            t.completedAt = done ? Date() : nil
        }
        if patch.keys.contains("scheduled_start") {
            t.scheduledStart = patch["scheduled_start"] as? Int
        }
        if patch.keys.contains("scheduled_minutes") {
            t.scheduledMinutes = patch["scheduled_minutes"] as? Int
        }
        if let day = patch["day"] as? String { t.day = day }
        if let raw = patch["bucket"] as? String { t.bucketRaw = raw }
        if let title = patch["title"] as? String { t.title = title }
        if let note = patch["note"] as? String { t.note = note }
        if let position = patch["position"] as? Int { t.position = position }
        t.updatedAt = Date()
        try context.save()
    }

    func deleteTask(_ id: String) async throws {
        if let t = try taskEntity(id) { context.delete(t); try context.save() }
    }

    // MARK: events

    func createEvent(day: String, bucket: Bucket, title: String,
                     startMin: Int, durationMin: Int) async throws -> PlannerEvent {
        let entity = EventEntity(day: day, bucket: bucket, title: title,
                                 startMin: startMin, durationMin: durationMin, now: Date())
        context.insert(entity)
        try context.save()
        return entity.asEvent()
    }

    func patchEvent(_ id: String, _ patch: [String: Any?]) async throws {
        guard let e = try eventEntity(id) else { return }
        if let day = patch["day"] as? String { e.day = day }
        if let raw = patch["bucket"] as? String { e.bucketRaw = raw }
        if let title = patch["title"] as? String { e.title = title }
        if let note = patch["note"] as? String { e.note = note }
        if let start = patch["start_min"] as? Int { e.startMin = start }
        if let dur = patch["duration_min"] as? Int { e.durationMin = dur }
        try context.save()
    }

    func deleteEvent(_ id: String) async throws {
        if let e = try eventEntity(id) { context.delete(e); try context.save() }
    }

    // MARK: helpers

    // SwiftData #Predicate with captured variables crashes on this runtime, so
    // fetch-all-and-filter in Swift. Local data volume makes this cheap.
    private func allTasks() throws -> [TaskEntity] {
        try context.fetch(FetchDescriptor<TaskEntity>())
    }

    func taskEntity(_ id: String) throws -> TaskEntity? {
        try allTasks().first { $0.id == id }
    }

    private func eventEntity(_ id: String) throws -> EventEntity? {
        try context.fetch(FetchDescriptor<EventEntity>()).first { $0.id == id }
    }

    private func nextPosition(day: String) throws -> Int {
        (try allTasks().filter { $0.day == day }.map(\.position).max() ?? -1) + 1
    }
}
