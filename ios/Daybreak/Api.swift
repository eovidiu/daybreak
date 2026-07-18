import Foundation

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case urgent, progress, extra
    var id: String { rawValue }
    var title: String {
        switch self {
        case .urgent: "Urgent"
        case .progress: "Progress"
        case .extra: "Extras"
        }
    }
    var subtitle: String {
        switch self {
        case .urgent: "things with teeth"
        case .progress: "the long game"
        case .extra: "if there's room"
        }
    }
}

struct PlannerTask: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
    var done: Bool
    var scheduledStart: Int?
    var scheduledMinutes: Int?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id, day, bucket, title, note, done, position
        case scheduledStart = "scheduled_start"
        case scheduledMinutes = "scheduled_minutes"
    }
}

struct PlannerEvent: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
    var startMin: Int
    var durationMin: Int

    enum CodingKeys: String, CodingKey {
        case id, day, bucket, title, note
        case startMin = "start_min"
        case durationMin = "duration_min"
    }
}

struct EarlierTask: Codable, Identifiable, Equatable {
    let id: String
    var day: String
    var bucket: Bucket
    var title: String
    var note: String
}

struct DayData: Codable, Equatable {
    var tasks: [PlannerTask]
    var events: [PlannerEvent]
}

struct User: Codable, Equatable {
    let id: String
    let email: String
    let name: String
}

struct ApiError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

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
