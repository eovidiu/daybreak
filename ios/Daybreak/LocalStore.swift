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
        try recordCorrections(for: t, patch: patch)  // before the values change
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

    // MARK: capture review queue

    // Enqueues a raw capture (pending classification). Used by the capture bar and by the
    // share extension writing directly to the shared store.
    func enqueueCapture(text: String, source: CaptureSource) async throws -> String {
        let item = CaptureItem(text: text, source: source, status: .pending, now: Date())
        context.insert(item)
        try context.save()
        return item.id
    }

    func pendingCaptures() async throws -> [PendingCapture] {
        try context.fetch(FetchDescriptor<CaptureItem>())
            .filter { $0.status == .pending }
            .sorted { $0.createdAt < $1.createdAt }
            .map { PendingCapture(id: $0.id, text: $0.text) }
    }

    // Writes one AuditRecord for the capture; auto-files a task when confidence clears the
    // threshold, otherwise queues a ReviewItem and creates no task. Marks the capture.
    func fileCapture(captureId: String, classification c: Classification,
                     threshold: Double) async throws -> CaptureResult {
        guard let capture = try captureItem(captureId) else {
            throw ApiError(message: "capture not found")
        }
        let now = Date()
        let autoFiled = Bouncer.autoFiles(confidence: c.confidence, threshold: threshold)
        let audit = AuditRecord(captureId: capture.id, rawInput: capture.text,
                                chosenBucket: c.bucket, confidence: c.confidence,
                                autoFiled: autoFiled, modelTier: c.tier, now: now)
        context.insert(audit)

        if autoFiled {
            let task = TaskEntity(day: c.day, bucket: c.bucket, title: c.cleanedTitle,
                                  scheduledStart: c.startMin, scheduledMinutes: c.durationMin,
                                  position: try nextPosition(day: c.day),
                                  auditRecordId: audit.id, now: now)
            capture.statusRaw = CaptureStatus.filed.rawValue
            context.insert(task)
            try context.save()
            return .filed(task.asTask())
        }

        let review = ReviewItem(captureId: capture.id, cleanedTitle: c.cleanedTitle,
                                suggestedBucket: c.bucket, suggestedDay: c.day,
                                suggestedStart: c.startMin, suggestedMinutes: c.durationMin,
                                confidence: c.confidence, auditRecordId: audit.id, now: now)
        capture.statusRaw = CaptureStatus.classified.rawValue
        context.insert(review)
        try context.save()
        return .queued(review.asReview())
    }

    func reviews() async throws -> [Review] {
        try context.fetch(FetchDescriptor<ReviewItem>())
            .sorted { $0.createdAt < $1.createdAt }
            .map { $0.asReview() }
    }

    func acceptReview(_ id: String, bucket: Bucket, day: String, title: String,
                      start: Int?, minutes: Int?) async throws -> PlannerTask {
        guard let review = try reviewEntity(id) else { throw ApiError(message: "not found") }
        let task = TaskEntity(day: day, bucket: bucket, title: title,
                              scheduledStart: start, scheduledMinutes: minutes,
                              position: try nextPosition(day: day),
                              auditRecordId: review.auditRecordId, now: Date())
        context.insert(task)
        context.delete(review)
        try context.save()
        return task.asTask()
    }

    func dismissReview(_ id: String) async throws {
        if let review = try reviewEntity(id) { context.delete(review); try context.save() }
    }

    func digest(today: String) async throws -> Digest {
        let tasks = try allTasks().map { $0.asTask() }
        let events = try context.fetch(FetchDescriptor<EventEntity>()).map { $0.asEvent() }
        return DigestService.digest(tasks: tasks, events: events, today: today)
    }

    // MARK: audit history

    func auditHistory() async throws -> [AuditEntry] {
        try context.fetch(FetchDescriptor<AuditRecord>())
            .sorted { $0.createdAt > $1.createdAt }   // newest first
            .map { record in
                AuditEntry(id: record.id, rawInput: record.rawInput,
                           bucket: record.chosenBucket, confidence: record.confidence,
                           autoFiled: record.autoFiled, tier: record.modelTier,
                           createdAt: record.createdAt,
                           corrections: CorrectionLog.decode(record.correctionsJSON))
            }
    }

    // Appends a {field,old,new,at} correction to a task's linked AuditRecord for each of
    // bucket / day / scheduledStart that this patch actually changes. Append-only; title
    // and note edits are not corrections.
    private func recordCorrections(for t: TaskEntity, patch: [String: Any?]) throws {
        guard let auditId = t.auditRecordId, let audit = try auditEntity(auditId) else { return }
        var log = CorrectionLog.decode(audit.correctionsJSON)
        let now = Date()
        var appended = false

        if let raw = patch["bucket"] as? String, raw != t.bucketRaw {
            log.append(Correction(field: "bucket", old: t.bucketRaw, new: raw, at: now))
            appended = true
        }
        if let day = patch["day"] as? String, day != t.day {
            log.append(Correction(field: "day", old: t.day, new: day, at: now))
            appended = true
        }
        if patch.keys.contains("scheduled_start") {
            let newStart = patch["scheduled_start"] as? Int
            if newStart != t.scheduledStart {
                log.append(Correction(field: "scheduledStart",
                                      old: t.scheduledStart.map(String.init) ?? "",
                                      new: newStart.map(String.init) ?? "", at: now))
                appended = true
            }
        }
        if appended { audit.correctionsJSON = CorrectionLog.encode(log) }
    }

    private func auditEntity(_ id: String) throws -> AuditRecord? {
        try context.fetch(FetchDescriptor<AuditRecord>()).first { $0.id == id }
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

    private func reviewEntity(_ id: String) throws -> ReviewItem? {
        try context.fetch(FetchDescriptor<ReviewItem>()).first { $0.id == id }
    }

    private func captureItem(_ id: String) throws -> CaptureItem? {
        try context.fetch(FetchDescriptor<CaptureItem>()).first { $0.id == id }
    }

    private func nextPosition(day: String) throws -> Int {
        (try allTasks().filter { $0.day == day }.map(\.position).max() ?? -1) + 1
    }
}
