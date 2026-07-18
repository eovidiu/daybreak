import SwiftUI

@MainActor
final class PlannerStore: ObservableObject {
    let api: PlannerApi
    let classifier: CaptureClassifier
    private let defaults: UserDefaults

    init(api: PlannerApi, classifier: CaptureClassifier = Capture.makeClassifier(),
         defaults: UserDefaults = .standard) {
        self.api = api
        self.classifier = classifier
        self.defaults = defaults
    }

    @Published var user: User?
    @Published var checkedSession = false
    @Published var day: String = Day.today()
    @Published var data = DayData(tasks: [], events: [])
    @Published var earlier: [EarlierTask] = []
    @Published var reviews: [Review] = []
    @Published var errorMessage: String?
    @Published var dayLoadStamp = 0

    private var cache: [String: DayData] = [:]

    func bootstrap() async {
        user = try? await api.me()
        checkedSession = true
        if user != nil { await load() }
    }

    func signOut() async {
        try? await api.signOut()
        user = nil
        cache = [:]
        data = DayData(tasks: [], events: [])
        reviews = []
    }

    func select(day newDay: String) {
        day = newDay
        if let cached = cache[newDay] { data = cached }  // instant render
        Task { await load() }
    }

    func load() async {
        do {
            // Sequential, not concurrent: the local SwiftData store shares one
            // ModelContext, which traps on overlapping access.
            let dayData = try await api.day(day)
            let earlierTasks = try await api.earlier(before: Day.today())
            let queued = try await api.reviews()
            cache[day] = dayData
            data = dayData
            earlier = earlierTasks
            reviews = queued
            dayLoadStamp += 1
        } catch {
            report(error)
        }
    }

    // Optimistic mutation helper: applies locally, syncs, reloads on failure.
    private func sync(_ apply: () -> Void, send: @escaping () async throws -> Void) {
        apply()
        cache[day] = data
        Task {
            do { try await send() } catch {
                report(error)
                await load()
            }
        }
    }

    func addTask(bucket: Bucket, title: String) async {
        do {
            let task = try await api.createTask(day: day, bucket: bucket, title: title)
            data.tasks.append(task)
            cache[day] = data
        } catch {
            report(error)
        }
    }

    // Natural-language capture: classify the line, then let the Bouncer decide. A
    // confident classification auto-files a task; a low-confidence one is queued for
    // review. Threshold is the user's setting.
    func capture(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let c = await classifier.classify(trimmed, today: Day.today())
        do {
            let result = try await api.fileCapture(text: trimmed, classification: c,
                                                   threshold: CaptureThreshold.load(defaults))
            switch result {
            case .filed: await load()
            case .queued(let review): reviews.append(review)
            }
        } catch {
            report(error)
        }
    }

    // Accept a queued review with (possibly edited) values: creates the task, drops the
    // review.
    func acceptReview(_ review: Review, bucket: Bucket, day: String, title: String,
                      start: Int?, minutes: Int?) async {
        do {
            _ = try await api.acceptReview(review.id, bucket: bucket, day: day, title: title,
                                           start: start, minutes: minutes)
            reviews.removeAll { $0.id == review.id }
            await load()
        } catch {
            report(error)
        }
    }

    func dismissReview(_ review: Review) async {
        reviews.removeAll { $0.id == review.id }
        do { try await api.dismissReview(review.id) } catch { report(error) }
    }

    func toggle(_ task: PlannerTask) {
        sync {
            if let i = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[i].done.toggle() }
        } send: { [api] in
            try await api.patchTask(task.id, ["done": !task.done])
        }
    }

    func schedule(_ task: PlannerTask, start: Int?, minutes: Int?) {
        sync {
            if let i = data.tasks.firstIndex(where: { $0.id == task.id }) {
                data.tasks[i].scheduledStart = start
                data.tasks[i].scheduledMinutes = minutes
            }
        } send: { [api] in
            try await api.patchTask(task.id, ["scheduled_start": start,
                                              "scheduled_minutes": minutes])
        }
    }

    func update(_ task: PlannerTask, title: String, note: String, bucket: Bucket) {
        sync {
            if let i = data.tasks.firstIndex(where: { $0.id == task.id }) {
                data.tasks[i].title = title
                data.tasks[i].note = note
                data.tasks[i].bucket = bucket
            }
        } send: { [api] in
            try await api.patchTask(task.id, ["title": title, "note": note,
                                              "bucket": bucket.rawValue])
        }
    }

    func delete(_ task: PlannerTask) {
        sync {
            data.tasks.removeAll { $0.id == task.id }
        } send: { [api] in
            try await api.deleteTask(task.id)
        }
    }

    func addEvent(title: String, bucket: Bucket, start: Int, minutes: Int) async {
        do {
            let ev = try await api.createEvent(day: day, bucket: bucket, title: title,
                                               startMin: start, durationMin: minutes)
            data.events.append(ev)
            cache[day] = data
        } catch {
            report(error)
        }
    }

    func move(_ event: PlannerEvent, toStart start: Int) {
        sync {
            if let i = data.events.firstIndex(where: { $0.id == event.id }) { data.events[i].startMin = start }
        } send: { [api] in
            try await api.patchEvent(event.id, ["start_min": start])
        }
    }

    func moveScheduled(_ task: PlannerTask, toStart start: Int) {
        sync {
            if let i = data.tasks.firstIndex(where: { $0.id == task.id }) { data.tasks[i].scheduledStart = start }
        } send: { [api] in
            try await api.patchTask(task.id, ["scheduled_start": start])
        }
    }

    func update(_ event: PlannerEvent, title: String, note: String, bucket: Bucket,
                start: Int, minutes: Int) {
        sync {
            if let i = data.events.firstIndex(where: { $0.id == event.id }) {
                data.events[i] = PlannerEvent(id: event.id, day: event.day, bucket: bucket,
                                              title: title, note: note,
                                              startMin: start, durationMin: minutes)
            }
        } send: { [api] in
            try await api.patchEvent(event.id, [
                "title": title, "note": note, "bucket": bucket.rawValue,
                "start_min": start, "duration_min": minutes,
            ])
        }
    }

    func delete(_ event: PlannerEvent) {
        sync {
            data.events.removeAll { $0.id == event.id }
        } send: { [api] in
            try await api.deleteEvent(event.id)
        }
    }

    func pullIntoToday(_ task: EarlierTask) {
        earlier.removeAll { $0.id == task.id }
        Task {
            do {
                try await api.patchTask(task.id, ["day": Day.today(),
                                                  "scheduled_start": nil,
                                                  "scheduled_minutes": nil])
                await load()
            } catch { report(error) }
        }
    }

    func deleteEarlier(_ task: EarlierTask) {
        earlier.removeAll { $0.id == task.id }
        Task { try? await api.deleteTask(task.id) }
    }

    private func report(_ error: Error) {
        if (error as? ApiError)?.message == "unauthorized" {
            user = nil
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
