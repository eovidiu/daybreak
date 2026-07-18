import Foundation

// Value-type models live in Models.swift. This file holds the data-gateway protocol and
// the Day helpers.

// @MainActor so a SwiftData-backed conformer's ModelContext is always touched on the
// main actor (Core Data traps otherwise). Cloud/mock conformers are unaffected.
@MainActor
protocol PlannerApi {
    func me() async throws -> User
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, name: String) async throws
    func signOut() async throws
    func day(_ day: String) async throws -> DayData
    func earlier(before: String) async throws -> [EarlierTask]
    func createTask(day: String, bucket: Bucket, title: String) async throws -> PlannerTask
    func patchTask(_ id: String, _ patch: [String: Any?]) async throws
    func deleteTask(_ id: String) async throws
    func createEvent(day: String, bucket: Bucket, title: String,
                     startMin: Int, durationMin: Int) async throws -> PlannerEvent
    func patchEvent(_ id: String, _ patch: [String: Any?]) async throws
    func deleteEvent(_ id: String) async throws

    // Capture pipeline (local-first AI features). A capture is enqueued first (by the
    // capture bar, or by the share extension writing straight to the shared store), then
    // filed through the classifier + Bouncer.
    func enqueueCapture(text: String, source: CaptureSource) async throws -> String
    func pendingCaptures() async throws -> [PendingCapture]
    func fileCapture(captureId: String, classification: Classification,
                     threshold: Double) async throws -> CaptureResult
    func reviews() async throws -> [Review]
    func acceptReview(_ id: String, bucket: Bucket, day: String, title: String,
                      start: Int?, minutes: Int?) async throws -> PlannerTask
    func dismissReview(_ id: String) async throws

    // Today's digest, computed over all local data.
    func digest(today: String) async throws -> Digest

    // Immutable audit trail of classifications and their corrections.
    func auditHistory() async throws -> [AuditEntry]
}

enum Day {
    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func add(_ day: String, _ delta: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day),
              let moved = Calendar.current.date(byAdding: .day, value: delta, to: d)
        else { return day }
        return f.string(from: moved)
    }

    static func label(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return day }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMMM d"
        return out.string(from: d)
    }

    static func shortLabel(_ day: String) -> (weekday: String, dayNum: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return (day, "") }
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        let dn = DateFormatter(); dn.dateFormat = "d"
        return (wd.string(from: d), dn.string(from: d))
    }

    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
